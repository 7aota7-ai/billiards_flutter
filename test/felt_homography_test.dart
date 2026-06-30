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

  test('portrait felt swaps long/short axes', () {
    const apiX = 0.713;
    const apiY = 0.311;
    final norm = FeltHomography.detectionToFeltNorm(
      apiX,
      apiY,
      portraitFelt: true,
    );
    expect(norm.dx, closeTo(apiY, 1e-9));
    expect(norm.dy, closeTo(apiX, 1e-9));
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
}
