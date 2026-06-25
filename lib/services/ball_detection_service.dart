import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/detected_ball_layout.dart';
import 'detection_api_settings.dart';

/// Result of probing the local detection API.
class BallDetectionServerStatus {
  const BallDetectionServerStatus({
    required this.available,
    required this.summary,
    this.detail,
  });

  final bool available;
  final String summary;
  final String? detail;
}

/// Calls the OpenCV FastAPI server (Cloud Run or local) or parses pasted JSON.
class BallDetectionService {
  BallDetectionService({this.baseUrl = DetectionApiSettings.defaultUrl});

  final String baseUrl;

  static bool _isHttps(String url) => url.startsWith('https://');

  /// HTTPS の Web から HTTP のローカル API だけブロック（mixed content）。
  bool get isBlockedByMixedContent =>
      kIsWeb && Uri.base.scheme == 'https' && !_isHttps(baseUrl);

  static String get mixedContentBlockedDetail =>
      'GitHub Pages（HTTPS）からは HTTP のローカル API に接続できません。\n\n'
      '本番: Cloud Run（HTTPS）を使うか、ローカル開発は次の手順:\n'
      '1. PC で uvicorn --host 0.0.0.0 --port 8765\n'
      '2. PC で flutter run -d chrome --web-hostname 0.0.0.0 --web-port 8080\n'
      '3. スマホで http://PCのIP:8080 を開く\n'
      '4. API URL を http://PCのIP:8765 に設定';

  Future<BallDetectionServerStatus> checkServer() async {
    if (isBlockedByMixedContent) {
      return BallDetectionServerStatus(
        available: false,
        summary: '検出 API: HTTPS ページから HTTP API は不可',
        detail: mixedContentBlockedDetail,
      );
    }
    try {
      final res = await http
          .get(Uri.parse('$baseUrl/health'))
          .timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        return BallDetectionServerStatus(
          available: true,
          summary: '検出 API: 接続 OK ($baseUrl)',
        );
      }
      return BallDetectionServerStatus(
        available: false,
        summary: '検出 API: 応答異常 (${res.statusCode})',
        detail: 'tools/ball_detector で uvicorn を起動してください。',
      );
    } catch (_) {
      return BallDetectionServerStatus(
        available: false,
        summary: '検出 API: 未接続 — CLI JSON 貼り付け可',
        detail: 'PC で uvicorn server:app --host 127.0.0.1 --port 8765 '
            'を起動してください。',
      );
    }
  }

  Future<bool> isServerAvailable() async {
    return (await checkServer()).available;
  }

  Future<DetectedBallLayout> detectFromBytes({
    required Uint8List imageBytes,
    required String filename,
    required List<OffsetLike> corners,
    double? refWidth,
    double? refHeight,
  }) async {
    final request = http.MultipartRequest('POST', Uri.parse('$baseUrl/detect'));
    request.files.add(
      http.MultipartFile.fromBytes(
        'image',
        imageBytes,
        filename: filename,
      ),
    );
    request.fields['corners'] = jsonEncode(
      corners.map((c) => [c.dx, c.dy]).toList(),
    );
    if (refWidth != null && refWidth > 0) {
      request.fields['ref_width'] = refWidth.round().toString();
    }
    if (refHeight != null && refHeight > 0) {
      request.fields['ref_height'] = refHeight.round().toString();
    }

    final streamed = await request.send().timeout(const Duration(seconds: 60));
    final body = await streamed.stream.bytesToString();
    if (streamed.statusCode == 413) {
      throw BallDetectionException(
        '画像が大きすぎます（API上限 10MB）。別の写真を選ぶか、アプリを再読み込みしてください。',
      );
    }
    if (streamed.statusCode != 200) {
      throw BallDetectionException(
        '検出 API エラー (${streamed.statusCode}): $body',
      );
    }
    return DetectedBallLayout.fromJson(
      Map<String, dynamic>.from(jsonDecode(body) as Map),
    );
  }

  DetectedBallLayout parseJson(String source) => DetectedBallLayout.parse(source);
}

class OffsetLike {
  const OffsetLike(this.dx, this.dy);
  final double dx;
  final double dy;
}

class BallDetectionException implements Exception {
  BallDetectionException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Map detected color hints to ball ids when unambiguous (v1 helper).
int? suggestBallId(String? color, {required bool allowCue}) {
  if (color == null) return null;
  switch (color) {
    case 'white':
      return allowCue ? 0 : null;
    case 'yellow':
      return 1;
    case 'blue':
      return 2;
    case 'red':
      return 3;
    case 'purple':
      return 4;
    case 'orange':
      return 5;
    case 'green':
      return 6;
    case 'maroon':
      return 7;
    case 'black':
      return 8;
    default:
      return null;
  }
}
