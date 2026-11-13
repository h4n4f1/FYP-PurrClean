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

/// Numbers used by the Home "Litter Care" card.
/// The Cloud Function (functions/index.js) has its own copy: keep them equal.
class CareThresholds {
  CareThresholds._();

  static const double wasteCapacityGrams = 500;
  static const int wasteWarnPct = 80;
  static const int cleanAfterVisits = 6;
  static const int cleanAfterHours = 24;
  static const double ammoniaCleanPpm = 30;
  static const int refillEveryDays = 7;
  static const Duration recheckEvery = Duration(minutes: 15);
}

/// Litter-care reminders as SYSTEM notifications.
///
///  * The Cloud Function decides when a reminder is due and sends a push, so
///    it arrives even when the app is closed.
///  * This class (a) registers the phone for those pushes, (b) keeps the
///    "last cleaned / emptied / refilled" times in sync with the server,
///    (c) shows pushes that arrive while the app is open as system
///    notifications too, and (d) feeds the Home "Litter Care" card.
class CareReminderService {
  CareReminderService._();
  static final CareReminderService instance = CareReminderService._();

  static const _channelId = 'care_reminders';
  static const _channelName = 'Litter care reminders';
  static const _channelDesc =
      'Reminders to clean the litter box, empty waste and refill litter';

  late final SensorService _sensor = SensorService();
  final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();

  FirebaseDatabase get _db => FirebaseDatabase.instanceFor(
        app: Firebase.app(),
        databaseURL: SensorService.databaseUrl,
      );

  /// Latest litter-care status (null until the first check finishes).
  final ValueNotifier<CareStatus?> status = ValueNotifier<CareStatus?>(null);

  SharedPreferences? _prefs;
  String? _uid;
  String? _deviceId;
  String? _token;
  StreamSubscription<DatabaseEvent>? _sub;
  StreamSubscription<String>? _tokenSub;
  Timer? _timer;
  List<LitterEvent> _events = const [];
  bool _localReady = false;

  bool _busy = false;
  bool _rerun = false;

  // ------------------------------------------------------------ lifecycle

  Future<void> start() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) return;
    _uid = uid;
    status.value = null;

    _prefs ??= await SharedPreferences.getInstance();
    await _initLocalNotifications();
    await _seedBaselines();
    await _attachDevice();
    if (_uid != uid) return;

    _timer?.cancel();
    _timer = Timer.periodic(CareThresholds.recheckEvery, (_) async {
      await _attachDevice();
      await _evaluate();
    });
    await _evaluate();
  }

  /// Sign-out / leaving the main screen: stop pushes for this phone.
  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    final sub = _sub;
    final tokenSub = _tokenSub;
    final deviceId = _deviceId;
    final token = _token;
    _sub = null;
    _tokenSub = null;
    _uid = null;
    _deviceId = null;
    _token = null;
    _events = const [];
    await sub?.cancel();
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

  Future<void> checkNow() => _evaluate();

  // -------------------------------------------------------- owner actions

  String _fieldFor(CareTask task) => switch (task) {
        CareTask.cleanBox => 'last_clean',
        CareTask.wasteDisposal => 'last_waste',
        CareTask.refillLitter => 'last_refill',
      };

  /// The owner did the job: reset its counter here and on the server.
  Future<void> markDone(CareTask task) async {
    final prefs = _prefs;
    if (prefs == null) return;
    final field = _fieldFor(task);
    final now = DateTime.now().millisecondsSinceEpoch;
    await prefs.setInt(_k(field), now);

    final id = _deviceId;
    if (id != null) {
      try {
        await _db.ref('devices/$id/care').update({
          field: now,
          'notified_${task.name}': null, // clears the "already reminded" mark
        }).timeout(const Duration(seconds: 8));
      } catch (e) {
        debugPrint('markDone sync failed: $e');
      }
    }
    await _cancelSystemNotification(task.notificationId);
    await _evaluate();
  }

  /// Call after a notification switch in Settings changes.
  Future<void> syncPrefs() async {
    final id = _deviceId;
    final token = _token;
    if (id != null && token != null) await _saveToken(id, token);
  }

  /// Settings -> "Send test reminder": a real system notification.
  Future<void> preview(CareTask task) async {
    final reminder = _reminderFor(task, status.value ?? _sampleStatus(task));
    await _show(
      id: task.notificationId,
      title: reminder.title,
      body: reminder.message,
    );
  }

  /// A push arrived while the app is open (Android does not draw those
  /// itself), so show it as a system notification too.
  Future<void> showFromRemote({
    required Map<String, dynamic> data,
    String? title,
    String? body,
  }) async {
    final CareTask? task = switch ((data['task'] ?? data['type'])?.toString()) {
      'clean' || 'cleanBox' || 'litter_cleaning' => CareTask.cleanBox,
      'waste' || 'wasteDisposal' || 'waste_disposal' => CareTask.wasteDisposal,
      'refill' || 'refillLitter' || 'litter_refill' => CareTask.refillLitter,
      _ => null,
    };
    final raw = (data['task'] ?? data['type'])?.toString() ?? '';
    final id = task?.notificationId ??
        (2000 + raw.codeUnits.fold<int>(0, (a, b) => a + b) % 900);
    await _show(
      id: id,
      title: (title == null || title.isEmpty) ? 'Litter care reminder' : title,
      body: body ?? '',
    );
  }

  // ------------------------------------------------------- device & push

  Future<void> _attachDevice() async {
    final uid = _uid;
    if (uid == null) return;
    final id = await DeviceStatusService.instance.resolveActiveDeviceId();
    if (_uid != uid) return;
    if (id == _deviceId && _sub != null) return;

    _deviceId = id;
    await _sub?.cancel();
    _sub = _sensor.getEventStream(id).listen(
      (event) {
        _events = _sensor.parseEvents(event.snapshot);
        _evaluate();
      },
      onError: (Object e) => debugPrint('CareReminderService stream error: $e'),
    );
    await _syncCareState(id);
    await _registerPush(id);
  }

  /// The server's "last cleaned / emptied / refilled" times win; anything the
  /// server does not have yet is uploaded from this phone.
  Future<void> _syncCareState(String id) async {
    final prefs = _prefs;
    if (prefs == null) return;
    try {
      final ref = _db.ref('devices/$id/care');
      final snap = await ref.get().timeout(const Duration(seconds: 8));
      final server = snap.value is Map ? snap.value as Map : const {};
      for (final field in const ['last_clean', 'last_waste', 'last_refill']) {
        final v = server[field];
        if (v is num) {
          await prefs.setInt(_k(field), v.toInt());
        } else {
          final local = prefs.getInt(_k(field));
          if (local != null) await ref.child(field).set(local);
        }
      }
    } catch (e) {
      debugPrint('Syncing care state failed: $e');
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
    final clean =
        await LocalProfileStore.loadNotificationPref(uid, CareTask.cleanBox.prefKey);
    final waste = await LocalProfileStore.loadNotificationPref(
        uid, CareTask.wasteDisposal.prefKey);
    final refill = await LocalProfileStore.loadNotificationPref(
        uid, CareTask.refillLitter.prefKey);
    final health =
        await LocalProfileStore.loadNotificationPref(uid, 'health_anomaly');
    try {
      await _db.ref('devices/$deviceId/fcmTokens/$token').set({
        'uid': uid,
        'clean': clean,
        'waste': waste,
        'refill': refill,
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

  Future<void> _evaluate() async {
    if (_busy) {
      _rerun = true;
      return;
    }
    _busy = true;
    try {
      do {
        _rerun = false;
        _evaluateOnce();
      } while (_rerun);
    } catch (e) {
      debugPrint('CareReminderService evaluate failed: $e');
    } finally {
      _busy = false;
    }
  }

  void _evaluateOnce() {
    if (_prefs == null || _uid == null) return;
    final now = DateTime.now();
    final lastClean = _readDate('last_clean') ?? now;
    final lastWaste = _readDate('last_waste') ?? now;
    final lastRefill = _readDate('last_refill') ?? now;

    final sinceClean =
        _events.where((e) => e.timestamp.isAfter(lastClean)).toList();
    final wasteGrams = _events
        .where((e) => e.timestamp.isAfter(lastWaste))
        .fold<double>(0, (sum, e) => sum + e.depositMassGrams);

    final int wastePct =
        ((wasteGrams / CareThresholds.wasteCapacityGrams) * 100)
            .round()
            .clamp(0, 100)
            .toInt();
    final visits = sinceClean.length;
    final hoursSinceClean = now.difference(lastClean).inHours;
    final highAmmonia = sinceClean
        .any((e) => e.peakAmmoniaPpm >= CareThresholds.ammoniaCleanPpm);
    final daysSinceRefill = now.difference(lastRefill).inDays;

    status.value = CareStatus(
      wasteGrams: wasteGrams,
      wastePct: wastePct,
      visitsSinceClean: visits,
      hoursSinceClean: hoursSinceClean,
      highAmmonia: highAmmonia,
      daysSinceRefill: daysSinceRefill,
      lastClean: lastClean,
      lastWasteEmptied: lastWaste,
      lastRefill: lastRefill,
      due: <CareTask>{
        if (visits >= CareThresholds.cleanAfterVisits ||
            highAmmonia ||
            (visits > 0 && hoursSinceClean >= CareThresholds.cleanAfterHours))
          CareTask.cleanBox,
        if (wastePct >= CareThresholds.wasteWarnPct) CareTask.wasteDisposal,
        if (daysSinceRefill >= CareThresholds.refillEveryDays)
          CareTask.refillLitter,
      },
    );
  }

  // -------------------------------------------------------------- content

  CareReminder _reminderFor(CareTask task, CareStatus s) {
    switch (task) {
      case CareTask.cleanBox:
        return CareReminder(
          task: task,
          title: 'Clean the litter box',
          message: s.highAmmonia
              ? 'Ammonia is high in the litter box. A quick scoop will '
                  'freshen it up.'
              : 'Your cat has used the box ${s.visitsSinceClean} times since '
                  'it was last cleaned. Time for a scoop!',
        );
      case CareTask.wasteDisposal:
        final full = s.wastePct >= 100;
        return CareReminder(
          task: task,
          title: full ? 'Waste drawer is full' : 'Waste drawer is almost full',
          message: full
              ? 'Empty the drawer now to keep the box clean and odor-free.'
              : 'The drawer is about ${s.wastePct}% full. Please empty it '
                  'into a sealed bag soon.',
          urgent: full,
        );
      case CareTask.refillLitter:
        return CareReminder(
          task: task,
          title: 'Refill the litter',
          message: 'The litter was last topped up ${s.daysSinceRefill} days '
              'ago. Add fresh litter so clumping and odor control keep '
              'working.',
        );
    }
  }

  CareStatus _sampleStatus(CareTask task) {
    final now = DateTime.now();
    return CareStatus(
      wasteGrams: 410,
      wastePct: 82,
      visitsSinceClean: 7,
      hoursSinceClean: 20,
      highAmmonia: false,
      daysSinceRefill: 8,
      lastClean: now,
      lastWasteEmptied: now,
      lastRefill: now,
      due: {task},
    );
  }

  // ------------------------------------------------------------- storage

  String _k(String name) => 'care_${name}_$_uid';

  DateTime? _readDate(String name) {
    final ms = _prefs?.getInt(_k(name));
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  Future<void> _seedBaselines() async {
    final prefs = _prefs;
    if (prefs == null) return;
    final now = DateTime.now();
    final midnight = DateTime(now.year, now.month, now.day);
    Future<void> seed(String name, DateTime value) async {
      if (prefs.getInt(_k(name)) == null) {
        await prefs.setInt(_k(name), value.millisecondsSinceEpoch);
      }
    }

    await seed('last_clean', midnight);
    await seed('last_waste', midnight);
    await seed('last_refill', now);
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