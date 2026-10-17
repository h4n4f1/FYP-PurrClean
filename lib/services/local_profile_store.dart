import 'dart:convert';
import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Stores profile / cat / settings data on the device, separately for each
/// user id.
class LocalProfileStore {
  LocalProfileStore._();

  /// Notification preference keys and their default values.
  static const Map<String, bool> notificationDefaults = {
    'health_anomaly': true,
    'litter_cleaning': true,
    'litter_refill': true,
    'daily_summary': false,
  };

  static String _userPhotoKey(String uid) => 'user_photo_$uid';
  static String _catPhotoKey(String uid) => 'cat_photo_$uid';
  static String _catNameKey(String uid) => 'cat_name_$uid';
  static String _notifKey(String uid, String key) => 'notif_${key}_$uid';

  // ---- image picking -------------------------------------------------

  /// Opens the gallery and returns a resized image, or null if cancelled.
  static Future<Uint8List?> pickImage() async {
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 80,
    );
    if (file == null) return null;
    return file.readAsBytes();
  }

  // ---- generic helpers -----------------------------------------------

  static Future<Uint8List?> _loadBytes(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = prefs.getString(key);
    if (encoded == null) return null;
    try {
      return base64Decode(encoded);
    } catch (_) {
      return null;
    }
  }

  static Future<void> _saveBytes(String key, Uint8List? bytes) async {
    final prefs = await SharedPreferences.getInstance();
    if (bytes == null) {
      await prefs.remove(key);
    } else {
      await prefs.setString(key, base64Encode(bytes));
    }
  }

  // ---- user profile picture ------------------------------------------

  static Future<Uint8List?> loadUserPhoto(String uid) =>
      _loadBytes(_userPhotoKey(uid));

  static Future<void> saveUserPhoto(String uid, Uint8List? bytes) =>
      _saveBytes(_userPhotoKey(uid), bytes);

  // ---- cat profile ---------------------------------------------------

  static Future<Uint8List?> loadCatPhoto(String uid) =>
      _loadBytes(_catPhotoKey(uid));

  static Future<void> saveCatPhoto(String uid, Uint8List? bytes) =>
      _saveBytes(_catPhotoKey(uid), bytes);

  static Future<String> loadCatName(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_catNameKey(uid)) ?? '';
  }

  static Future<void> saveCatName(String uid, String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_catNameKey(uid), name);
  }

  static Future<void> clearCat(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_catPhotoKey(uid));
    await prefs.remove(_catNameKey(uid));
  }

  // ---- notification preferences --------------------------------------

  static Future<bool> loadNotificationPref(String uid, String key) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_notifKey(uid, key)) ??
        notificationDefaults[key] ??
        false;
  }

  static Future<void> saveNotificationPref(
    String uid,
    String key,
    bool value,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_notifKey(uid, key), value);
  }

  // ---- account deletion ----------------------------------------------

  static Future<void> clearUser(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_userPhotoKey(uid));
    await prefs.remove(_catPhotoKey(uid));
    await prefs.remove(_catNameKey(uid));
    await prefs.remove('last_opened_$uid');
    for (final key in notificationDefaults.keys) {
      await prefs.remove(_notifKey(uid, key));
    }
  }
}