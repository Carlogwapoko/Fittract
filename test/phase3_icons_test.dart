import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fittract/screens/exercise_library_screen.dart';
import 'package:fittract/screens/activity_screen.dart';
import 'package:fittract/screens/food_screen.dart';
import 'package:fittract/screens/meal_picker_screen.dart';
import 'package:fittract/screens/routines_tab.dart';
import 'package:fittract/screens/workout_screen.dart';
import 'package:fittract/services/activity_tracking_service.dart';
import 'package:fittract/store/store.dart';
import 'package:fittract/widgets/log_activity_sheet.dart';
import 'package:fittract/widgets/shared_widgets.dart';

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

/// Hosts [page] on top of a still-mounted home route so back navigation has
/// somewhere to return to. The unique key gives each call a fresh navigator:
/// pumpWidget reuses the previous Navigator state (and any route it holds),
/// which would leave HOME offstage behind an earlier push.
Future<void> pushScreen(WidgetTester tester, Widget page) async {
  largeViewport(tester);
  await tester.pumpWidget(
    MaterialApp(
      key: UniqueKey(),
      home: const Scaffold(body: Center(child: Text('HOME'))),
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
  group('exercise icon selection', () {
    test('identity, bodyweight, equipment, group, and default tiers', () {
      // Movement identity: Material has a genuinely matching icon.
      expect(exerciseIconFor('Running', 'Cardio'), Icons.directions_run);
      expect(
        exerciseIconFor('Sprint intervals', 'Cardio'),
        Icons.directions_run,
      );
      expect(exerciseIconFor('Cycling', 'Cardio'), Icons.directions_bike);
      expect(exerciseIconFor('Plank', 'Core'), Icons.self_improvement);
      expect(exerciseIconFor('Swimming', 'Cardio'), Icons.pool);

      // Bodyweight: a plain figure, no equipment implied.
      expect(exerciseIconFor('Push-ups', 'Chest'), Icons.accessibility_new);
      expect(
        exerciseIconFor('Bodyweight squat', 'Legs'),
        Icons.accessibility_new,
      );
      expect(exerciseIconFor('Glute bridge', 'Legs'), Icons.accessibility_new);
      expect(exerciseIconFor('Jump rope', 'Cardio'), Icons.accessibility_new);

      // Equipment cues: barbell/dumbbell/cable work.
      expect(
        exerciseIconFor('Barbell bench press', 'Chest'),
        Icons.fitness_center,
      );
      expect(exerciseIconFor('Pull-ups', 'Back'), Icons.fitness_center);
      expect(exerciseIconFor('Back squat', 'Legs'), Icons.fitness_center);
      expect(exerciseIconFor('Seated cable row', 'Back'), Icons.fitness_center);

      // Custom/legacy exercises: muscle-group category, then safe default.
      expect(exerciseIconFor('Dragon flags', 'Core'), Icons.self_improvement);
      expect(exerciseIconFor('Sled pushes', 'Cardio'), Icons.bolt);
      expect(exerciseIconFor('Mystery move'), Icons.fitness_center);
      expect(exerciseIconFor(null, null), Icons.fitness_center);
    });

    testWidgets(
      'library, routine rows, and the live workout card share one icon per exercise',
      (tester) async {
        largeViewport(tester);
        await freshStore();

        // Exercise library (filtered so the row is certainly on screen).
        await tester.pumpWidget(
          const MaterialApp(home: ExerciseLibraryScreen()),
        );
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField).first, 'Plank');
        await tester.pumpAndSettle();
        expect(find.byIcon(Icons.self_improvement), findsOneWidget);

        final routine = <String, dynamic>{
          'id': 77,
          'name': 'Core',
          'type': 'Strength',
          'ex': [
            {'n': 'Plank', 'm': 'Core', 's': 3, 'r': 30, 'rest': 30},
            {'n': 'Push-ups', 'm': 'Chest', 's': 3, 'r': 12, 'rest': 45},
          ],
        };

        // Routine editor row: both exercises visible, same icons as the library.
        await pushScreen(tester, EditRoutine(routine));
        await tester.pumpAndSettle();
        expect(find.byIcon(Icons.self_improvement), findsOneWidget);
        expect(find.byIcon(Icons.accessibility_new), findsOneWidget);

        // Live workout card shows the current exercise's icon.
        await pushScreen(tester, WorkoutScreen(routine));
        await tester.pumpAndSettle();
        expect(find.byIcon(Icons.self_improvement), findsOneWidget);
      },
    );
  });

  group('meal icon consistency', () {
    test('presets keep their icon by name; others fall back by type', () {
      expect(
        mealIconFor('Oatmeal with berries', 'Breakfast'),
        Icons.breakfast_dining_outlined,
      );
      expect(
        mealIconFor('oatmeal WITH BERRIES', 'breakfast'),
        Icons.breakfast_dining_outlined,
      );
      expect(
        mealIconFor('Greek yogurt parfait', 'Breakfast'),
        Icons.icecream_outlined,
      );
      expect(
        mealIconFor('Chicken rice bowl', 'Lunch'),
        Icons.rice_bowl_outlined,
      );

      // Unknown/manual meals: deterministic meal-type fallback.
      expect(
        mealIconFor('Homemade pasta', 'Lunch'),
        Icons.lunch_dining_outlined,
      );
      expect(mealIconFor('Chips', 'Snack'), Icons.cookie_outlined);
      expect(
        mealIconFor('Porridge', 'Breakfast'),
        Icons.free_breakfast_outlined,
      );

      // Missing type or name: the safe dinner default.
      expect(mealIconFor(null, 'Dinner'), Icons.dinner_dining_outlined);
      expect(mealIconFor('Anything', null), Icons.dinner_dining_outlined);
      expect(mealIconFor(null, null), Icons.dinner_dining_outlined);
    });

    testWidgets(
      'preset picture survives selection, logging, save, and reload',
      (tester) async {
        largeViewport(tester);
        await freshStore();
        await tester.pumpWidget(const MaterialApp(home: MealPickerScreen()));
        await tester.pumpAndSettle();

        // The picker shows the preset's food photo.
        expect(
          find.byWidgetPredicate(
            (widget) =>
                widget is Image &&
                widget.image is AssetImage &&
                (widget.image as AssetImage).assetName ==
                    'assets/images/Oatmeal_with_berries.jpg',
          ),
          findsOneWidget,
        );

        await tester.tap(find.text('Add to today').first);
        await tester.pumpAndSettle();
        expect(store.meals, hasLength(1));

        // No icon metadata is persisted: the meal schema is untouched.
        final saved = store.meals.single as Map;
        expect(saved.containsKey('icon'), isFalse);
        expect(saved.containsKey('ic'), isFalse);
        expect(saved.keys, containsAll(['t', 'n', 'k', 'p', 'c', 'f']));

        // Save and reload through JSON, as a real session would.
        store.save();
        store.d['meals'] = jsonDecode(jsonEncode(store.d['meals']));

        await tester.pumpWidget(const MaterialApp(home: FoodScreen()));
        await tester.pumpAndSettle();

        // Same photo as the picker offered, even after JSON serialization.
        expect(find.text('Oatmeal with berries'), findsOneWidget);
        expect(
          find.byWidgetPredicate(
            (widget) =>
                widget is Image &&
                widget.image is AssetImage &&
                (widget.image as AssetImage).assetName ==
                    'assets/images/Oatmeal_with_berries.jpg',
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets('manual entry offers camera and gallery photo entry points', (
      tester,
    ) async {
      largeViewport(tester);
      await freshStore();

      await tester.pumpWidget(const MaterialApp(home: ManualMealScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Choose from gallery'), findsOneWidget);
      expect(find.text('Scan your food'), findsOneWidget);
      expect(
        find.text(
          'A compressed photo is sent securely for ingredient analysis.',
        ),
        findsOneWidget,
      );
      expect(find.text('Food photo (optional)'), findsNothing);
      expect(
        find.text('No ingredients yet. Scan your food or add them manually.'),
        findsOneWidget,
      );
    });

    testWidgets('legacy meals without icon metadata render safely', (
      tester,
    ) async {
      largeViewport(tester);
      await freshStore();
      store.d['meals'] = [
        // Saved by an older build: preset name, nutrition, no icon metadata.
        {
          't': 'Breakfast',
          'n': 'Greek yogurt parfait',
          'desc': '',
          'k': 280,
          'p': 18,
          'c': 38,
          'f': 7,
        },
        // Manual meal: only its meal type can decide the icon.
        {
          't': 'Snack',
          'n': 'Chips',
          'desc': '',
          'k': 200,
          'p': 2,
          'c': 20,
          'f': 12,
        },
        // Degenerate legacy row: no meal type at all.
        {'t': null, 'n': 'Mystery morsel', 'k': 100, 'p': 1, 'c': 10, 'f': 4},
      ];
      store.save();

      await tester.pumpWidget(const MaterialApp(home: FoodScreen()));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // Presets use their bundled photos; manual/legacy rows keep category icons.
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Image &&
              widget.image is AssetImage &&
              (widget.image as AssetImage).assetName ==
                  'assets/images/Greek-Yogurt-Parfait.jpg',
        ),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.cookie_outlined), findsOneWidget);
      expect(find.byIcon(Icons.dinner_dining_outlined), findsOneWidget);
      expect(find.byIcon(Icons.free_breakfast_outlined), findsNothing);
      expect(find.text('Mystery morsel'), findsOneWidget);
    });
  });

  group('activity icon selection', () {
    test('maps each logged activity type and defaults for unknown names', () {
      expect(activityIconFor('Brisk walk'), Icons.directions_walk);
      expect(activityIconFor('Running'), Icons.directions_run);
      expect(activityIconFor('Cycling'), Icons.directions_bike);
      expect(activityIconFor('Swimming'), Icons.pool);
      expect(activityIconFor('Yoga'), Icons.self_improvement);
      expect(
        activityIconFor('Underwater basket weaving'),
        Icons.fitness_center,
      );
      expect(activityIconFor(null), Icons.fitness_center);
    });

    testWidgets('activity picker only offers step-related activities', (
      tester,
    ) async {
      await freshStore();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showLogActivity(context),
                child: const Text('Open activity picker'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open activity picker'));
      await tester.pumpAndSettle();

      expect(find.text('Cycling'), findsNothing);
      expect(find.text('Swimming'), findsNothing);
      expect(find.text('Yoga'), findsNothing);
      expect(find.text('Brisk walk'), findsOneWidget);
      expect(find.text('Running'), findsOneWidget);
    });

    testWidgets('activity sheet keeps manual logging as an alternate flow', (
      tester,
    ) async {
      await freshStore();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showLogActivity(context),
                child: const Text('Open activity picker'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open activity picker'));
      await tester.pumpAndSettle();
      expect(find.text('Duration'), findsNothing);
      expect(find.text('Add manually instead'), findsOneWidget);
      expect(find.text('kcal'), findsNothing);
      expect(find.text('--'), findsNWidgets(3));

      await tester.tap(find.text('Add manually instead'));
      await tester.pumpAndSettle();
      expect(find.text('Duration'), findsOneWidget);
      expect(find.text('15 min'), findsOneWidget);
      expect(find.text('Distance (km)'), findsOneWidget);
      expect(find.text('Save activity'), findsOneWidget);

      await tester.ensureVisible(find.text('Save activity'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save activity'));
      await tester.pumpAndSettle();
      expect(store.acts, hasLength(1));
      expect(store.acts.single['n'], 'Brisk walk');
      expect(store.acts.single['min'], 30);
      expect(store.acts.single['t'], isA<num>());
    });

    testWidgets('tracked activity stops, accepts distance, and saves', (
      tester,
    ) async {
      await freshStore();
      store.d['weights'] = [
        [today(), 70.0],
      ];
      store.d['h'] = 170;
      const locationChannel = MethodChannel('flutter.baseflow.com/geolocator');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(locationChannel, (call) async {
            if (call.method == 'isLocationServiceEnabled') return false;
            return 0;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(locationChannel, null),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showLogActivity(context),
                child: const Text('Open activity picker'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open activity picker'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Start'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Start'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Stop'), findsOneWidget);
      expect(find.text('GPS off, distance will be estimated'), findsOneWidget);
      expect(find.text('Distance (km)'), findsNothing);
      expect(find.text('Running'), findsOneWidget);

      await tester.runAsync(
        () => Future<void>.delayed(const Duration(seconds: 2)),
      );
      await tester.pump();
      expect(activityTracking.elapsedSeconds, greaterThanOrEqualTo(1));
      await tester.ensureVisible(find.text('Stop'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Stop'));
      await tester.pump();
      expect(find.text('Save activity'), findsOneWidget);
      expect(find.text('Distance (km)'), findsOneWidget);
      await tester.enterText(find.byType(TextField).last, '0.1');
      await tester.pump();
      expect(find.text('142'), findsOneWidget);

      await tester.tap(find.text('Save activity'));
      await tester.pumpAndSettle();

      final saved = store.acts.single;
      expect(saved['n'], 'Brisk walk');
      expect(saved['t'], isA<num>());
      expect(saved['durationSec'], greaterThanOrEqualTo(1));
      expect(saved['km'], 0.1);
      expect(saved['st'], 142);
      expect(
        saved['kc'],
        (4.3 * 70 * (saved['durationSec'] as int) / 3600).round(),
      );
      expect(store.steps, 142);
      expect(store.d['activeActivity'], isNull);
      expect(activityTracking.hasSession, isFalse);
    });

    testWidgets('movement screen can reopen a running activity session', (
      tester,
    ) async {
      await freshStore();
      const locationChannel = MethodChannel('flutter.baseflow.com/geolocator');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(locationChannel, (call) async {
            if (call.method == 'isLocationServiceEnabled') return false;
            return 0;
          });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(locationChannel, null);
      });

      await activityTracking.start('Brisk walk');
      largeViewport(tester);
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: ActivityScreen())),
      );
      await tester.pumpAndSettle();

      expect(find.text('Tracking in progress'), findsOneWidget);
      expect(find.text('Log an activity'), findsOneWidget);
      await tester.tap(find.text('Tracking in progress'));
      await tester.pumpAndSettle();
      expect(find.text('Stop'), findsOneWidget);
      expect(find.text('Brisk walk'), findsOneWidget);
      activityTracking.discard();
      await tester.pump();
    });

    testWidgets('activity history shows recorded type and delete glyph', (
      tester,
    ) async {
      largeViewport(tester);
      await freshStore();
      store.acts
        ..add({
          'n': 'Brisk walk',
          'min': 20,
          'km': 1.5,
          'st': 100,
          'kc': 90,
          't': null,
        })
        ..add({
          'n': 'Cycling',
          'min': 30,
          'km': 8.0,
          'st': 0,
          'kc': 210,
          't': null,
        });
      store.d['steps'] = 300;
      store.save();

      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: ActivityScreen())),
      );
      await tester.pumpAndSettle();

      // Each row wears its own activity icon; the old all-rows-run icon is gone.
      expect(find.byIcon(Icons.directions_walk), findsOneWidget);
      expect(find.byIcon(Icons.directions_bike), findsOneWidget);
      expect(find.byIcon(Icons.directions_run), findsNothing);

      // The trailing affordance is deletion, not the misleading chevron.
      expect(find.byIcon(Icons.delete_outline), findsNWidgets(2));
      expect(find.byIcon(Icons.chevron_right), findsNothing);
    });

    testWidgets(
      'delete affordance still asks before removing, with Phase 2 safety',
      (tester) async {
        largeViewport(tester);
        await freshStore();
        store.acts.add({
          'n': 'Swimming',
          'min': 30,
          'km': 0.5,
          'st': 40,
          'kc': 200,
          't': null,
        });
        store.d['steps'] = 100;
        store.save();

        await tester.pumpWidget(
          const MaterialApp(home: Scaffold(body: ActivityScreen())),
        );
        await tester.pumpAndSettle();

        // Tapping the delete glyph runs the same confirmation as the row.
        await tester.tap(find.byIcon(Icons.delete_outline));
        await tester.pumpAndSettle();
        expect(find.text('Remove this activity?'), findsOneWidget);

        // Cancel keeps the entry.
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(store.acts, hasLength(1));

        // Confirm removes exactly it and restores its steps.
        await tester.tap(find.byIcon(Icons.delete_outline));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Remove'));
        await tester.pumpAndSettle();
        expect(store.acts, isEmpty);
        expect(store.steps, 60);
        expect(find.text('Swimming'), findsNothing);
      },
    );
  });
}
