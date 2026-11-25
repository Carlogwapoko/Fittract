import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fittract/screens/auth_screen.dart';
import 'package:fittract/screens/meal_picker_screen.dart';
import 'package:fittract/screens/progress_tab.dart';
import 'package:fittract/store/store.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await store.init();
  });

  testWidgets(
    'food scanner buttons stay aligned and readable at phone widths',
    (tester) async {
      for (final width in [320.0, 360.0, 390.0, 430.0]) {
        tester.view
          ..physicalSize = Size(width, 900)
          ..devicePixelRatio = 1;
        await tester.pumpWidget(const MaterialApp(home: ManualMealScreen()));
        await tester.pumpAndSettle();

        final scanButton = find.widgetWithText(FilledButton, 'Scan your food');
        final galleryButton = find.widgetWithText(
          OutlinedButton,
          'Choose from gallery',
        );
        expect(tester.getSize(scanButton).height, 56);
        expect(tester.getSize(galleryButton).height, 56);
        expect(
          tester
              .getRect(scanButton)
              .contains(tester.getRect(find.text('Scan your food')).topLeft),
          isTrue,
        );
        expect(
          tester
              .getRect(galleryButton)
              .contains(
                tester.getRect(find.text('Choose from gallery')).topLeft,
              ),
          isTrue,
        );
        expect(tester.takeException(), isNull);
      }
      addTearDown(tester.view.reset);
    },
  );

  testWidgets('progress navigation and overview cards fit phone widths', (
    tester,
  ) async {
    for (final width in [320.0, 360.0, 390.0, 430.0]) {
      tester.view
        ..physicalSize = Size(width, 900)
        ..devicePixelRatio = 1;
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: ProgressTab())),
      );
      await tester.pumpAndSettle();

      final overview = tester.widget<Text>(find.text('Overview'));
      expect(overview.maxLines, 1);
      expect(overview.softWrap, isFalse);
      final progressCards = [
        find.ancestor(
          of: find.text('Workouts · last 4 weeks'),
          matching: find.byType(Material),
        ),
        find.ancestor(
          of: find.text('Time moving'),
          matching: find.byType(Material),
        ),
      ];
      expect(
        tester.getSize(progressCards[0].first).height,
        tester.getSize(progressCards[1].first).height,
      );
      expect(tester.takeException(), isNull);
    }
    addTearDown(tester.view.reset);
  });

  testWidgets(
    'signup agreement remains compact and aligned on narrow screens',
    (tester) async {
      for (final width in [320.0, 360.0, 390.0]) {
        tester.view
          ..physicalSize = Size(width, 900)
          ..devicePixelRatio = 1;
        await tester.pumpWidget(
          MaterialApp(home: AuthScreen(key: ValueKey(width))),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('New here? Create an account'));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('terms-agreement-row')),
          findsOneWidget,
        );
        expect(find.text('Terms of Service'), findsOneWidget);
        expect(find.text('Privacy Policy'), findsOneWidget);
        expect(
          tester.getSize(find.byKey(const ValueKey('terms-checkbox'))).height,
          40,
        );
        expect(
          tester
              .getSize(find.byKey(const ValueKey('terms-agreement-row')))
              .height,
          lessThanOrEqualTo(120),
        );
        expect(tester.takeException(), isNull);
      }
      addTearDown(tester.view.reset);
    },
  );
}
