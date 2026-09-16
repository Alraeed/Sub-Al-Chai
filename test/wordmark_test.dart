import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spill_the_tea/l10n/app_strings.dart';
import 'package:spill_the_tea/widgets/tea_logo.dart';
import 'package:spill_the_tea/widgets/tea_wordmark.dart';

/// Pumps the lockup inside a chosen ambient text direction.
Future<void> _pumpWordmark(
  WidgetTester tester, {
  TextDirection direction = TextDirection.rtl,
  String? tagline,
  double markSize = 96,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Directionality(
        textDirection: direction,
        child: Scaffold(
          body: Center(
            child: TeaWordmark(markSize: markSize, tagline: tagline),
          ),
        ),
      ),
    ),
  );
  // One frame is enough: the steam loop is intentionally endless.
  await tester.pump();
}

Text _textOf(WidgetTester tester, String data) =>
    tester.widget<Text>(find.text(data));

/// The cup mark only — the framework paints plenty of other CustomPaints, so
/// matching by type alone would measure the wrong layer.
Finder get _cupMark => find.byWidgetPredicate(
      (Widget w) => w is CustomPaint && w.painter is TeaLogoPainter,
    );

void main() {
  group('TeaWordmark', () {
    testWidgets('carries the cup mark, the Arabic name and the Latin line',
        (WidgetTester tester) async {
      await _pumpWordmark(tester);

      expect(find.text(AppStrings.appName), findsOneWidget);
      expect(find.text(AppStrings.appNameLatin), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('keeps each run in its own direction, in RTL and in LTR',
        (WidgetTester tester) async {
      for (final TextDirection ambient in <TextDirection>[
        TextDirection.rtl,
        TextDirection.ltr,
      ]) {
        await _pumpWordmark(tester, direction: ambient);

        // The Latin brand line must never be reordered by an RTL ancestor,
        // and the Arabic name must never be reordered by an LTR one.
        expect(_textOf(tester, AppStrings.appNameLatin).textDirection,
            TextDirection.ltr);
        expect(_textOf(tester, AppStrings.appName).textDirection,
            TextDirection.rtl);
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('gives the Arabic to English step one deliberate gap',
        (WidgetTester tester) async {
      await _pumpWordmark(tester);

      final double arabicBottom =
          tester.getBottomLeft(find.text(AppStrings.appName)).dy;
      final double latinTop =
          tester.getTopLeft(find.text(AppStrings.appNameLatin)).dy;

      // A single documented step sits between the two runs, and it is the
      // seam-bearing one — not two accidental paddings.
      expect(
        latinTop - arabicBottom,
        closeTo(TeaWordmark.arabicToLatin, 0.5),
      );
      expect(
        TeaWordmark.arabicToLatin,
        TeaWordmark.arabicToSeam +
            TeaWordmark.seamHeight +
            TeaWordmark.seamToLatin,
      );
      // The step is generous enough to separate the runs visually.
      expect(TeaWordmark.arabicToLatin, greaterThanOrEqualTo(30));
    });

    testWidgets('the mark scales with markSize and stays above the name',
        (WidgetTester tester) async {
      await _pumpWordmark(tester, markSize: 48);
      expect(_cupMark, findsOneWidget);
      final double smallMarkBottom = tester.getBottomLeft(_cupMark).dy;
      final double smallNameTop =
          tester.getTopLeft(find.text(AppStrings.appName)).dy;
      expect(smallNameTop - smallMarkBottom, closeTo(TeaWordmark.markGap, 0.5));

      await _pumpWordmark(tester, markSize: 140);
      final double bigMarkBottom = tester.getBottomLeft(_cupMark).dy;
      final double bigNameTop =
          tester.getTopLeft(find.text(AppStrings.appName)).dy;
      expect(bigNameTop - bigMarkBottom, closeTo(TeaWordmark.markGap, 0.5));
      // The mark really scaled rather than just moved.
      expect(tester.getSize(_cupMark).width, 140);
    });

    testWidgets('the tagline is optional and sits under the Latin line',
        (WidgetTester tester) async {
      await _pumpWordmark(tester);
      expect(find.text(AppStrings.tagline), findsNothing);

      await _pumpWordmark(tester, tagline: AppStrings.tagline);
      expect(find.text(AppStrings.tagline), findsOneWidget);

      final double latinBottom =
          tester.getBottomLeft(find.text(AppStrings.appNameLatin)).dy;
      final double taglineTop =
          tester.getTopLeft(find.text(AppStrings.tagline)).dy;
      expect(
          taglineTop - latinBottom, closeTo(TeaWordmark.latinToTagline, 0.5));
    });

    testWidgets('announces the name once, not once per element',
        (WidgetTester tester) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await _pumpWordmark(tester, tagline: AppStrings.tagline);

      // The decorative cup must not repeat the name it sits next to.
      expect(find.bySemanticsLabel(AppStrings.appName), findsOneWidget);

      handle.dispose();
    });
  });
}
