import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Bake EXIF orientation into PNG bytes so display == OpenCV decode.
class ImageBakeService {
  ImageBakeService._();

  static Future<({Uint8List bytes, Size size})> bake(Uint8List raw) async {
    final codec = await ui.instantiateImageCodec(raw);
    final frame = await codec.getNextFrame();
    final img = frame.image;
    final w = img.width;
    final h = img.height;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawImage(img, Offset.zero, Paint());
    final picture = recorder.endRecording();
    final baked = await picture.toImage(w, h);
    final data = await baked.toByteData(format: ui.ImageByteFormat.png);
    img.dispose();
    baked.dispose();
    if (data == null) {
      throw StateError('画像の正規化に失敗しました');
    }
    return (
      bytes: data.buffer.asUint8List(),
      size: Size(w.toDouble(), h.toDouble()),
    );
  }
}
