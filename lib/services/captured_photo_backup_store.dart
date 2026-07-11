import 'dart:convert';
import 'dart:typed_data';

import 'package:shared_preferences/shared_preferences.dart';

/// 直近1枚の撮影/読込画像を端末内ストレージに退避（Web: localStorage 経由）。
class CapturedPhotoBackupStore {
  CapturedPhotoBackupStore._();

  static const _keyBytes = 'billiards_last_capture_b64';
  static const _keyName = 'billiards_last_capture_name';
  static const _keyTime = 'billiards_last_capture_ms';

  /// 約 4MB まで（SharedPreferences / localStorage 向け）。
  static const maxBytes = 4 * 1024 * 1024;

  static Future<void> save(Uint8List bytes, String filename) async {
    if (bytes.isEmpty || bytes.length > maxBytes) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyBytes, base64Encode(bytes));
      await prefs.setString(_keyName, filename);
      await prefs.setInt(_keyTime, DateTime.now().millisecondsSinceEpoch);
    } catch (_) {
      // Quota exceeded (Web localStorage) など — 表示・検出は続行する。
    }
  }

  static Future<CapturedPhotoBackup?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyBytes);
    if (raw == null || raw.isEmpty) return null;
    try {
      final bytes = base64Decode(raw);
      if (bytes.isEmpty) return null;
      final name = prefs.getString(_keyName) ?? 'billiards.jpg';
      final ms = prefs.getInt(_keyTime);
      return CapturedPhotoBackup(
        bytes: bytes,
        filename: name,
        savedAt: ms == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(ms),
      );
    } catch (_) {
      return null;
    }
  }

  static Future<bool> hasBackup() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.containsKey(_keyBytes);
  }
}

class CapturedPhotoBackup {
  const CapturedPhotoBackup({
    required this.bytes,
    required this.filename,
    this.savedAt,
  });

  final Uint8List bytes;
  final String filename;
  final DateTime? savedAt;
}
