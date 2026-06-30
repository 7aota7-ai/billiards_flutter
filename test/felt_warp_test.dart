import 'dart:io';
import 'dart:ui';

import 'package:billiards_flutter/services/felt_warp_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('portrait warp is 500x1000', () async {
    final path = 'tools/ball_detector/samples/S__194969627_0.jpg';
    final bytes = File(path).readAsBytesSync();
    final decoded = img.decodeImage(bytes)!;
    const corners = [
      [0.332, 0.27],
      [0.668, 0.27],
      [0.98, 0.76],
      [0.02, 0.76],
    ];
    final warped = await FeltWarpService.warpToFelt(
      imageBytes: bytes,
      cornersNorm: corners,
      imageSize: Size(decoded.width.toDouble(), decoded.height.toDouble()),
      portrait: true,
    );
    expect(warped, isNotNull);
    expect(warped!.width, 500);
    expect(warped.height, 1000);
    await File('tools/ball_detector/out/debug_dart_warp.jpg')
        .writeAsBytes(warped.bytes);
  });
}
