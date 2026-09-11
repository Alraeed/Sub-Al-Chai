import 'package:flutter_test/flutter_test.dart';

import 'package:spill_the_tea/app.dart';
import 'package:spill_the_tea/l10n/app_strings.dart';

void main() {
  testWidgets('App boots and shows the branded splash', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const SpillTheTeaApp());
    await tester.pump();

    // Bootstrap has not completed in the test harness, so the splash
    // (ص ب الجاي + a lantern icon) should be visible.
    expect(find.text(AppStrings.appName), findsOneWidget);
  });
}
