import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fittract/screens/food_screen.dart';
import 'package:fittract/screens/activity_screen.dart';
import 'package:fittract/screens/progress_tab.dart';
import 'package:fittract/screens/profile_tab.dart';
import 'package:fittract/screens/routines_tab.dart';
import 'package:fittract/screens/schedule_tab.dart';
import 'package:fittract/screens/today_tab.dart';
import 'package:fittract/screens/water_screen.dart';
import 'package:fittract/screens/weight_screen.dart';
import 'package:fittract/screens/workout_screen.dart';
import 'package:fittract/services/google_auth_service.dart';
import 'package:fittract/store/store.dart';
import 'package:fittract/widgets/shared_widgets.dart';

void _ignoreTab(int _) {}

Future<void> freshStore() async {
  SharedPreferences.setMockInitialValues({});
  await store.init();
}

/// Default test surface is 800x600, which leaves the tail of these screens
/// outside the build window; ListViews then build lazily and finders miss
/// rows that exist in the layout.
void largeViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(1100, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

/// Hosts [page] on top of a still-mounted home route so snackbars and back
/// navigation have somewhere to render/return.
Future<void> pushScreen(WidgetTester tester, Widget page) async {
  largeViewport(tester);
  await tester.pumpWidget(
    const MaterialApp(
      home: Scaffold(body: Center(child: Text('HOME'))),
    ),
  );
  final home = tester.element(find.text('HOME'));
  Navigator.of(home)
      .push(MaterialPageRoute<void>(builder: (_) => page))
      .ignore();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> tapBtn(WidgetTester tester, String label) async {
  await tester.ensureVisible(find.text(label));
  await tester.pump();
  await tester.tap(find.text(label));
}

EditableText editableTextOf(WidgetTester tester, Finder field) =>
    tester.widget<EditableText>(
      find.descendant(of: field, matching: find.byType(EditableText)),
    );

String fieldText(WidgetTester tester, Finder field) =>
    editableTextOf(tester, field).controller.text;

void main() {
  group('progressOf / bar()', () {
    test('maps NaN and infinities to safe bounds', () {
      expect(progressOf(double.nan), 0.0);
      expect(progressOf(double.infinity), 1.0);
      expect(progressOf(double.negativeInfinity), 0.0);
      expect(progressOf(-0.5), 0.0);
      expect(progressOf(0.42), 0.42);
      expect(progressOf(1.7), 1.0);
    });

    testWidgets('bar() renders NaN and infinite progress without throwing', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                bar(double.nan),
                bar(double.infinity),
                bar(double.negativeInfinity),
                bar(0.5),
              ],
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      final values = tester
          .widgetList<LinearProgressIndicator>(
            find.byType(LinearProgressIndicator),
          )
          .map((w) => w.value)
          .toList();
      expect(values, [0.0, 1.0, 0.0, 0.5]);
    });
  });

  group('goal normalization (data layer)', () {
    test('nutritionGoals replaces zero/negative/non-numeric values only', () {
      final s = Store()..d = Store().seed();
      s.d['nutritionGoals'] = {
        'calories': 0,
        'protein': -5,
        'carbs': 'lots',
        'fat': 65,
      };
      expect(s.nutritionGoals['calories'], 2100);
      expect(s.nutritionGoals['protein'], 140);
      expect(s.nutritionGoals['carbs'], 220);
      expect(s.nutritionGoals['fat'], 65);

      s.d['nutritionGoals'] = {
        'calories': 1800,
        'protein': 120,
        'carbs': 200,
        'fat': 50,
      };
      expect(s.nutritionGoals['calories'], 1800);
      expect(s.nutritionGoals['protein'], 120);
      expect(s.nutritionGoals['carbs'], 200);
      expect(s.nutritionGoals['fat'], 50);
    });

    test('goal fields decode tolerantly from legacy/malformed snapshots', () {
      final s = Store()..d = Store().seed();

      s.d['goal'] = <String, dynamic>{};
      expect(s.goalField('sw'), 0.0);
      expect(s.goalField('w'), 0.0);
      expect(s.weeklyWorkoutGoal, 3); // default when missing
      expect(s.goalProgress(), 0);

      s.d['goal'] = {'sw': '80', 'w': null, 'wk': 0};
      expect(s.goalField('sw'), 0.0); // non-numeric reads as unset
      expect(s.goalField('w'), 0.0);
      expect(s.weeklyWorkoutGoal, 1); // malformed zero clamps up

      s.d['goal'] = {'sw': 85.0, 'w': 75.0, 'wk': 4};
      s.d['weights'] = [
        ['2026-01-01', 85.0],
        [today(), 80.0],
      ];
      expect(s.goalProgress(), closeTo(0.5, 1e-9));
      expect(s.weeklyWorkoutGoal, 4);
    });

    testWidgets('Food screen renders when the calorie goal is zero', (
      tester,
    ) async {
      await freshStore();
      store.d['nutritionGoals'] = {
        'calories': 0,
        'protein': 0,
        'carbs': 0,
        'fat': 0,
      };
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: FoodScreen())),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      // The getter restored defaults so the ring and bars stay valid.
      expect(store.nutritionGoals['calories'], 2100);
    });

    testWidgets(
      'Today tab renders with a zero calorie goal and zero weekly goal',
      (tester) async {
        await freshStore();
        store.d['nutritionGoals'] = {'calories': 0};
        store.d['goal']['wk'] = 0;
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(body: TodayTab(goTo: _ignoreTab)),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('Weight screen renders with a malformed goal map', (
      tester,
    ) async {
      await freshStore();
      store.d['goal'] = <String, dynamic>{}; // every key missing
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: WeightScreen())),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('Progress tab renders with a malformed goal map', (
      tester,
    ) async {
      await freshStore();
      store.d['goal'] = {'sw': 'not-a-number'};
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: ProgressTab())),
      );
      await tester.pumpAndSettle();
      // Exercise every sub-tab; none may throw on the bad goal data.
      for (final label in ['Weight', 'Goals', 'Daily', 'Overview']) {
        await tester.ensureVisible(find.text(label));
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
      }
      expect(tester.takeException(), isNull);
    });
  });

  group('activity removal across an async confirmation', () {
    testWidgets(
      'confirming after the list changed does not remove a different activity',
      (tester) async {
        largeViewport(tester);
        await freshStore();
        final walk = <String, dynamic>{
          'n': 'Brisk walk',
          'min': 20,
          'km': 1.5,
          'st': 100,
          'kc': 90,
          't': null,
        };
        final run = <String, dynamic>{
          'n': 'Running',
          'min': 10,
          'km': 2.0,
          'st': 200,
          'kc': 150,
          't': null,
        };
        store.acts
          ..add(walk)
          ..add(run);
        store.d['steps'] = 300;
        store.save();

        await tester.pumpWidget(
          const MaterialApp(home: Scaffold(body: ActivityScreen())),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Brisk walk'));
        await tester.pumpAndSettle(); // confirmation dialog is open

        // The list mutates while the dialog is open (e.g. midnight rollover).
        store.acts.remove(walk);
        store.save();
        await tester.pumpAndSettle();

        await tester.tap(find.text('Remove'));
        await tester.pumpAndSettle();

        // The surviving activity is untouched, steps are unchanged, and the
        // user is told the entry was already gone.
        expect(store.acts, hasLength(1));
        expect(store.acts.single['n'], 'Running');
        expect(store.steps, 300);
        expect(
          find.text('That activity is no longer in the list.'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'confirming removes exactly the tapped activity and its steps',
      (tester) async {
        largeViewport(tester);
        await freshStore();
        final walk = <String, dynamic>{
          'n': 'Brisk walk',
          'min': 20,
          'km': 1.5,
          'st': 100,
          'kc': 90,
          't': null,
        };
        final run = <String, dynamic>{
          'n': 'Running',
          'min': 10,
          'km': 2.0,
          'st': 200,
          'kc': 150,
          't': null,
        };
        store.acts
          ..add(walk)
          ..add(run);
        store.d['steps'] = 300;
        store.save();

        await tester.pumpWidget(
          const MaterialApp(home: Scaffold(body: ActivityScreen())),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Brisk walk'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Remove'));
        await tester.pumpAndSettle();

        expect(store.acts, hasLength(1));
        expect(store.acts.single['n'], 'Running');
        expect(store.steps, 200);
      },
    );
  });

  group('empty and malformed routines', () {
    testWidgets('EditRoutine refuses to save a routine with no exercises', (
      tester,
    ) async {
      await freshStore();
      final src = <String, dynamic>{
        'id': 1,
        'name': 'Empty',
        'type': 'Strength',
        'ex': <dynamic>[],
      };
      await pushScreen(tester, EditRoutine(src));

      final saveButton = find.widgetWithText(FilledButton, 'Save routine');
      expect(tester.widget<FilledButton>(saveButton).onPressed, isNull);
      expect(store.routines, isEmpty);
      expect(find.text('Edit routine'), findsOneWidget); // still editing
    });

    testWidgets(
      'WorkoutScreen with an empty routine explains itself and never traps',
      (tester) async {
        await freshStore();
        await pushScreen(
          tester,
          WorkoutScreen({'id': 'empty', 'name': 'Empty', 'ex': <dynamic>[]}),
        );
        await tester.pumpAndSettle();

        expect(find.text('This routine has no exercises.'), findsOneWidget);
        expect(store.d['activeW'], isNull); // empty sessions are not persisted

        final nextButton = find.widgetWithText(FilledButton, 'Next ›');
        expect(tester.widget<FilledButton>(nextButton).onPressed, isNull);
        await tester.tap(find.byTooltip('Session options'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Discard session'));
        await tester.pumpAndSettle();
        expect(
          find.text("Discard this session? Your sets won't be saved."),
          findsOneWidget,
        );
        await tester.tap(find.text('Discard'));
        await tester.pumpAndSettle();
        expect(find.byType(WorkoutScreen), findsNothing);
        expect(store.d['activeW'], isNull);
      },
    );

    testWidgets('WorkoutScreen tolerates a routine with no ex key at all', (
      tester,
    ) async {
      await freshStore();
      await pushScreen(
        tester,
        WorkoutScreen({'id': 'weird', 'name': 'Weird'}), // no 'ex' key
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('This routine has no exercises.'), findsOneWidget);
    });
  });

  group('routine editor field state', () {
    testWidgets('removing an exercise keeps later rows\' in-progress values', (
      tester,
    ) async {
      await freshStore();
      final src = <String, dynamic>{
        'id': 1,
        'name': 'Test',
        'type': 'Strength',
        'ex': [
          {'n': 'Push-ups', 'm': 'Chest', 's': 3, 'r': 15, 'rest': 45},
          {'n': 'Squats', 'm': 'Legs', 's': 3, 'r': 12, 'rest': 60},
          {'n': 'Plank', 'm': 'Core', 's': 3, 'r': 30, 'rest': 30},
        ],
      };
      await pushScreen(tester, EditRoutine(src));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Squats'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Increase Sets'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('More options for Push-ups'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove'));
      await tester.pump();

      expect(find.text('Squats'), findsOneWidget);
      expect(find.text('Push-ups'), findsNothing);
      expect(find.text('4'), findsOneWidget);
      expect(find.text('Undo'), findsOneWidget);
    });
  });

  group('deleted scheduled routines', () {
    testWidgets(
      'Today shows a deleted-routine card instead of "Nothing scheduled"',
      (tester) async {
        await freshStore();
        store.d['sch'] = [
          {'id': 1, 'r': 99, 'd': today(), 't': '18:00'},
        ];
        store.save();

        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(body: TodayTab(goTo: _ignoreTab)),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('(deleted routine)'), findsOneWidget);
        expect(find.text('Nothing scheduled'), findsNothing);
        expect(find.textContaining('was deleted'), findsOneWidget);
        expect(find.textContaining('Start workout'), findsNothing);
      },
    );

    testWidgets('Today shows the redesigned empty workout state', (
      tester,
    ) async {
      await freshStore();
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: TodayTab(goTo: _ignoreTab)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Nothing planned yet'), findsOneWidget);
    });

    testWidgets(
      'Schedule entry for a deleted routine hides Start and explains',
      (tester) async {
        await freshStore();
        store.d['sch'] = [
          {'id': 1, 'r': 99, 'd': today(), 't': '18:00'},
        ];
        store.save();

        await tester.pumpWidget(
          const MaterialApp(home: Scaffold(body: ScheduleTab())),
        );
        await tester.pumpAndSettle();

        expect(find.text('(deleted routine)'), findsOneWidget);
        expect(find.textContaining('routine deleted'), findsOneWidget);
        expect(find.textContaining('0 min'), findsNothing);

        await tester.tap(find.byTooltip('Workout options'));
        await tester.pumpAndSettle();
        expect(find.text('Start workout'), findsNothing);
        expect(find.text('Delete'), findsOneWidget);
      },
    );

    testWidgets('Schedule entry with a live routine still offers Start', (
      tester,
    ) async {
      await freshStore();
      store.d['routines'] = [
        {
          'id': 7,
          'name': 'Push day',
          'type': 'Strength',
          'ex': [
            {'n': 'Push-ups', 'm': 'Chest', 's': 3, 'r': 15, 'rest': 45},
          ],
        },
      ];
      store.d['sch'] = [
        {'id': 1, 'r': 7, 'd': today(), 't': '18:00'},
      ];
      store.save();

      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: ScheduleTab())),
      );
      await tester.pumpAndSettle();

      expect(find.text('Push day'), findsOneWidget);
      await tester.tap(find.byTooltip('Workout options'));
      await tester.pumpAndSettle();
      expect(find.text('Start workout'), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);
    });
  });

  group('progress history empty state', () {
    testWidgets(
      'View all is hidden with no history and shown once history exists',
      (tester) async {
        largeViewport(tester);
        await freshStore();
        await tester.pumpWidget(
          const MaterialApp(home: Scaffold(body: ProgressTab())),
        );
        await tester.pumpAndSettle();
        expect(find.text('View all'), findsNothing);

        store.hist.add({
          'n': 'Push day',
          'd': today(),
          'min': 30,
          'ex': 3,
          'kc': 220,
        });
        store.save();
        await tester.pumpAndSettle();
        expect(find.text('View all'), findsOneWidget);
      },
    );
  });

  group('local-first sign-out', () {
    testWidgets(
      'remote sign-out failure still signs the user out locally, with a warning',
      (tester) async {
        largeViewport(tester);
        await freshStore();
        store.activateGoogleAccount(
          uid: 'uid-1',
          email: 'user@example.com',
          displayName: 'User',
        );
        GoogleAuthService.debugSignOutOverride = () async {
          throw FirebaseAuthException(code: 'network-request-failed');
        };
        addTearDown(() => GoogleAuthService.debugSignOutOverride = null);

        await tester.pumpWidget(
          const MaterialApp(home: Scaffold(body: ProfileTab())),
        );
        await tester.pumpAndSettle();

        await tapBtn(tester, 'Log out');
        await tester.pumpAndSettle();

        expect(store.hasActiveSession, isFalse);
        expect(store.sessionUid, isNull);
        expect(
          find.textContaining('signed out on this device'),
          findsOneWidget,
        );
      },
    );

    testWidgets('a successful remote sign-out still ends the local session', (
      tester,
    ) async {
      largeViewport(tester);
      await freshStore();
      store.activateGoogleAccount(
        uid: 'uid-2',
        email: 'user2@example.com',
        displayName: 'User Two',
      );
      GoogleAuthService.debugSignOutOverride = () async {};
      addTearDown(() => GoogleAuthService.debugSignOutOverride = null);

      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: ProfileTab())),
      );
      await tester.pumpAndSettle();

      await tapBtn(tester, 'Log out');
      await tester.pumpAndSettle();

      expect(store.hasActiveSession, isFalse);
      expect(find.textContaining('signed out on this device'), findsNothing);
    });
  });

  group('water custom amount and undo', () {
    testWidgets('activity logging is not duplicated on the water screen', (
      tester,
    ) async {
      await freshStore();
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: WaterScreen())),
      );
      await tester.pumpAndSettle();

      expect(find.text('+ Log physical activity'), findsNothing);
    });

    testWidgets('invalid custom amount is rejected with a message', (
      tester,
    ) async {
      await freshStore();
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: WaterScreen())),
      );
      await tester.pumpAndSettle();

      await tapBtn(tester, 'Custom');
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'abc');
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();

      expect(
        find.text('Enter a positive amount of millilitres.'),
        findsOneWidget,
      );
      expect(store.water(), 0);

      // A valid amount still works.
      await tapBtn(tester, 'Custom');
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, '330');
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();
      expect(store.water(), 330);
    });

    testWidgets('zero and negative custom amounts are rejected', (
      tester,
    ) async {
      await freshStore();
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: WaterScreen())),
      );
      await tester.pumpAndSettle();

      for (final bad in ['0', '-100']) {
        await tapBtn(tester, 'Custom');
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField).first, bad);
        await tester.tap(find.text('Add'));
        await tester.pumpAndSettle();
        expect(
          find.text('Enter a positive amount of millilitres.'),
          findsOneWidget,
        );
        expect(store.water(), 0);
      }
    });

    testWidgets(
      'Undo is disabled with nothing logged and removes the last drink when enabled',
      (tester) async {
        await freshStore();
        await tester.pumpWidget(
          const MaterialApp(home: Scaffold(body: WaterScreen())),
        );
        await tester.pumpAndSettle();

        final undoButton = find.ancestor(
          of: find.text('Undo'),
          matching: find.byType(TextButton),
        );
        expect(tester.widget<TextButton>(undoButton).onPressed, isNull);

        await tester.tap(find.text('+ 250 ml'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('+ 250 ml'));
        await tester.pumpAndSettle();
        expect(store.water(), 500);

        expect(tester.widget<TextButton>(undoButton).onPressed, isNotNull);
        await tester.tap(find.text('Undo'));
        await tester.pumpAndSettle();
        expect(store.water(), 250);
      },
    );
  });
}
