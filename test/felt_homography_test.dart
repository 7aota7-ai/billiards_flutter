import 'dart:ui';

import 'package:billiards_flutter/services/felt_homography.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('landscape felt keeps API long/short axes', () {
    const apiX = 0.713;
    const apiY = 0.311;
    final norm = FeltHomography.detectionToFeltNorm(
      apiX,
      apiY,
      portraitFelt: false,
    );
    expect(norm.dx, closeTo(apiX, 1e-9));
    expect(norm.dy, closeTo(apiY, 1e-9));
  });

  test('portrait felt mirrors short axis vs landscape', () {
    const apiX = 0.713;
    const apiY = 0.311;
    final norm = FeltHomography.detectionToFeltNorm(
      apiX,
      apiY,
      portraitFelt: true,
    );
    expect(norm.dx, closeTo(1.0 - apiY, 1e-9));
    expect(norm.dy, closeTo(apiX, 1e-9));
  });

  test('landscape and portrait round-trip through warp axes', () {
    const landscape = Offset(0.25, 0.62);
    final portrait = FeltHomography.landscapeFeltNormToPortrait(landscape);
    final back = FeltHomography.portraitFeltNormToLandscape(portrait);
    expect(back.dx, closeTo(landscape.dx, 1e-9));
    expect(back.dy, closeTo(landscape.dy, 1e-9));
  });

  test('portrait and landscape felt norms map to same warp axes', () {
    const apiX = 0.42;
    const apiY = 0.67;
    final warp = FeltHomography.warpAxesFromDetection(apiX, apiY);
    final portrait = FeltHomography.feltNormFromWarpAxes(
      warp,
      portraitFelt: true,
    );
    final landscape = FeltHomography.feltNormFromWarpAxes(
      warp,
      portraitFelt: false,
    );
    final fromPortrait = FeltHomography.feltNormToWarpAxes(
      portrait,
      portraitFelt: true,
    );
    final fromLandscape = FeltHomography.feltNormToWarpAxes(
      landscape,
      portraitFelt: false,
    );
    expect(fromPortrait.alongLong, closeTo(warp.alongLong, 1e-9));
    expect(fromPortrait.alongShort, closeTo(warp.alongShort, 1e-9));
    expect(fromLandscape.alongLong, closeTo(warp.alongLong, 1e-9));
    expect(fromLandscape.alongShort, closeTo(warp.alongShort, 1e-9));
  });

  test('warp origin maps to tap-order TL on steep portrait photo', () {
    const cornersNorm = [
      [0.32, 0.37],
      [0.68, 0.374],
      [0.969, 0.673],
      [0.012, 0.656],
    ];
    const imageSize = Size(1536, 2048);
    final imageNorm = FeltHomography.warpNormToImageNorm(
      Offset.zero,
      cornersNorm,
      imageSize,
    );
    expect(imageNorm, isNotNull);
    expect(imageNorm!.dx, closeTo(0.32, 0.02));
    expect(imageNorm.dy, closeTo(0.37, 0.02));
  });
}
