import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_esp_ble_prov/flutter_esp_ble_prov.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Handles first-time Wi-Fi setup of the PurrClean ESP32 over Bluetooth LE.
///
/// The phone talks to the ESP32 over BLE, asks it which Wi-Fi networks IT can
/// see (so only 2.4 GHz networks it can actually join are listed), and then
/// sends it the home Wi-Fi name + password.
///
/// The device that was set up is remembered PER USER, so logging in with a
/// different account on the same phone does not inherit someone else's device.
///
/// The constants below MUST match the firmware
/// (firmware/PurrClean_Provisioning/PurrClean_Provisioning.ino).
class DeviceProvisioningService {
  DeviceProvisioningService._();
  static final DeviceProvisioningService instance =
      DeviceProvisioningService._();

  /// BLE name prefix advertised by the ESP32 (full name is PREFIX + "_ABCD").
  static const String devicePrefix = 'PROV_PURRCLEAN';

  /// Proof-of-possession string the ESP32 expects (Security 1).
  static const String proofOfPossession = 'purrclean-pop';

  /// uid of the logged-in user ('guest' if nobody is logged in).
  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? 'guest';

  String get _provisionedKey => 'device_wifi_provisioned_$_uid';
  String get _deviceNameKey => 'device_ble_name_$_uid';

  static String _setupStepKey(String uid) => 'device_setup_step_done_$uid';

  final FlutterEspBleProv _ble = FlutterEspBleProv();

  // ---- persisted state -----------------------------------------------

  /// True once the ESP32 has been successfully given the home Wi-Fi details
  /// from this phone by the current user.
  Future<bool> isProvisioned() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_provisionedKey) ?? false;
  }

  Future<void> markProvisioned(String deviceName) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_provisionedKey, true);
    await prefs.setString(_deviceNameKey, deviceName);
  }

  /// BLE name of the device that the current user set up (or null).
  Future<String?> savedDeviceName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_deviceNameKey);
  }

  /// Forget the device completely (e.g. to set up a different one).
  Future<void> clearProvisioned() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_provisionedKey);
    await prefs.remove(_deviceNameKey);
  }

  /// Whether this user has already been through the post-login device step
  /// (either finished it or tapped "Skip for now").
  Future<bool> isSetupStepDone(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_setupStepKey(uid)) ?? false;
  }

  Future<void> markSetupStepDone(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_setupStepKey(uid), true);
  }

  // ---- permissions ---------------------------------------------------

  /// Returns null when everything needed for scanning is OK, otherwise a
  /// message telling the user exactly what to fix.
  ///
  /// Android needs Location permission (and the Location switch turned on) to
  /// scan for Bluetooth devices. iOS shows its own Bluetooth prompt
  /// automatically on first use, so nothing is needed there.
  Future<String?> checkAccess() async {
    if (defaultTargetPlatform != TargetPlatform.android) return null;

    // Request Bluetooth first, then Location on its own. Location is
    // requested as a full group (fine + coarse together), which Android 12+
    // requires - otherwise the pop-up never shows.
    final bt = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
    ].request();

    final btDenied = bt.values.any((s) => !s.isGranted);
    if (btDenied) {
      final blocked = bt.values.any((s) => s.isPermanentlyDenied);
      if (blocked) {
        await openAppSettings();
        return 'Nearby devices permission is blocked. In the settings page '
            'that just opened, go to Permissions, allow "Nearby devices", '
            'then come back and try again.';
      }
      return 'PurrClean needs the Nearby devices (Bluetooth) permission to '
          'find your device. Please tap Allow and try again.';
    }

    var location = await Permission.location.status;
    if (!location.isGranted) {
      location = await Permission.location.request();
    }

    if (!location.isGranted) {
      if (location.isPermanentlyDenied) {
        await openAppSettings();
        return 'Location permission is blocked. In the settings page that '
            'just opened, go to Permissions > Location, choose "Allow only '
            'while using the app" and turn on "Use precise location", then '
            'come back and try again.';
      }
      return 'PurrClean needs Location permission to find nearby Bluetooth '
          'devices. Please tap Allow (choose "Precise") and try again.';
    }

    final locationOn = await Permission.location.serviceStatus.isEnabled;
    if (!locationOn) {
      return 'Please turn on Location (GPS) in your phone\'s quick settings '
          'panel, then try again. Android needs it to scan for Bluetooth '
          'devices.';
    }

    return null;
  }

  // ---- provisioning steps --------------------------------------------

  Future<List<String>> scanDevices() async {
    final devices = await _ble.scanBleDevices(devicePrefix);
    return devices.toSet().toList()..sort();
  }

  /// Wi-Fi networks visible to the ESP32 itself.
  Future<List<String>> scanNetworks(String deviceName) async {
    final networks = await _ble.scanWifiNetworks(deviceName, proofOfPossession);
    return networks.where((s) => s.trim().isNotEmpty).toSet().toList()..sort();
  }

  /// Sends the Wi-Fi credentials to the ESP32 and waits for it to report
  /// whether it managed to join the network.
  Future<bool> provision({
    required String deviceName,
    required String ssid,
    required String password,
  }) async {
    final ok = await _ble.provisionWifi(
      deviceName,
      proofOfPossession,
      ssid,
      password,
    );
    return ok ?? false;
  }
}