import 'dart:convert';

/// Detection result from photo import (OpenCV prototype).
class DetectedBallLayout {
  DetectedBallLayout({
    required this.balls,
    this.meta = const {},
  });

  final List<DetectedBall> balls;
  final Map<String, dynamic> meta;

  factory DetectedBallLayout.fromJson(Map<String, dynamic> json) {
    final rawBalls = json['balls'];
    final balls = <DetectedBall>[];
    if (rawBalls is List) {
      for (final item in rawBalls) {
        if (item is Map<String, dynamic>) {
          balls.add(DetectedBall.fromJson(item));
        } else if (item is Map) {
          balls.add(DetectedBall.fromJson(Map<String, dynamic>.from(item)));
        }
      }
    }
    final meta = json['meta'];
    return DetectedBallLayout(
      balls: balls,
      meta: meta is Map ? Map<String, dynamic>.from(meta) : const {},
    );
  }

  static DetectedBallLayout parse(String source) {
    final trimmed = source.trim();
    if (trimmed.isEmpty) {
      throw const FormatException('JSON が空です');
    }
    final decoded = jsonDecode(trimmed);
    if (decoded is List) {
      return DetectedBallLayout.fromJson({'balls': decoded});
    }
    if (decoded is Map) {
      return DetectedBallLayout.fromJson(Map<String, dynamic>.from(decoded));
    }
    throw FormatException('JSON はオブジェクトか balls 配列である必要があります');
  }
}

class DetectedBall {
  DetectedBall({
    this.id,
    required this.x,
    required this.y,
    this.color,
  });

  final int? id;
  final double x;
  final double y;
  final String? color;

  factory DetectedBall.fromJson(Map<String, dynamic> json) {
    final rawId = json['id'];
    return DetectedBall(
      id: rawId == null ? null : (rawId as num).toInt(),
      x: (json['x'] as num).toDouble(),
      y: (json['y'] as num).toDouble(),
      color: json['color'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'x': x,
        'y': y,
        if (color != null) 'color': color,
      };
}
