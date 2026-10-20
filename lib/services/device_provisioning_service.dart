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

  static const String _provisionedKey = 'device_wifi_provisioned';
  static const String _deviceNameKey = 'device_ble_name';

  final FlutterEspBleProv _ble = FlutterEspBleProv();

  // ---- persisted state -----------------------------------------------

  /// True once the ESP32 has been successfully given the home Wi-Fi details
  /// from this phone.
  Future<bool> isProvisioned() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_provisionedKey) ?? false;
  }

  Future<void> markProvisioned(String deviceName) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_provisionedKey, true);
    await prefs.setString(_deviceNameKey, deviceName);
  }

  /// Forget the device (e.g. when the user wants to set up a different one).
  Future<void> clearProvisioned() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_provisionedKey);
    await prefs.remove(_deviceNameKey);
  }

  // ---- permissions ---------------------------------------------------

  /// Android needs runtime Bluetooth (and, on older versions, location)
  /// permission to scan. iOS shows its own Bluetooth prompt automatically on
  /// first use, so nothing is needed there.
  Future<bool> ensurePermissions() async {
    if (defaultTargetPlatform != TargetPlatform.android) return true;

    final results = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ].request();

    final bluetoothOk = (results[Permission.bluetoothScan]?.isGranted ??
            false) &&
        (results[Permission.bluetoothConnect]?.isGranted ?? false);
    final locationOk = results[Permission.locationWhenInUse]?.isGranted ?? false;

    // Android 12+ uses the Bluetooth permissions; Android 11 and below use
    // location for BLE scanning.
    return bluetoothOk || locationOk;
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