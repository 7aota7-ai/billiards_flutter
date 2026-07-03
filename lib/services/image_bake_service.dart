import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

/// Bake EXIF orientation, resize, and JPEG-compress for API upload.
class ImageBakeService {
  ImageBakeService._();

  /// Cloud Run default limit is 10MB; keep margin for multipart overhead.
  static const int maxUploadBytes = 9 * 1024 * 1024;

  /// Long edge cap — enough for ball detection, keeps PNG-style bloat away.
  static const int maxLongEdgePx = 2048;

  static Future<({Uint8List bytes, Size size})> bake(Uint8List raw) async {
    final baked = await compute(_bakeInIsolate, raw);
    return (
      bytes: baked.bytes,
      size: Size(baked.width, baked.height),
    );
  }

  static _BakedPayload _bakeInIsolate(Uint8List raw) {
    final decoded = img.decodeImage(raw);
    if (decoded == null) {
      throw StateError('画像を読み込めませんでした');
    }

    var working = img.bakeOrientation(decoded);
    working = _resizeIfNeeded(working);
    final bytes = _encodeJpegUnderLimit(working);

    return _BakedPayload(
      bytes: bytes,
      width: working.width.toDouble(),
      height: working.height.toDouble(),
    );
  }

  static img.Image _resizeIfNeeded(img.Image image) {
    final w = image.width;
    final h = image.height;
    final longEdge = w > h ? w : h;
    if (longEdge <= maxLongEdgePx) return image;

    if (w >= h) {
      return img.copyResize(image, width: maxLongEdgePx);
    }
    return img.copyResize(image, height: maxLongEdgePx);
  }

  static Uint8List _encodeJpegUnderLimit(img.Image image) {
    var quality = 88;
    var bytes = Uint8List.fromList(img.encodeJpg(image, quality: quality));
    while (bytes.length > maxUploadBytes && quality > 55) {
      quality -= 8;
      bytes = Uint8List.fromList(img.encodeJpg(image, quality: quality));
    }

    if (bytes.length <= maxUploadBytes) return bytes;

    var scaled = image;
    while (bytes.length > maxUploadBytes && scaled.width > 800) {
      scaled = img.copyResize(
        scaled,
        width: (scaled.width * 0.85).round(),
      );
      quality = 82;
      bytes = Uint8List.fromList(img.encodeJpg(scaled, quality: quality));
    }

    if (bytes.length > maxUploadBytes) {
      throw StateError(
        '画像を圧縮しても上限（${maxUploadBytes ~/ (1024 * 1024)}MB）を超えます',
      );
    }
    return bytes;
  }
}

class _BakedPayload {
  const _BakedPayload({
    required this.bytes,
    required this.width,
    required this.height,
  });

  final Uint8List bytes;
  final double width;
  final double height;
}
