import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';

import 'device_provisioning_service.dart';

/// What the app knows about the ESP32.
enum DeviceLinkStatus {
  /// Still working it out (or no heartbeat data yet). No banner.
  unknown,

  /// This account has never set up a device (e.g. the user skipped setup).
  notSetUp,

  /// The ESP32 reported that its Wi-Fi was reset (BOOT button).
  wasReset,

  /// Set up before, but no heartbeat for a few minutes.
  offline,

  /// Heartbeat received recently.
  online,
}

/// Reads/writes devices/<id>/... in the Firebase Realtime Database.
///   provisioned : true/false  (written by the app and the ESP32)
///   ownerUid    : uid of the account that set the device up (written by app)
///   lastSeen    : server time in ms (heartbeat written by the ESP32)
///   resetWifi   : set to true by the app to tell the ESP32 to forget its
///                 Wi-Fi and restart in setup mode (old Wi-Fi is kept as a
///                 backup for 5 minutes)
///   hardReset   : set to true by the app to make the ESP32 forget its Wi-Fi
///                 completely (same as holding BOOT for 5 s)
///
/// The COMMANDS and the owner lookup go over plain HTTPS (the same way the
/// ESP32 talks to the database) because the Firebase SDK can hang without
/// telling you why. Status watching still uses the SDK.
class DeviceStatusService {
  DeviceStatusService._();
  static final DeviceStatusService instance = DeviceStatusService._();

  /// MUST match DB_URL in the firmware. Use the EXACT URL shown in
  /// Firebase console -> Realtime Database -> Data tab (no trailing slash).
  static const String _databaseUrl = 'https://purrclean-124-default-rtdb.asia-southeast1.firebasedatabase.app';

  /// The ESP32 sends a heartbeat every 60 s, so 3 minutes = 3 missed beats.
  static const Duration offlineAfter = Duration(minutes: 3);

  FirebaseDatabase get _db => FirebaseDatabase.instanceFor(
        app: Firebase.app(),
        databaseURL: _databaseUrl,
      );

  /// "PROV_PURRCLEAN_3FA2" -> "3FA2"
  static String idFromName(String deviceName) => deviceName.split('_').last;

  // ---- plain HTTPS helpers (same as the ESP32 uses) -------------------

  Uri _uri(String deviceName, String field) => Uri.parse(
      '$_databaseUrl/devices/${idFromName(deviceName)}/$field.json');

  /// GET -> body text ("true", "false", "null", ...) or null if it failed.
  Future<String?> _restGet(String deviceName, String field) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 8);
    try {
      final req = await client.getUrl(_uri(deviceName, field));
      final res = await req.close().timeout(const Duration(seconds: 8));
      final body = await res.transform(utf8.decoder).join();
      if (res.statusCode == 200) return body.trim();
      debugPrint('REST GET $field failed: HTTP ${res.statusCode} $body');
      return null;
    } catch (e) {
      debugPrint('REST GET $field failed: $e');
      return null;
    } finally {
      client.close(force: true);
    }
  }

  /// PUT a JSON value. Returns true on HTTP 200.
  Future<bool> _restPut(String deviceName, String field, String json) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 8);
    try {
      final req = await client.putUrl(_uri(deviceName, field));
      req.headers.contentType = ContentType.json;
      req.write(json);
      final res = await req.close().timeout(const Duration(seconds: 8));
      final body = await res.transform(utf8.decoder).join();
      if (res.statusCode == 200) return true;
      debugPrint('REST PUT $field failed: HTTP ${res.statusCode} $body');
      return false;
    } catch (e) {
      debugPrint('REST PUT $field failed: $e');
      return false;
    } finally {
      client.close(force: true);
    }
  }

  /// Sends a command flag, retrying once.
  Future<bool> _sendFlag(String deviceName, String flag) async {
    for (var attempt = 1; attempt <= 2; attempt++) {
      if (await _restPut(deviceName, flag, 'true')) return true;
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    return false;
  }

  /// Polls until the flag is no longer "true" (the ESP32 sets it to false
  /// when it has picked the command up).
  Future<bool> _waitForFlagCleared(
    String deviceName,
    String flag,
    Duration timeout,
  ) async {
    final end = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(end)) {
      final value = await _restGet(deviceName, flag);
      if (value != null && value != 'true') return true;
      await Future<void>.delayed(const Duration(seconds: 2));
    }
    return false;
  }

  // ---- owner link ----------------------------------------------------------

  /// Links the device to an account (or unlinks it when [uid] is null).
  Future<bool> setOwner(String deviceName, String? uid) =>
      _restPut(deviceName, 'ownerUid', uid == null ? 'null' : jsonEncode(uid));

  /// Looks for a device that belongs to [uid]. Returns its BLE name
  /// ("PROV_PURRCLEAN_3FA2") or null if there is none.
  /// Needs  ".indexOn": ["ownerUid"]  under "devices" in the database rules.
  Future<String?> findDeviceForUser(String uid) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 8);
    try {
      final uri = Uri.parse('$_databaseUrl/devices.json').replace(
        queryParameters: {
          'orderBy': '"ownerUid"',
          'equalTo': '"$uid"',
        },
      );
      final req = await client.getUrl(uri);
      final res = await req.close().timeout(const Duration(seconds: 10));
      final body = await res.transform(utf8.decoder).join();
      if (res.statusCode != 200) {
        debugPrint('findDeviceForUser failed: HTTP ${res.statusCode} $body');
        return null;
      }
      final data = jsonDecode(body);
      if (data is! Map) return null;
      for (final entry in data.entries) {
        final value = entry.value;
        // A device that was reset is no longer set up: skip it.
        if (value is Map && value['provisioned'] == false) continue;
        return '${DeviceProvisioningService.devicePrefix}_${entry.key}';
      }
      return null;
    } catch (e) {
      debugPrint('findDeviceForUser failed: $e');
      return null;
    } finally {
      client.close(force: true);
    }
  }

  // ---- provisioning status ---------------------------------------------

  /// Sets devices/<id>/provisioned. When the app marks a device as set up
  /// (true) it also records the logged-in account as its owner.
  Future<void> setProvisioned(String deviceName, bool value) async {
    if (value) {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) await setOwner(deviceName, uid);
    }
    try {
      await _db
          .ref('devices/${idFromName(deviceName)}/provisioned')
          .set(value)
          .timeout(const Duration(seconds: 5));
    } catch (e) {
      // Offline or slow: don't block the UI (the write is sent later).
      debugPrint('setProvisioned failed: $e');
    }
  }

  /// Waits until the ESP32 has reported provisioned = true (it does this as
  /// soon as it is online on the new Wi-Fi). Returns false on timeout.
  Future<bool> waitForProvisioned(
    String deviceName, {
    Duration timeout = const Duration(seconds: 75),
  }) async {
    try {
      await _db
          .ref('devices/${idFromName(deviceName)}/provisioned')
          .onValue
          .firstWhere((event) => event.snapshot.value == true)
          .timeout(timeout);
      return true;
    } catch (_) {
      return false;
    }
  }

  // ---- commands (plain HTTPS) -------------------------------------------

  /// Tells the ESP32 to forget its Wi-Fi and restart in setup mode.
  /// Only works while the ESP32 is online on its current Wi-Fi.
  Future<bool> requestWifiReset(String deviceName) =>
      _sendFlag(deviceName, 'resetWifi');

  /// Tells the ESP32 to forget its Wi-Fi COMPLETELY (like holding BOOT for
  /// 5 s). If the ESP32 is offline right now, the command stays in the cloud
  /// and is carried out as soon as it comes back online.
  Future<bool> requestHardReset(String deviceName) =>
      _sendFlag(deviceName, 'hardReset');

  /// Waits until the ESP32 has picked up the reset command.
  Future<bool> waitForWifiResetAck(
    String deviceName, {
    Duration timeout = const Duration(seconds: 40),
  }) =>
      _waitForFlagCleared(deviceName, 'resetWifi', timeout);

  /// Waits until the ESP32 has picked up the hard reset.
  Future<bool> waitForHardResetAck(
    String deviceName, {
    Duration timeout = const Duration(seconds: 15),
  }) =>
      _waitForFlagCleared(deviceName, 'hardReset', timeout);

  /// Cancels a reset command the ESP32 never picked up, so it doesn't wipe
  /// its Wi-Fi later when it comes back online.
  Future<void> cancelWifiReset(String deviceName) async {
    await _restPut(deviceName, 'resetWifi', 'false');
  }

  /// "Remove device": hard-resets the ESP32, unlinks it from the account and
  /// forgets it on this phone. Returns true if the ESP32 confirmed the reset
  /// straight away; false if it was offline (it will reset itself when it is
  /// back online).
  Future<bool> removeDevice(String deviceName) async {
    await requestHardReset(deviceName);
    final acked = await waitForHardResetAck(deviceName);
    await setOwner(deviceName, null);
    await DeviceProvisioningService.instance.clearProvisioned();
    return acked;
  }

  // ---- live status ------------------------------------------------------

  /// Live status of the device. Create it once (e.g. in initState) and cancel
  /// the subscription in dispose().
  Stream<DeviceLinkStatus> watchStatus() {
    late final StreamController<DeviceLinkStatus> controller;
    StreamSubscription<DatabaseEvent>? sub;
    Timer? timer;

    var hasDevice = false;
    Object? provisioned;
    int? lastSeen;
    var offsetMs = 0; // server time minus phone time

    void emit() {
      if (controller.isClosed) return;
      controller.add(_compute(
        hasDevice: hasDevice,
        provisioned: provisioned,
        lastSeen: lastSeen,
        offsetMs: offsetMs,
      ));
    }

    Future<void> start() async {
      final name = await DeviceProvisioningService.instance.savedDeviceName();
      if (name == null) {
        if (!controller.isClosed) controller.add(DeviceLinkStatus.notSetUp);
        return;
      }
      hasDevice = true;

      try {
        final event = await _db
            .ref('.info/serverTimeOffset')
            .onValue
            .first
            .timeout(const Duration(seconds: 5));
        final value = event.snapshot.value;
        if (value is num) offsetMs = value.toInt();
      } catch (_) {
        // Fall back to the phone's clock.
      }
      if (controller.isClosed) return;

      sub = _db.ref('devices/${idFromName(name)}').onValue.listen(
        (event) {
          final value = event.snapshot.value;
          if (value is Map) {
            provisioned = value['provisioned'];
            final seen = value['lastSeen'];
            lastSeen = seen is num ? seen.toInt() : null;
          } else {
            provisioned = null;
            lastSeen = null;
          }
          emit();
        },
        onError: (Object e) {
          debugPrint('watchStatus error: $e');
          emit();
        },
      );

      // Re-check regularly: "offline" happens when nothing changes.
      timer = Timer.periodic(const Duration(seconds: 30), (_) => emit());
      emit();
    }

    controller = StreamController<DeviceLinkStatus>(
      onListen: () {
        start();
      },
      onCancel: () async {
        timer?.cancel();
        await sub?.cancel();
      },
    );
    return controller.stream;
  }

  DeviceLinkStatus _compute({
    required bool hasDevice,
    required Object? provisioned,
    required int? lastSeen,
    required int offsetMs,
  }) {
    if (!hasDevice) return DeviceLinkStatus.notSetUp;
    if (provisioned == false) return DeviceLinkStatus.wasReset;
    if (lastSeen == null) return DeviceLinkStatus.unknown;

    final serverNow = DateTime.now().millisecondsSinceEpoch + offsetMs;
    final age = serverNow - lastSeen;
    return age > offlineAfter.inMilliseconds
        ? DeviceLinkStatus.offline
        : DeviceLinkStatus.online;
  }
}