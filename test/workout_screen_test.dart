import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fittract/screens/today_tab.dart';
import 'package:fittract/screens/workout_screen.dart';
import 'package:fittract/store/store.dart';

Map<String, dynamic> routine({
  String id = 'r-push',
  String name = 'Push Day',
  String type = 'Strength',
}) => {
  'id': id,
  'name': name,
  'type': type,
  'ex': <Map<String, dynamic>>[
    {'n': 'Bench Press', 'm': 'Chest', 's': 3, 'r': 8, 'rest': 45},
    {'n': 'Squat', 'm': 'Legs', 's': 2, 'r': 5, 'rest': 30},
  ],
};

Future<void> freshStore() async {
  SharedPreferences.setMockInitialValues({});
  await store.init();
}

void setLargeViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(1100, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Future<void> pushScreen(WidgetTester tester, Widget page) async {
  setLargeViewport(tester);
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

void main() {
  testWidgets('category header, compact sticky timer, pause and resume', (
    tester,
  ) async {
    await freshStore();
    await pushScreen(tester, WorkoutScreen(routine(type: 'Cardio')));

    expect(find.text('CARDIO · LIVE SESSION'), findsOneWidget);
    expect(find.text('Exercise 1 of 2 · 0 done'), findsOneWidget);
    expect(find.text('00:00'), findsOneWidget);

    await tester.tap(find.byTooltip('Pause'));
    await tester.pump();
    expect(find.text('Paused'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('00:00'), findsOneWidget);

    await tester.tap(find.byTooltip('Resume'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('00:02'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('set completion shows timer rest controls and autosaves', (
    tester,
  ) async {
    await freshStore();
    await pushScreen(tester, WorkoutScreen(routine()));

    await tester.tap(find.byTooltip('Complete set 1'));
    await tester.pump();
    expect(find.text('Rest 00:45'), findsOneWidget);
    expect((store.d['activeW'] as Map)['sets'][0][0]['ok'], isTrue);

    await tester.tap(find.text('+15s'));
    await tester.pump();
    expect(find.text('Rest 01:00'), findsOneWidget);
    await tester.tap(find.text('Skip'));
    await tester.pump();
    expect(find.textContaining('Rest 00:'), findsNothing);
    expect((store.d['activeW'] as Map)['restLeft'], 0);

    await tester.enterText(find.byKey(const ValueKey('kg00')), '41.5');
    await tester.pump();
    expect(((store.d['activeW'] as Map)['sets'] as List)[0][0]['kg'], 41.5);
  });

  testWidgets('all sets done banner appears and last final set skips rest', (
    tester,
  ) async {
    await freshStore();
    await pushScreen(tester, WorkoutScreen(routine()));

    for (final set in [1, 2, 3]) {
      await tester.tap(find.byTooltip('Complete set $set'));
      await tester.pump();
      if (set < 3) {
        await tester.tap(find.text('Skip'));
        await tester.pump();
      }
    }
    expect(find.text('All sets done ✓'), findsOneWidget);
    expect((store.d['activeW'] as Map)['done'], <bool>[true, false]);

    await tester.tap(find.text('Next ›'));
    await tester.pump();
    await tester.tap(find.byTooltip('Complete set 1'));
    await tester.pump();
    await tester.tap(find.text('Skip'));
    await tester.pump();
    await tester.tap(find.byTooltip('Complete set 2'));
    await tester.pump();
    expect(find.text('All sets done ✓'), findsOneWidget);
    expect(find.textContaining('Rest '), findsNothing);
    expect((store.d['activeW'] as Map)['done'], <bool>[true, true]);
  });

  testWidgets('bodyweight switch and time-based exercises adjust set columns', (
    tester,
  ) async {
    await freshStore();
    await pushScreen(
      tester,
      WorkoutScreen({
        'id': 'r-circuit',
        'name': 'Circuit',
        'type': 'Cardio',
        'ex': [
          {'n': 'Burpees', 'm': 'Cardio', 's': 2, 'r': 12, 'rest': 30},
          {'n': 'Mountain climbers', 'm': 'Core', 's': 4, 'r': 30, 'rest': 30},
        ],
      }),
    );

    expect(find.text('CARDIO · LIVE SESSION'), findsOneWidget);
    expect(find.text('SET'), findsOneWidget);
    expect(find.text('REPS'), findsOneWidget);
    expect(find.byKey(const ValueKey('kg00')), findsNothing);

    await tester.tap(find.text('Next ›'));
    await tester.pump();
    expect(find.text('REPS'), findsNothing);
    expect(find.text('4 × 30 sec · 30 sec rest'), findsOneWidget);
    expect(find.text('SEC'), findsOneWidget);
    expect(find.text('KG'), findsNothing);
    expect(find.byKey(const ValueKey('kg10')), findsNothing);
    expect(find.text('4 × 30 sec'), findsOneWidget);
  });

  testWidgets('previous session values are referenced and prefilled', (
    tester,
  ) async {
    await freshStore();
    store.d['lastWorkout'] = {
      'r-push': {
        'Bench Press': [
          {'kg': 42.5, 'rp': 9},
          {'kg': 45, 'rp': 8},
        ],
      },
    };
    await pushScreen(tester, WorkoutScreen(routine()));

    expect(find.text('Last time: 42.5 kg × 9 reps'), findsOneWidget);
    final firstWeight = tester.widget<TextFormField>(
      find.byKey(const ValueKey('kg00')),
    );
    expect(firstWeight.initialValue, '42.5');
    final secondWeight = tester.widget<TextFormField>(
      find.byKey(const ValueKey('kg01')),
    );
    expect(secondWeight.initialValue, '45');
  });

  testWidgets('back asks to stay or pause and exit with saved progress', (
    tester,
  ) async {
    await freshStore();
    await pushScreen(tester, WorkoutScreen(routine()));
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();

    expect(find.text('Leave session?'), findsOneWidget);
    expect(find.text('Stay'), findsOneWidget);
    expect(find.text('Pause & exit'), findsOneWidget);
    await tester.tap(find.text('Stay'));
    await tester.pumpAndSettle();
    expect(find.byType(WorkoutScreen), findsOneWidget);

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pause & exit'));
    await tester.pumpAndSettle();
    expect(find.byType(WorkoutScreen), findsNothing);
    expect((store.d['activeW'] as Map)['paused'], isTrue);
  });

  testWidgets('session menu confirms discard and does not record history', (
    tester,
  ) async {
    await freshStore();
    await pushScreen(tester, WorkoutScreen(routine()));

    await tester.tap(find.byTooltip('Session options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard session'));
    await tester.pumpAndSettle();
    expect(
      find.text("Discard this session? Your sets won't be saved."),
      findsOneWidget,
    );
    await tester.tap(find.text('Keep session'));
    await tester.pumpAndSettle();
    expect(find.byType(WorkoutScreen), findsOneWidget);
    expect(store.d.containsKey('activeW'), isTrue);
    expect(store.hist, isEmpty);
  });

  testWidgets('finishing incomplete workout confirms and shows summary', (
    tester,
  ) async {
    await freshStore();
    await pushScreen(tester, WorkoutScreen(routine()));

    await tester.ensureVisible(find.text('Finish workout'));
    await tester.tap(find.text('Finish workout'));
    await tester.pumpAndSettle();
    expect(
      find.text('Finish workout? 2 exercises not done. Finish anyway?'),
      findsOneWidget,
    );
    await tester.tap(find.text('Keep going'));
    await tester.pumpAndSettle();
    expect(find.byType(WorkoutScreen), findsOneWidget);

    await tester.ensureVisible(find.text('Finish workout'));
    await tester.tap(find.text('Finish workout'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Finish'));
    await tester.pumpAndSettle();
    expect(find.text('Workout complete'), findsOneWidget);
    expect(find.text('Sets completed: 0 / 5'), findsOneWidget);
    expect(find.text('Volume: 0 kg × reps'), findsOneWidget);
    expect(store.d.containsKey('activeW'), isFalse);
    expect(store.hist, hasLength(1));
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.byType(WorkoutScreen), findsNothing);
  });

  testWidgets('Today offers to resume a saved workout', (tester) async {
    await freshStore();
    store.d['activeW'] = {
      'rid': 'r-push',
      'name': 'Push Day',
      'routine': routine(),
      'i': 1,
      'secs': 32,
      'done': <bool>[true, false],
      'sets': [
        [
          {'kg': 40, 'rp': 8, 'ok': true},
          {'kg': 40, 'rp': 8, 'ok': true},
          {'kg': 40, 'rp': 8, 'ok': true},
        ],
        [
          {'kg': 60, 'rp': 5, 'ok': false},
          {'kg': 60, 'rp': 5, 'ok': false},
        ],
      ],
      'bodyweight': <bool>[false, false],
    };
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: TodayTab(goTo: _ignoreTab)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('WORKOUT IN PROGRESS'), findsOneWidget);
    expect(find.text('Resume workout'), findsOneWidget);
    expect(find.text('Nothing scheduled'), findsNothing);
  });

  testWidgets('checklist jumps to exercise and marks the active row', (
    tester,
  ) async {
    await freshStore();
    await pushScreen(tester, WorkoutScreen(routine()));

    final current = tester.widget<Semantics>(
      find.byWidgetPredicate(
        (widget) =>
            widget is Semantics &&
            widget.properties.label == 'Bench Press, current exercise',
      ),
    );
    expect(current.properties.selected, isTrue);
    await tester.tap(find.text('Squat').last);
    await tester.pump();
    expect(find.text('Squat'), findsWidgets);
    expect(find.text('Exercise 2 of 2 · 0 done'), findsOneWidget);
  });
}

void _ignoreTab(int _) {}
