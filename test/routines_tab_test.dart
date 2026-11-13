import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fittract/screens/routines_tab.dart';
import 'package:fittract/store/store.dart';

Future<void> freshStore() async {
  SharedPreferences.setMockInitialValues({});
  await store.init();
}

void setLargeViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(1100, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Future<void> mountRoutines(WidgetTester tester) async {
  await tester.pumpWidget(
    const MaterialApp(home: Scaffold(body: RoutinesTab())),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('empty routines state links to Explore and starter routines', (
    tester,
  ) async {
    setLargeViewport(tester);
    await freshStore();
    await mountRoutines(tester);

    expect(
      find.text('No routines yet. Start with one that fits your week.'),
      findsOneWidget,
    );
    expect(find.text('0 routines'), findsNothing);
    await tester.tap(find.text('Try a starter routine'));
    await tester.pumpAndSettle();

    expect(find.text('Popular this week'), findsOneWidget);
    expect(find.text('Gentle mobility flow'), findsOneWidget);
  });

  testWidgets('Explore filters, previews and adds a starter with View action', (
    tester,
  ) async {
    setLargeViewport(tester);
    await freshStore();
    await mountRoutines(tester);

    await tester.tap(find.text('Try a starter routine'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'Mobility'));
    await tester.pumpAndSettle();

    expect(find.text('Gentle mobility flow'), findsOneWidget);
    expect(find.text('Push day'), findsNothing);
    await tester.tap(find.text('Gentle mobility flow'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Cat-cow stretch'), findsOneWidget);

    await tester.tap(find.text('+ Add'));
    await tester.pumpAndSettle();
    expect(store.routines, hasLength(1));
    expect(find.text('Added ✓'), findsOneWidget);
    expect(
      find.text('Added Gentle mobility flow to My routines'),
      findsOneWidget,
    );

    await tester.tap(find.text('View'));
    await tester.pumpAndSettle();
    expect(find.text('Gentle mobility flow'), findsOneWidget);
    expect(find.text('Create routine'), findsOneWidget);
    expect(find.text('1 routine'), findsOneWidget);
  });

  testWidgets('routine card actions and delete confirmation are clear', (
    tester,
  ) async {
    setLargeViewport(tester);
    await freshStore();
    store.d['routines'] = [
      {
        'id': 42,
        'name': 'Quick cardio',
        'type': 'Cardio',
        'ex': <Map<String, dynamic>>[],
      },
    ];
    await mountRoutines(tester);

    expect(find.text('Your routine'), findsOneWidget);
    expect(find.text('1 routine'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Start'), findsOneWidget);
    expect(find.byTooltip('Routine options for Quick cardio'), findsOneWidget);

    await tester.tap(find.byTooltip('Routine options for Quick cardio'));
    await tester.pumpAndSettle();
    expect(find.text('Start workout'), findsOneWidget);
    expect(find.text('Edit routine'), findsOneWidget);
    expect(find.text('Delete routine'), findsOneWidget);

    await tester.tap(find.text('Delete routine'));
    await tester.pumpAndSettle();
    expect(find.text('Delete this routine?'), findsOneWidget);
    expect(store.routines, hasLength(1));
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(store.routines, hasLength(1));

    await tester.tap(find.byTooltip('Routine options for Quick cardio'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete routine'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(store.routines, isEmpty);
  });

  testWidgets('the whole routine card opens its editor', (tester) async {
    setLargeViewport(tester);
    await freshStore();
    store.d['routines'] = [
      {
        'id': 42,
        'name': 'Tap to edit',
        'type': 'Strength',
        'ex': <Map<String, dynamic>>[],
      },
    ];
    await mountRoutines(tester);

    await tester.tap(find.text('Tap to edit'));
    await tester.pumpAndSettle();
    expect(find.byType(EditRoutine), findsOneWidget);
  });

  testWidgets('My routines search shows its no-match message', (tester) async {
    setLargeViewport(tester);
    await freshStore();
    store.d['routines'] = [
      {
        'id': 42,
        'name': 'Quick cardio',
        'type': 'Cardio',
        'ex': <Map<String, dynamic>>[],
      },
    ];
    await mountRoutines(tester);

    await tester.enterText(find.byType(TextField), 'not found');
    await tester.pumpAndSettle();
    expect(find.text('No routines match your search.'), findsOneWidget);
  });

  testWidgets('routine editor requires a name and asks before discarding', (
    tester,
  ) async {
    setLargeViewport(tester);
    await freshStore();
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () {
                Navigator.push<void>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => EditRoutine({
                      'id': 42,
                      'name': '',
                      'type': 'Strength',
                      'isNew': true,
                      'ex': [
                        {
                          'n': 'Push-ups',
                          'm': 'Chest',
                          's': 3,
                          'r': 12,
                          'rest': 45,
                        },
                      ],
                    }),
                  ),
                );
              },
              child: const Text('Open editor'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open editor'));
    await tester.pumpAndSettle();

    expect(find.text('NEW ROUTINE'), findsOneWidget);
    expect(find.text('Name your routine'), findsOneWidget);
    expect(find.text('e.g. Push day'), findsOneWidget);
    final saveButton = find.widgetWithText(FilledButton, 'Save routine');
    expect(tester.widget<FilledButton>(saveButton).onPressed, isNull);

    await tester.enterText(find.byType(TextField).first, 'Push day');
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(saveButton).onPressed, isNotNull);

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Discard changes?'), findsOneWidget);
    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();
    expect(find.byType(EditRoutine), findsOneWidget);

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(find.byType(EditRoutine), findsNothing);
  });
}
