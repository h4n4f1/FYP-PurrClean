import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';

import 'device_provisioning_service.dart';

/// What the app knows about the ESP32.
enum DeviceLinkStatus {
  /// Still working it out (or no heartbeat data yet). No banner.
  unknown,

  /// This phone has never set up a device (e.g. the user skipped setup).
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
///   lastSeen    : server time in ms (heartbeat written by the ESP32)
class DeviceStatusService {
  DeviceStatusService._();
  static final DeviceStatusService instance = DeviceStatusService._();

  /// MUST match DB_URL in the firmware. Copy it from
  /// Firebase console -> Realtime Database -> Data tab.
  static const String _databaseUrl =
      'https://purrclean-124-default-rtdb.firebaseio.com';

  /// The ESP32 sends a heartbeat every 60 s, so 3 minutes = 3 missed beats.
  static const Duration offlineAfter = Duration(minutes: 3);

  FirebaseDatabase get _db => FirebaseDatabase.instanceFor(
        app: Firebase.app(),
        databaseURL: _databaseUrl,
      );

  /// "PROV_PURRCLEAN_3FA2" -> "3FA2"
  static String idFromName(String deviceName) => deviceName.split('_').last;

  Future<void> setProvisioned(String deviceName, bool value) async {
    try {
      await _db
          .ref('devices/${idFromName(deviceName)}/provisioned')
          .set(value);
    } catch (e) {
      debugPrint('setProvisioned failed: $e');
    }
  }

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