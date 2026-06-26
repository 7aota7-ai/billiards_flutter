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
  /// Calibrated for a natural standing shot (Jun 2026): chest-height phone,
  /// 5–60 cm behind the near cushion — not overhead. Overhead tilt made the
  /// far rail look too narrow (ratio ≈ 0.30–0.35) and forced an unrealistic
  /// arm position. At a comfortable oblique angle the far rail spans ~55% of
  /// the near rail width.
  static const farNearWidthRatio = 0.55;

  /// Normalized preview positions for TL → TR → BR → BL.
  ///
  /// Sized so the whole felt fits with side margin while standing upright;
  /// aligning the guide should not require raising the phone above eye level.
  static const farYNorm = 0.38;
  static const nearYNorm = 0.86;
  static const nearHalfWidthNorm = 0.40;

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
    Offset(0.28, 0.38),
    Offset(0.72, 0.38),
    Offset(0.90, 0.86),
    Offset(0.10, 0.86),
  ];

  /// Short hint for capture screens (natural angle, no overhead).
  static const captureHint =
      '立ったまま自然な角度でOK。台の4隅が画面に入れば十分です';

  static List<List<double>> defaultPhotoCornersAsLists() =>
      defaultPhotoCorners
          .map((p) => [p.dx, p.dy])
          .toList(growable: false);

  static String get specLabel =>
      'プレイングエリア ${playingLengthCm.toInt()}×${playingWidthCm.toInt()} cm（2:1）';
}
