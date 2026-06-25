import 'dart:ui';

/// Regulation table dimensions and camera overlay guide (near-end perspective).
///
/// Outer: 290 × 160 cm, playing area (felt): 254 × 127 cm → 2:1 length:width.
class TableGuideGeometry {
  TableGuideGeometry._();

  static const playingLengthCm = 254.0;
  static const playingWidthCm = 127.0;
  static const outerLengthCm = 290.0;
  static const outerWidthCm = 160.0;

  static const playingAspect = playingLengthCm / playingWidthCm;

  /// Felt width / outer width (reference for cushion inset).
  static const feltOuterWidthRatio = playingWidthCm / outerWidthCm;

  /// Perspective: far rail apparent width / near rail width (typical end view).
  static const farNearWidthRatio = 0.64;

  /// Normalized preview positions for TL → TR → BR → BL.
  static const farYNorm = 0.18;
  static const nearYNorm = 0.86;
  static const nearHalfWidthNorm = 0.42;

  static List<Offset> guideCornersNormalized() {
    const farHalf = nearHalfWidthNorm * farNearWidthRatio;
    const cx = 0.5;
    return [
      Offset(cx - farHalf, farYNorm),
      Offset(cx + farHalf, farYNorm),
      Offset(cx + nearHalfWidthNorm, nearYNorm),
      Offset(cx - nearHalfWidthNorm, nearYNorm),
    ];
  }

  /// Portrait table photo — initial felt corners (photo import / browser camera).
  static const defaultPhotoCorners = <Offset>[
    Offset(0.254, 0.151),
    Offset(0.749, 0.151),
    Offset(0.892, 0.864),
    Offset(0.111, 0.864),
  ];

  static List<List<double>> defaultPhotoCornersAsLists() =>
      defaultPhotoCorners
          .map((p) => [p.dx, p.dy])
          .toList(growable: false);

  static String get specLabel =>
      'プレイングエリア ${playingLengthCm.toInt()}×${playingWidthCm.toInt()} cm（2:1）';
}
