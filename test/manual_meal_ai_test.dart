import 'dart:async';

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fittract/screens/meal_picker_screen.dart';
import 'package:fittract/services/food_ai_service.dart';
import 'package:fittract/store/store.dart';

class _FakeFoodAiService implements FoodAiService {
  int nutritionCalls = 0;
  int scanCalls = 0;
  bool failNextEstimate = false;
  bool nutritionUnavailable = false;
  bool omitBundledNutrition = false;
  Completer<MealScanResult>? scanGate;
  final nutritionInputs = <List<MealIngredient>>[];
  final scannedPhotos = <Uint8List>[];

  @override
  Future<Uint8List> compressPhoto(Uint8List imageBytes) async => imageBytes;

  @override
  Future<MealScanResult> scanMeal(Uint8List jpegBytes) async {
    scanCalls++;
    scannedPhotos.add(Uint8List.fromList(jpegBytes));
    final gate = scanGate;
    if (gate != null) return gate.future;
    return MealScanResult(
      isFood: true,
      mealName: 'Egg and rice',
      mealType: 'Lunch',
      ingredients: [
        MealIngredient(name: 'Egg', amount: 2, unit: 'pcs'),
        MealIngredient(name: 'Rice', amount: 150, unit: 'g'),
      ],
      nutrition: nutritionUnavailable || omitBundledNutrition
          ? null
          : const NutritionEstimate(
              calories: 400,
              protein: 25,
              carbs: 55,
              fat: 10,
            ),
      nutritionUnavailable: nutritionUnavailable,
    );
  }

  @override
  Future<NutritionEstimate> estimateNutrition(
    List<MealIngredient> ingredients,
  ) async {
    nutritionCalls++;
    nutritionInputs.add(List.of(ingredients));
    if (failNextEstimate) {
      failNextEstimate = false;
      throw StateError('Offline');
    }
    return NutritionEstimate(
      calories: 250 + ingredients.length * 50,
      protein:
          20 +
          ingredients.length * 4 +
          ingredients.fold<double>(0, (total, item) => total + item.amount) /
              1000,
      carbs: 30 + ingredients.length * 5,
      fat: 10 + ingredients.length * 2,
    );
  }

  @override
  Future<bool> photoMatchesIngredients(
    Uint8List imageBytes,
    List<MealIngredient> ingredients,
  ) async => true;
}

Finder _field(String label) => find.byWidgetPredicate(
  (widget) =>
      widget is TextField &&
      widget.decoration?.labelText?.startsWith(label) == true,
);

void main() {
  test('ingredient serialization retains its nutrition source', () {
    expect(
      const MealIngredient(
        name: 'Rice',
        amount: 150,
        unit: 'g',
        source: 'USDA FoodData Central',
      ).toJson(),
      {
        'name': 'Rice',
        'amount': 150,
        'unit': 'g',
        'source': 'USDA FoodData Central',
      },
    );
  });

  testWidgets('estimates confirmed ingredients and preserves edited values', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1100, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final ai = _FakeFoodAiService();
    await tester.pumpWidget(MaterialApp(home: ManualMealScreen(aiService: ai)));

    expect(find.text('Ingredients'), findsOneWidget);
    expect(find.text('USDA + GEMINI'), findsNothing);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Add to food log'),
          )
          .onPressed,
      isNull,
    );

    await tester.tap(find.text('Add ingredient'));
    await tester.pumpAndSettle();
    await tester.enterText(_field('Ingredient name'), 'Egg');
    await tester.enterText(_field('Amount'), '2');
    await tester.tap(find.text('g').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('pcs').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pump();

    expect(ai.nutritionCalls, 1);
    expect(find.text('Egg'), findsOneWidget);
    expect(find.text('2 pcs'), findsOneWidget);
    expect(_field('Calories'), findsOneWidget);
    expect(
      tester.widget<TextField>(_field('Calories')).controller!.text,
      '300',
    );

    await tester.enterText(_field('Calories'), '777');
    await tester.pump();
    expect(find.text('Calories · Edited'), findsOneWidget);

    await tester.tap(find.text('Add ingredient'));
    await tester.pumpAndSettle();
    await tester.enterText(_field('Ingredient name'), 'Rice');
    await tester.enterText(_field('Amount'), '150');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pump();

    expect(ai.nutritionCalls, 2);
    expect(
      tester.widget<TextField>(_field('Calories')).controller!.text,
      '777',
    );
    expect(
      tester.widget<TextField>(_field('Protein')).controller!.text,
      '28.2',
    );
    expect(find.text('Egg'), findsOneWidget);
    expect(find.text('150 g'), findsOneWidget);

    await tester.tap(find.text('Recalculate nutrition'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(_field('Calories')).controller!.text,
      '350',
    );
    expect(find.text('Calories · Edited'), findsNothing);
  });

  testWidgets('changing an ingredient amount recalculates nutrition', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1100, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final ai = _FakeFoodAiService();
    await tester.pumpWidget(MaterialApp(home: ManualMealScreen(aiService: ai)));

    await tester.tap(find.text('Add ingredient'));
    await tester.pumpAndSettle();
    await tester.enterText(_field('Ingredient name'), 'Oats');
    await tester.enterText(_field('Amount'), '100');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pump();

    expect(ai.nutritionCalls, 1);
    await tester.tap(find.byTooltip('Edit Oats'));
    await tester.pumpAndSettle();
    await tester.enterText(_field('Amount'), '200');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pump();

    expect(ai.nutritionCalls, 2);
    expect(ai.nutritionInputs.last.single.amount, 200);
    expect(find.text('200 g'), findsOneWidget);
    expect(
      tester.widget<TextField>(_field('Protein')).controller!.text,
      '24.2',
    );
  });

  testWidgets('custom ingredient units are required, saved, and displayed', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1100, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final ai = _FakeFoodAiService();
    await tester.pumpWidget(MaterialApp(home: ManualMealScreen(aiService: ai)));

    await tester.tap(find.text('Add ingredient'));
    await tester.pumpAndSettle();
    await tester.enterText(_field('Ingredient name'), 'Oil');
    await tester.enterText(_field('Amount'), '2');
    await tester.tap(find.text('g').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Others').last);
    await tester.pumpAndSettle();
    expect(_field('Custom unit'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    expect(
      find.text('Enter a custom unit of 1–30 characters.'),
      findsOneWidget,
    );

    await tester.enterText(_field('Custom unit'), ' tbsp ');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pump();

    expect(ai.nutritionInputs.single.single.unit, 'tbsp');
    expect(find.text('2 tbsp'), findsOneWidget);
  });

  testWidgets('AI failures keep manual entry available with a retry', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1100, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final ai = _FakeFoodAiService()..failNextEstimate = true;
    await tester.pumpWidget(MaterialApp(home: ManualMealScreen(aiService: ai)));

    await tester.tap(find.text('Add ingredient'));
    await tester.pumpAndSettle();
    await tester.enterText(_field('Ingredient name'), 'Egg');
    await tester.enterText(_field('Amount'), '2');
    await tester.tap(find.text('g').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('pcs').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pump();

    expect(
      find.textContaining('Nutrition could not be calculated'),
      findsOneWidget,
    );
    await tester.enterText(_field('Calories'), '180');
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Nutrition could not be calculated'),
      findsNothing,
    );
    expect(
      tester.widget<TextField>(_field('Calories')).controller!.text,
      '180',
    );
    expect(find.text('Calories · Edited'), findsOneWidget);
  });

  testWidgets('Scan again reuses the selected photo without reopening camera', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'food_scan_privacy_notice_accepted_gemini': true,
    });
    tester.view.physicalSize = const Size(1100, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final ai = _FakeFoodAiService();
    final sources = <ImageSource>[];
    final imageBytes = Uint8List.fromList(
      image.encodePng(image.Image(width: 1, height: 1)),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: ManualMealScreen(
          aiService: ai,
          photoPicker: (source) async {
            sources.add(source);
            return XFile.fromData(imageBytes, name: 'food.png');
          },
        ),
      ),
    );

    await tester.tap(find.text('Scan your food'));
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
    expect(sources, [ImageSource.camera]);
    expect(ai.scanCalls, 1);

    await tester.tap(find.text('Scan again'));
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
    expect(sources, [ImageSource.camera]);
    expect(ai.scanCalls, 2);
    expect(ai.scannedPhotos, hasLength(2));
    expect(ai.scannedPhotos.last, orderedEquals(imageBytes));
    expect(ai.scannedPhotos.first, orderedEquals(ai.scannedPhotos.last));
  });

  testWidgets('automatically scans a photo recovered after app restart', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'food_scan_privacy_notice_accepted_gemini': true,
    });
    tester.view.physicalSize = const Size(1100, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final ai = _FakeFoodAiService();
    final imageBytes = Uint8List.fromList(
      image.encodePng(image.Image(width: 1, height: 1)),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: ManualMealScreen(
          aiService: ai,
          recoveredPhoto: XFile.fromData(imageBytes, name: 'food.png'),
        ),
      ),
    );

    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();

    expect(ai.scanCalls, 1);
    expect(
      tester.widget<TextField>(_field('Meal name')).controller!.text,
      'Egg and rice',
    );
    expect(find.text('Scanning your food…'), findsNothing);
  });

  testWidgets('shows scan progress and applies the returned food details', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'food_scan_privacy_notice_accepted_gemini': true,
    });
    tester.view.physicalSize = const Size(1100, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final ai = _FakeFoodAiService()..scanGate = Completer<MealScanResult>();
    final imageBytes = Uint8List.fromList(
      image.encodePng(image.Image(width: 1, height: 1)),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: ManualMealScreen(
          aiService: ai,
          photoPicker: (_) async =>
              XFile.fromData(imageBytes, name: 'food.png'),
        ),
      ),
    );

    await tester.tap(find.text('Scan your food'));
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();

    expect(ai.scanCalls, 1);
    expect(find.text('Scanning your food…'), findsWidgets);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    final scanButton = find.widgetWithText(FilledButton, 'Scan your food');
    expect(scanButton, findsOneWidget);
    expect(tester.widget<FilledButton>(scanButton).onPressed, isNull);
    expect(
      find.descendant(
        of: scanButton,
        matching: find.byIcon(Icons.camera_alt_outlined),
      ),
      findsOneWidget,
    );

    ai.scanGate!.complete(
      const MealScanResult(
        isFood: true,
        mealName: 'Egg and rice',
        mealType: 'Lunch',
        ingredients: [
          MealIngredient(name: 'Egg', amount: 2, unit: 'pcs'),
          MealIngredient(name: 'Rice', amount: 150, unit: 'g'),
        ],
        nutrition: NutritionEstimate(
          calories: 400,
          protein: 25,
          carbs: 55,
          fat: 10,
        ),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();

    expect(
      tester.widget<TextField>(_field('Meal name')).controller!.text,
      'Egg and rice',
    );
    expect(find.text('2 pcs'), findsOneWidget);
    expect(find.text('150 g'), findsOneWidget);
    expect(find.text('Scanning your food…'), findsNothing);
    expect(ai.nutritionCalls, 0);
  });

  testWidgets(
    'calculates nutrition immediately when scan has no bundled estimate',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'food_scan_privacy_notice_accepted_gemini': true,
      });
      tester.view.physicalSize = const Size(1100, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final ai = _FakeFoodAiService()..omitBundledNutrition = true;
      final imageBytes = Uint8List.fromList(
        image.encodePng(image.Image(width: 1, height: 1)),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: ManualMealScreen(
            aiService: ai,
            photoPicker: (_) async =>
                XFile.fromData(imageBytes, name: 'food.png'),
          ),
        ),
      );

      await tester.tap(find.text('Scan your food'));
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();

      expect(ai.nutritionCalls, 1);
      expect(
        tester.widget<TextField>(_field('Calories')).controller!.text,
        '350',
      );
      expect(find.text('Calculating nutrition…'), findsNothing);
    },
  );

  testWidgets(
    'keeps recognized meal and offers nutrition retry on enrichment failure',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'food_scan_privacy_notice_accepted_gemini': true,
      });
      tester.view.physicalSize = const Size(1100, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final ai = _FakeFoodAiService()..nutritionUnavailable = true;
      final imageBytes = Uint8List.fromList(
        image.encodePng(image.Image(width: 1, height: 1)),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: ManualMealScreen(
            aiService: ai,
            photoPicker: (_) async =>
                XFile.fromData(imageBytes, name: 'food.png'),
          ),
        ),
      );

      await tester.tap(find.text('Scan your food'));
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();

      expect(
        tester.widget<TextField>(_field('Meal name')).controller!.text,
        'Egg and rice',
      );
      expect(
        find.textContaining('Nutrition could not be calculated right now.'),
        findsOneWidget,
      );
      expect(find.text('Try again'), findsOneWidget);
      expect(ai.nutritionCalls, 0);
    },
  );

  testWidgets('saves photo validation with the meal in local storage', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await store.init(rollDay: false);
    store.d['meals'] = <Map<String, dynamic>>[];
    tester.view.physicalSize = const Size(1100, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(home: ManualMealScreen(aiService: _FakeFoodAiService())),
    );

    await tester.enterText(_field('Meal name'), 'Oatmeal');
    await tester.enterText(_field('Calories'), '250');
    await tester.pump();
    expect(
      tester.widget<TextField>(_field('Meal name')).controller!.text,
      'Oatmeal',
    );
    expect(
      tester.widget<TextField>(_field('Calories')).controller!.text,
      '250',
    );
    final saveButton = find.widgetWithText(FilledButton, 'Add to food log');
    await tester.ensureVisible(saveButton);
    expect(tester.widget<FilledButton>(saveButton).onPressed, isNotNull);
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    final validation = (store.meals.single as Map)['photoValidation'] as Map;
    expect(validation['status'], 'not_scanned');
    expect(validation['acceptedByUser'], false);

    final stored = await store.readStoredAccount('ft');
    expect(stored, isNotNull);
    expect(
      ((stored!['meals'] as List).single as Map)['photoValidation'],
      validation,
    );
  });
}
