import 'dart:ui';

/// Maps felt / warp coordinates to original photo pixels (matches detect_balls.py).
class FeltHomography {
  FeltHomography._();

  static const warpWidth = 2000.0;
  static const warpHeight = 1000.0;

  /// Order 4 points as TL, TR, BR, BL (same as OpenCV helper in detect_balls.py).
  static List<Offset> orderCorners(List<Offset> pts) {
    if (pts.length != 4) {
      throw ArgumentError('corners must be 4 points');
    }
    var tl = pts[0];
    var tr = pts[0];
    var br = pts[0];
    var bl = pts[0];
    var minSum = double.infinity;
    var maxSum = -double.infinity;
    var minDiff = double.infinity;
    var maxDiff = -double.infinity;
    for (final p in pts) {
      final sum = p.dx + p.dy;
      final diff = p.dx - p.dy;
      if (sum < minSum) {
        minSum = sum;
        tl = p;
      }
      if (sum > maxSum) {
        maxSum = sum;
        br = p;
      }
      if (diff < minDiff) {
        minDiff = diff;
        tr = p;
      }
      if (diff > maxDiff) {
        maxDiff = diff;
        bl = p;
      }
    }
    return [tl, tr, br, bl];
  }

  /// Normalized felt coords (0–1 on 2000×1000 warp) → normalized image coords.
  static Offset? warpNormToImageNorm(
    Offset warpNorm,
    List<List<double>> cornersNorm,
    Size imageSize,
  ) {
    if (cornersNorm.length != 4) return null;
    const warpCorners = <Offset>[
      Offset(0, 0),
      Offset(warpWidth - 1, 0),
      Offset(warpWidth - 1, warpHeight - 1),
      Offset(0, warpHeight - 1),
    ];
    final imageCorners = orderCorners(
      cornersNorm
          .map((p) => Offset(p[0] * imageSize.width, p[1] * imageSize.height))
          .toList(growable: false),
    );
    final h = _homographyFrom4Points(warpCorners, imageCorners);
    final warpPx = Offset(
      warpNorm.dx.clamp(0.0, 1.0) * warpWidth,
      warpNorm.dy.clamp(0.0, 1.0) * warpHeight,
    );
    final imgPx = _apply(h, warpPx);
    return Offset(
      (imgPx.dx / imageSize.width).clamp(0.0, 1.0),
      (imgPx.dy / imageSize.height).clamp(0.0, 1.0),
    );
  }

  static List<List<double>> _homographyFrom4Points(
    List<Offset> src,
    List<Offset> dst,
  ) {
    final a = List.generate(8, (_) => List<double>.filled(8, 0));
    final b = List<double>.filled(8, 0);
    for (var i = 0; i < 4; i++) {
      final sx = src[i].dx;
      final sy = src[i].dy;
      final dx = dst[i].dx;
      final dy = dst[i].dy;
      final r1 = i * 2;
      final r2 = i * 2 + 1;
      a[r1][0] = sx;
      a[r1][1] = sy;
      a[r1][2] = 1;
      a[r1][6] = -dx * sx;
      a[r1][7] = -dx * sy;
      b[r1] = dx;
      a[r2][3] = sx;
      a[r2][4] = sy;
      a[r2][5] = 1;
      a[r2][6] = -dy * sx;
      a[r2][7] = -dy * sy;
      b[r2] = dy;
    }
    final h = _solve8x8(a, b);
    return [
      [h[0], h[1], h[2]],
      [h[3], h[4], h[5]],
      [h[6], h[7], 1.0],
    ];
  }

  static List<double> _solve8x8(List<List<double>> a, List<double> b) {
    final n = 8;
    final m = List.generate(n, (i) => List<double>.from(a[i])..add(b[i]));
    for (var col = 0; col < n; col++) {
      var pivot = col;
      for (var row = col + 1; row < n; row++) {
        if (m[row][col].abs() > m[pivot][col].abs()) pivot = row;
      }
      if (m[pivot][col].abs() < 1e-12) {
        throw StateError('singular homography');
      }
      final tmp = m[col];
      m[col] = m[pivot];
      m[pivot] = tmp;
      final div = m[col][col];
      for (var j = col; j <= n; j++) {
        m[col][j] /= div;
      }
      for (var row = 0; row < n; row++) {
        if (row == col) continue;
        final factor = m[row][col];
        if (factor == 0) continue;
        for (var j = col; j <= n; j++) {
          m[row][j] -= factor * m[col][j];
        }
      }
    }
    return List<double>.generate(n, (i) => m[i][n]);
  }

  static Offset _apply(List<List<double>> h, Offset p) {
    final w = h[2][0] * p.dx + h[2][1] * p.dy + h[2][2];
    if (w.abs() < 1e-12) return p;
    return Offset(
      (h[0][0] * p.dx + h[0][1] * p.dy + h[0][2]) / w,
      (h[1][0] * p.dx + h[1][1] * p.dy + h[1][2]) / w,
    );
  }
}
