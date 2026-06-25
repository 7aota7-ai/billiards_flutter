import 'package:shared_preferences/shared_preferences.dart';

/// Persisted base URL for the local ball-detection API.
class DetectionApiSettings {
  DetectionApiSettings._();

  static const defaultUrl = 'http://127.0.0.1:8765';
  static const _key = 'ball_detection_api_base_url';

  static Future<String> loadBaseUrl() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_key);
    if (saved == null || saved.trim().isEmpty) return defaultUrl;
    return _normalize(saved.trim());
  }

  static Future<void> saveBaseUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, _normalize(url.trim()));
  }

  static String _normalize(String url) {
    var u = url;
    if (!u.startsWith('http://') && !u.startsWith('https://')) {
      u = 'http://$u';
    }
    return u.replaceAll(RegExp(r'/+$'), '');
  }
}
