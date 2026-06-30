import 'dart:io';
import 'dart:ui';

import 'package:billiards_flutter/services/felt_warp_service.dart';
import 'package:billiards_flutter/services/image_bake_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('baked image warp matches decoded size', () async {
    final raw = File('tools/ball_detector/samples/S__194969627_0.jpg')
        .readAsBytesSync();
    final baked = await ImageBakeService.bake(raw);
    final decoded = img.decodeImage(baked.bytes)!;
    expect(decoded.width, baked.size.width.toInt());
    expect(decoded.height, baked.size.height.toInt());

    const corners = [
      [0.332, 0.27],
      [0.668, 0.27],
      [0.98, 0.76],
      [0.02, 0.76],
    ];
    final warped = await FeltWarpService.warpToFelt(
      imageBytes: baked.bytes,
      cornersNorm: corners,
      imageSize: baked.size,
      portrait: true,
    );
    expect(warped, isNotNull);
    expect(warped!.width, 500);
    expect(warped.height, 1000);
    await File('tools/ball_detector/out/debug_dart_baked_warp.jpg')
        .writeAsBytes(warped.bytes);
  });
}
