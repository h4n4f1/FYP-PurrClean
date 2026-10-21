import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';

import 'device_provisioning_service.dart';

/// Reads/writes devices/<id>/provisioned in the Firebase Realtime Database.
///
/// The ESP32 writes `false` here when the user holds BOOT (Wi-Fi reset) and
/// `true` once it is connected to Wi-Fi again. The app listens so it can send
/// the user back to the device setup screen.
class DeviceStatusService {
  DeviceStatusService._();
  static final DeviceStatusService instance = DeviceStatusService._();

  /// MUST match DB_URL in the firmware. Copy it from
  /// Firebase console -> Realtime Database -> Data tab.
  static const String _databaseUrl =
      'https://purrclean-124-default-rtdb.asia-southeast1.firebasedatabase.app';

  FirebaseDatabase get _db => FirebaseDatabase.instanceFor(
    app: Firebase.app(),
    databaseURL: _databaseUrl,
  );

  /// "PROV_PURRCLEAN_3FA2" -> "3FA2"
  static String idFromName(String deviceName) => deviceName.split('_').last;

  DatabaseReference _ref(String deviceName) =>
      _db.ref('devices/${idFromName(deviceName)}/provisioned');

  Future<void> setProvisioned(String deviceName, bool value) async {
    try {
      await _ref(deviceName).set(value);
    } catch (e) {
      debugPrint('setProvisioned failed: $e');
    }
  }

  /// Calls [onReset] whenever the ESP32 reports provisioned == false.
  /// Fires straight away if it is already false (e.g. the device was reset
  /// while the app was closed).
  Future<StreamSubscription<DatabaseEvent>?> watchReset(
    VoidCallback onReset,
  ) async {
    final name = await DeviceProvisioningService.instance.savedDeviceName();
    if (name == null) return null;
    return _ref(name).onValue.listen((event) {
      if (event.snapshot.value == false) onReset();
    }, onError: (Object e) => debugPrint('watchReset error: $e'));
  }
}
