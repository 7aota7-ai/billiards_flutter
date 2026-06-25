import 'dart:math' as math;
import 'dart:ui';

/// Maps overlay guide points on the camera preview widget to normalized image coords.
class CameraPreviewMapper {
  CameraPreviewMapper._();

  /// [guideWidgetNorm] — corners in 0–1 relative to preview widget (TL, TR, BR, BL).
  /// Assumes preview and capture share the same field-of-view (cover-fit center crop).
  static List<List<double>> mapGuideToNormalizedImage({
    required List<Offset> guideWidgetNorm,
    required Size widgetSize,
    required Size imageSize,
  }) {
    if (widgetSize.width <= 0 ||
        widgetSize.height <= 0 ||
        imageSize.width <= 0 ||
        imageSize.height <= 0) {
      throw ArgumentError('invalid sizes for mapping');
    }

    final imageAspect = imageSize.width / imageSize.height;
    final widgetAspect = widgetSize.width / widgetSize.height;

    late Size renderedInWidget;
    late Offset offset;
    if (widgetAspect > imageAspect) {
      renderedInWidget = Size(widgetSize.height * imageAspect, widgetSize.height);
      offset = Offset((widgetSize.width - renderedInWidget.width) / 2, 0);
    } else {
      renderedInWidget = Size(widgetSize.width, widgetSize.width / imageAspect);
      offset = Offset(0, (widgetSize.height - renderedInWidget.height) / 2);
    }

    return guideWidgetNorm.map((norm) {
      final wx = norm.dx * widgetSize.width;
      final wy = norm.dy * widgetSize.height;
      final ix =
          (wx - offset.dx) / renderedInWidget.width * imageSize.width;
      final iy =
          (wy - offset.dy) / renderedInWidget.height * imageSize.height;
      return [
        (ix / imageSize.width).clamp(0.0, 1.0),
        (iy / imageSize.height).clamp(0.0, 1.0),
      ];
    }).toList(growable: false);
  }

  static double cornerYSpan(List<List<double>> normalizedCorners) {
    if (normalizedCorners.length < 4) return 0;
    final ys = normalizedCorners.map((p) => p[1]);
    return ys.reduce(math.max) - ys.reduce(math.min);
  }
}
