import 'package:billiards_flutter/models/table_guide_geometry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('default guide corners pass minCornerYSpan validation', () {
    final ys = TableGuideGeometry.defaultPhotoCorners.map((p) => p.dy);
    final ySpan = ys.reduce((a, b) => a > b ? a : b) -
        ys.reduce((a, b) => a < b ? a : b);
    expect(ySpan, TableGuideGeometry.guideCornerYSpan);
    expect(ySpan, greaterThan(TableGuideGeometry.minCornerYSpan));
  });
}
