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

  /// Perspective: far rail apparent width / near rail width (end view).
  ///
  /// Calibrated from hall photos (Jun 2025): 165 cm shooter, ~80 cm table,
  /// seat only 5–60 cm behind the near cushion (cannot step back). With
  /// camera ~78 cm above the felt, geometry gives ratio ≈ 0.29. Old 0.64
  /// implied ~4.5 m back (near top-down), which is impossible here.
  static const farNearWidthRatio = 0.30;

  /// Normalized preview positions for TL → TR → BR → BL.
  static const farYNorm = 0.30;
  static const nearYNorm = 0.68;
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
  /// Same trapezoid as [guideCornersNormalized] for a typical portrait frame.
  static const defaultPhotoCorners = <Offset>[
    Offset(0.374, 0.30),
    Offset(0.626, 0.30),
    Offset(0.92, 0.68),
    Offset(0.08, 0.68),
  ];

  static List<List<double>> defaultPhotoCornersAsLists() =>
      defaultPhotoCorners
          .map((p) => [p.dx, p.dy])
          .toList(growable: false);

  static String get specLabel =>
      'プレイングエリア ${playingLengthCm.toInt()}×${playingWidthCm.toInt()} cm（2:1）';
}
