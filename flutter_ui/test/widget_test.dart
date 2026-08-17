import 'package:flutter_test/flutter_test.dart';

import 'package:southside_music_ui/main.dart';

void main() {
  testWidgets('app 可以构建主框架', (WidgetTester tester) async {
    await tester.pumpWidget(const SouthsideMusicApp());
    expect(find.text('Southside Music'), findsWidgets);
    expect(find.text('首页'), findsWidgets);
  });
}
