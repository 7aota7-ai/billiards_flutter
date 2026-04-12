import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:billiards_flutter/main.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('設定画面が表示される', (WidgetTester tester) async {
    await tester.pumpWidget(const BilliardsApp());
    await tester.pumpAndSettle();

    expect(find.text('スコアボード設定'), findsOneWidget);
    expect(find.text('プレイヤー設定'), findsOneWidget);
  });
}
