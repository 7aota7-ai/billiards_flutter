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
  /// Calibrated from hall photo `S__194969627_0.jpg` (Jun 2026): ~140 cm shooter
  /// height, ~40 cm from the near cushion, slight overhead — the widest framing
  /// achievable without losing the felt corners from the frame.
  static const farNearWidthRatio = 0.368;

  /// Normalized preview positions for TL → TR → BR → BL.
  ///
  /// Tuned so the yellow trapezoid matches the reference photo at minimum zoom.
  /// y-span ≈ 0.32 (far y≈0.38, near y≈0.69); near width ≈ 96% of frame.
  static const farYNorm = 0.376;
  static const nearYNorm = 0.694;
  static const nearHalfWidthNorm = 0.482;

  /// Minimum normalized Y span between far and near corners (photo import validation).
  static const minCornerYSpan = 0.32;

  static List<Offset> guideCornersNormalized() {
    const farHalf = nearHalfWidthNorm * farNearWidthRatio;
    const cx = 0.5;
    return const [
      Offset(cx - farHalf, farYNorm),
      Offset(cx + farHalf, farYNorm),
      Offset(cx + nearHalfWidthNorm, nearYNorm),
      Offset(cx - nearHalfWidthNorm, nearYNorm),
    ];
  }

  /// Portrait table photo — initial felt corners (photo import / browser camera).
  /// Matches [guideCornersNormalized] for the reference hall photo framing.
  static const defaultPhotoCorners = <Offset>[
    Offset(0.323, 0.376),
    Offset(0.677, 0.376),
    Offset(0.982, 0.694),
    Offset(0.018, 0.694),
  ];

  /// Short hint for capture screens.
  static const captureHint =
      'ズーム広角で台の4隅が黄色枠に入ればOK。次画面で微調整';

  static List<List<double>> defaultPhotoCornersAsLists() =>
      defaultPhotoCorners
          .map((p) => [p.dx, p.dy])
          .toList(growable: false);

  static String get specLabel =>
      'プレイングエリア ${playingLengthCm.toInt()}×${playingWidthCm.toInt()} cm（2:1）';
}
