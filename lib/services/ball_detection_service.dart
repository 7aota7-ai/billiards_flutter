import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../models/detected_ball_layout.dart';

/// Calls the local OpenCV FastAPI server or parses pasted JSON.
class BallDetectionService {
  BallDetectionService({this.baseUrl = 'http://127.0.0.1:8765'});

  final String baseUrl;

  Future<bool> isServerAvailable() async {
    try {
      final res = await http
          .get(Uri.parse('$baseUrl/health'))
          .timeout(const Duration(seconds: 2));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
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
