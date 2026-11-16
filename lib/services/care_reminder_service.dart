import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/care_reminder.dart';
import 'device_status_service.dart';
import 'local_profile_store.dart';
import 'sensor_service.dart';

/// Litter box notifications:
///  1. every time the cat visits the box and does their business
///  2. the box has not been cleaned for 2 weeks
///
/// The Cloud Function (functions/litter_notifications.js) sends both as push
/// messages, so they arrive even when the app is closed. This class registers
/// the phone for those pushes, remembers when the owner last cleaned the box
/// (the "I cleaned it" button on Home) and shows pushes that arrive while the
/// app is open.
class CareReminderService {
  CareReminderService._();
  static final CareReminderService instance = CareReminderService._();

  static const _channelId = 'care_reminders';
  static const _channelName = 'Litter box notifications';
  static const _channelDesc =
      'Alerts for litter box visits and cleaning reminders';
  static const _cleanNotificationId = 1002;
  static const Duration _recheckEvery = Duration(minutes: 15);

  final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();

  FirebaseDatabase get _db => FirebaseDatabase.instanceFor(
        app: Firebase.app(),
        databaseURL: SensorService.databaseUrl,
      );

  /// Latest cleaning status (null until the first check finishes).
  final ValueNotifier<CleaningStatus?> status =
      ValueNotifier<CleaningStatus?>(null);

  SharedPreferences? _prefs;
  String? _uid;
  String? _deviceId;
  String? _attachedId;
  String? _token;
  StreamSubscription<String>? _tokenSub;
  Timer? _timer;
  bool _localReady = false;

  // ------------------------------------------------------------ lifecycle

  Future<void> start() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) return;
    _uid = uid;
    status.value = null;

    _prefs ??= await SharedPreferences.getInstance();
    await _initLocalNotifications();
    await _seedBaseline();
    await _attachDevice();
    if (_uid != uid) return;

    _timer?.cancel();
    _timer = Timer.periodic(_recheckEvery, (_) async {
      await _attachDevice();
      _evaluate();
    });
    _evaluate();
  }

  /// Sign-out / leaving the main screen: stop pushes for this phone.
  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    final tokenSub = _tokenSub;
    final deviceId = _deviceId;
    final token = _token;
    _tokenSub = null;
    _uid = null;
    _deviceId = null;
    _attachedId = null;
    _token = null;
    await tokenSub?.cancel();
    if (deviceId != null && token != null) {
      try {
        await _db
            .ref('devices/$deviceId/fcmTokens/$token')
            .remove()
            .timeout(const Duration(seconds: 5));
      } catch (e) {
        debugPrint('Removing push token failed: $e');
      }
    }
  }

  Future<void> checkNow() async => _evaluate();

  // -------------------------------------------------------- owner actions

  /// The owner tapped "I cleaned it": restart the 2-week timer here and on
  /// the server, and clear any cleaning notification that is still showing.
  Future<void> markCleaned() async {
    final prefs = _prefs;
    if (prefs == null) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    await prefs.setInt(_k('last_clean'), now);

    final id = _deviceId;
    if (id != null) {
      try {
        await _db.ref('devices/$id/care').update({
          'last_clean': now,
          'notified_clean': null, // lets the next 2-week reminder fire again
        }).timeout(const Duration(seconds: 8));
      } catch (e) {
        debugPrint('markCleaned sync failed: $e');
      }
    }
    await _cancelSystemNotification(_cleanNotificationId);
    _evaluate();
  }

  /// Call after a notification switch in Settings changes.
  Future<void> syncPrefs() async {
    final id = _deviceId;
    final token = _token;
    if (id != null && token != null) await _saveToken(id, token);
  }

  /// Settings -> "Send test reminder": a real system notification.
  Future<void> preview(LitterAlert alert) async {
    switch (alert) {
      case LitterAlert.catVisit:
        await _show(
          id: _visitNotificationId(),
          title: 'Litter box visit',
          body: 'Your cat just peed in the litter box.',
        );
      case LitterAlert.cleanOverdue:
        await _show(
          id: _cleanNotificationId,
          title: 'Time to clean the litter box',
          body: "The litter box hasn't been cleaned for 14 days. "
              'Give it a good clean and tap "I cleaned it" in the app.',
        );
    }
  }

  /// A push arrived while the app is open (Android does not draw those
  /// itself), so show it as a system notification too.
  Future<void> showFromRemote({
    required Map<String, dynamic> data,
    String? title,
    String? body,
  }) async {
    final type = (data['type'] ?? data['task'])?.toString();
    final isClean = type == LitterAlert.cleanOverdue.type;
    await _show(
      // cleaning reminder replaces itself; every visit gets its own entry
      id: isClean ? _cleanNotificationId : _visitNotificationId(),
      title: (title == null || title.isEmpty) ? 'PurrClean' : title,
      body: body ?? '',
    );
  }

  int _visitNotificationId() =>
      (DateTime.now().millisecondsSinceEpoch ~/ 1000) % 2000000000;

  // ------------------------------------------------------- device & push

  Future<void> _attachDevice() async {
    final uid = _uid;
    if (uid == null) return;
    final id = await DeviceStatusService.instance.resolveActiveDeviceId();
    if (_uid != uid) return;
    if (id == _attachedId) return;

    _deviceId = id;
    _attachedId = id;
    await _syncCleanState(id);
    await _registerPush(id);
    _evaluate();
  }

  /// The server's "last cleaned" time wins; if the server has none yet, the
  /// one from this phone is uploaded (the Cloud Function needs it).
  Future<void> _syncCleanState(String id) async {
    final prefs = _prefs;
    if (prefs == null) return;
    try {
      final ref = _db.ref('devices/$id/care/last_clean');
      final snap = await ref.get().timeout(const Duration(seconds: 8));
      final v = snap.value;
      if (v is num) {
        await prefs.setInt(_k('last_clean'), v.toInt());
      } else {
        final local = prefs.getInt(_k('last_clean'));
        if (local != null) await ref.set(local);
      }
    } catch (e) {
      debugPrint('Syncing clean state failed: $e');
    }
  }

  Future<void> _registerPush(String id) async {
    try {
      final messaging = FirebaseMessaging.instance;
      final token = await messaging.getToken();
      if (token != null) await _saveToken(id, token);
      _tokenSub ??= messaging.onTokenRefresh.listen((newToken) {
        final deviceId = _deviceId;
        if (deviceId != null) _saveToken(deviceId, newToken);
      });
    } catch (e) {
      debugPrint('Push registration failed: $e');
    }
  }

  Future<void> _saveToken(String deviceId, String token) async {
    final uid = _uid;
    if (uid == null) return;
    _token = token;
    final visit = await LocalProfileStore.loadNotificationPref(
        uid, LitterAlert.catVisit.prefKey);
    final clean = await LocalProfileStore.loadNotificationPref(
        uid, LitterAlert.cleanOverdue.prefKey);
    final health =
        await LocalProfileStore.loadNotificationPref(uid, 'health_anomaly');
    try {
      await _db.ref('devices/$deviceId/fcmTokens/$token').set({
        'uid': uid,
        'visit': visit,
        'clean': clean,
        'health': health,
        'updatedAt': ServerValue.timestamp,
      }).timeout(const Duration(seconds: 8));
    } catch (e) {
      debugPrint('Saving push token failed: $e');
    }
    try {
      await _db
          .ref('careDevices/$deviceId')
          .set(true)
          .timeout(const Duration(seconds: 8));
    } catch (e) {
      debugPrint('Saving careDevices failed: $e');
    }
  }

  // ------------------------------------------------------ status (card)

  void _evaluate() {
    if (_prefs == null || _uid == null) return;
    final now = DateTime.now();
    final lastClean = _readDate('last_clean') ?? now;
    final days = now.difference(lastClean).inDays;
    status.value = CleaningStatus(
      lastCleaned: lastClean,
      daysSinceClean: days,
      overdue: days >= CleaningStatus.cleanAfterDays,
    );
  }

  // ------------------------------------------------------------- storage

  String _k(String name) => 'care_${name}_$_uid';

  DateTime? _readDate(String name) {
    final ms = _prefs?.getInt(_k(name));
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  /// First run: start the 2-week timer from today.
  Future<void> _seedBaseline() async {
    final prefs = _prefs;
    if (prefs == null) return;
    if (prefs.getInt(_k('last_clean')) == null) {
      await prefs.setInt(
          _k('last_clean'), DateTime.now().millisecondsSinceEpoch);
    }
  }

  // ------------------------------------------------- system notifications

  Future<void> _initLocalNotifications() async {
    if (_localReady) return;
    try {
      await _local.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/launcher_icon'),
          iOS: DarwinInitializationSettings(),
        ),
      );
      // The Cloud Function sends its pushes to this channel.
      await _local
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(
            const AndroidNotificationChannel(
              _channelId,
              _channelName,
              description: _channelDesc,
              importance: Importance.high,
            ),
          );
      _localReady = true;
    } catch (e) {
      debugPrint('Local notifications init failed: $e');
    }
  }

  Future<void> _show({
    required int id,
    required String title,
    required String body,
  }) async {
    if (!_localReady) return;
    try {
      await _local.show(
        id: id,
        title: title,
        body: body,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            _channelName,
            channelDescription: _channelDesc,
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(),
        ),
      );
    } catch (e) {
      debugPrint('Showing system notification failed: $e');
    }
  }

  Future<void> _cancelSystemNotification(int id) async {
    if (!_localReady) return;
    try {
      await _local.cancel(id: id);
    } catch (e) {
      debugPrint('Cancelling system notification failed: $e');
    }
  }
}