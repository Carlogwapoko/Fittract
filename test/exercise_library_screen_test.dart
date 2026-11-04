import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fittract/screens/exercise_library_screen.dart';

void setLargeViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(1100, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('exercise cards toggle selection across the full card', (
    tester,
  ) async {
    setLargeViewport(tester);
    await tester.pumpWidget(
      const MaterialApp(home: ExerciseLibraryScreen(title: 'Create a routine')),
    );
    await tester.pumpAndSettle();

    expect(find.text('LEVEL'), findsOneWidget);
    expect(find.text('MUSCLE'), findsOneWidget);
    expect(find.text('Pick at least 1 exercise'), findsOneWidget);

    await tester.tap(find.text('Push-ups'));
    await tester.pumpAndSettle();
    expect(find.text('Continue (1 selected)'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle), findsOneWidget);

    await tester.tap(find.text('Push-ups'));
    await tester.pumpAndSettle();
    expect(find.text('Pick at least 1 exercise'), findsOneWidget);
  });

  testWidgets('filters lead to a validated, timed custom exercise', (
    tester,
  ) async {
    setLargeViewport(tester);
    List<Map<String, dynamic>>? selectedExercises;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                selectedExercises = await Navigator.of(context)
                    .push<List<Map<String, dynamic>>>(
                      MaterialPageRoute(
                        builder: (_) => const ExerciseLibraryScreen(
                          title: 'Create a routine',
                        ),
                      ),
                    );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ChoiceChip, 'Advanced').first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'Core').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'plank');
    await tester.pumpAndSettle();
    expect(find.text('0 exercises'), findsOneWidget);

    await tester.tap(find.text("Can't find it? Create a custom exercise"));
    await tester.pumpAndSettle();

    final nameField = find.byType(TextField).last;
    await tester.enterText(nameField, '   ');
    await tester.pumpAndSettle();
    expect(find.text('Name cannot contain only spaces'), findsOneWidget);

    await tester.enterText(nameField, 'Timed plank');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Time'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Increase Duration'));
    await tester.pumpAndSettle();
    expect(
      find.text('Timed plank · 3 × 35 sec · 60s rest · Beginner · Chest'),
      findsOneWidget,
    );

    final saveButton = find.widgetWithText(FilledButton, 'Add custom exercise');
    expect(tester.widget<FilledButton>(saveButton).onPressed, isNotNull);
    await tester.tap(saveButton);
    await tester.pumpAndSettle();
    expect(find.text('Continue (1 selected)'), findsOneWidget);
    await tester.tap(find.text('Continue (1 selected)'));
    await tester.pumpAndSettle();
    expect(selectedExercises?.single['unit'], 'sec');
    expect(selectedExercises?.single['r'], 35);
  });
}
