import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persisted base URL for the ball-detection API (Cloud Run or local uvicorn).
class DetectionApiSettings {
  DetectionApiSettings._();

  /// Cloud Run 本番 URL。デプロイ後 `gcloud run services describe` の URL に差し替え。
  static const cloudRunUrl =
      'https://billiards-ball-detector-frxlawrwwa-an.a.run.app';

  /// ローカル開発用。`flutter run --dart-define=DETECTION_API_URL=http://127.0.0.1:8765`
  static const localUrl = 'http://127.0.0.1:8765';

  static const defaultUrl = String.fromEnvironment(
    'DETECTION_API_URL',
    defaultValue: cloudRunUrl,
  );

  static const _key = 'ball_detection_api_base_url';

  static Future<String> loadBaseUrl() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_key);
    if (saved == null || saved.trim().isEmpty) return defaultUrl;
    final normalized = _normalize(saved.trim());

    // Migrate old local HTTP setting on HTTPS web to the new Cloud Run default.
    final shouldForceDefaultOnHttpsWeb = kIsWeb &&
        Uri.base.scheme == 'https' &&
        normalized.startsWith('http://');
    if (shouldForceDefaultOnHttpsWeb) {
      await prefs.setString(_key, defaultUrl);
      return defaultUrl;
    }
    return normalized;
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
