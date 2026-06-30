import 'dart:typed_data';
import 'dart:ui';

import 'package:image/image.dart' as img;

import 'felt_homography.dart';

/// ワープ結果（JPEG バイト列とピクセル寸法）。
class FeltWarpResult {
  const FeltWarpResult({
    required this.bytes,
    required this.width,
    required this.height,
  });

  final Uint8List bytes;
  final int width;
  final int height;

  bool get isPortrait => width < height;
}

/// 4隅ホモグラフィで写真をフェルト図面（1:2 または 2:1）に変換する。
class FeltWarpService {
  FeltWarpService._();

  /// ワープ手順を変えたらインクリメント（Hot reload 後の古いキャッシュ回避）。
  static const cacheVersion = 8;

  /// dst 幅 = ①–②、dst 高さ = ①–④（detect_balls.py の半解像度）。
  static const feltShortPx = 500;
  static const feltLongPx = 1000;

  static Future<FeltWarpResult?> warpToFelt({
    required Uint8List imageBytes,
    required List<List<double>> cornersNorm,
    required Size imageSize,
    required bool portrait,
  }) async {
    if (cornersNorm.length != 4) return null;
    final decoded = img.decodeImage(imageBytes);
    if (decoded == null) return null;

    final cornerW =
        imageSize.width > 0 ? imageSize.width : decoded.width.toDouble();
    final cornerH =
        imageSize.height > 0 ? imageSize.height : decoded.height.toDouble();

    // 隅は bake 時の imageSize で正規化。デコード寸法が違うときはサンプル座標を補正。
    final sx = decoded.width / cornerW;
    final sy = decoded.height / cornerH;

    final srcCorners = FeltHomography.cornersFromTapOrder(
      cornersNorm,
      Size(cornerW, cornerH),
    );

    final outW = portrait ? feltShortPx : feltLongPx;
    final outH = portrait ? feltLongPx : feltShortPx;
    final dstCorners = <Offset>[
      const Offset(0, 0),
      Offset(outW - 1.0, 0),
      Offset(outW - 1.0, outH - 1.0),
      Offset(0, outH - 1.0),
    ];
    final imgToDst = FeltHomography.homographyFrom4Points(srcCorners, dstCorners);
    final dstToImg = FeltHomography.invert3x3(imgToDst);
    if (dstToImg == null) return null;

    final warped = img.Image(width: outW, height: outH);
    for (var y = 0; y < outH; y++) {
      for (var x = 0; x < outW; x++) {
        final src = FeltHomography.applyMatrix(
          dstToImg,
          Offset(x.toDouble(), y.toDouble()),
        );
        final rgba = _sampleBilinear(
          decoded,
          src.dx * sx,
          src.dy * sy,
        );
        warped.setPixelRgba(x, y, rgba[0], rgba[1], rgba[2], rgba[3]);
      }
    }

    return FeltWarpResult(
      bytes: Uint8List.fromList(img.encodeJpg(warped, quality: 88)),
      width: outW,
      height: outH,
    );
  }

  static List<int> _sampleBilinear(img.Image image, double x, double y) {
    if (x < 0 || y < 0 || x >= image.width - 1 || y >= image.height - 1) {
      return const [8, 40, 55, 255];
    }
    final x0 = x.floor();
    final y0 = y.floor();
    final fx = x - x0;
    final fy = y - y0;
    final c00 = image.getPixel(x0, y0);
    final c10 = image.getPixel(x0 + 1, y0);
    final c01 = image.getPixel(x0, y0 + 1);
    final c11 = image.getPixel(x0 + 1, y0 + 1);
    final r = _lerpChannel(c00.r, c10.r, c01.r, c11.r, fx, fy);
    final g = _lerpChannel(c00.g, c10.g, c01.g, c11.g, fx, fy);
    final b = _lerpChannel(c00.b, c10.b, c01.b, c11.b, fx, fy);
    final a = _lerpChannel(c00.a, c10.a, c01.a, c11.a, fx, fy);
    return [r.round(), g.round(), b.round(), a.round()];
  }

  static double _lerpChannel(
    num c00,
    num c10,
    num c01,
    num c11,
    double fx,
    double fy,
  ) {
    final top = c00 + (c10 - c00) * fx;
    final bottom = c01 + (c11 - c01) * fx;
    return top + (bottom - top) * fy;
  }
}
