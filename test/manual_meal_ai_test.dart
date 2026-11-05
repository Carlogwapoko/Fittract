import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fittract/screens/meal_picker_screen.dart';
import 'package:fittract/services/food_ai_service.dart';

class _FakeFoodAiService implements FoodAiService {
  int nutritionCalls = 0;
  bool failNextEstimate = false;
  final nutritionInputs = <List<MealIngredient>>[];

  @override
  Future<Uint8List> compressPhoto(Uint8List imageBytes) async => imageBytes;

  @override
  Future<MealScanResult> scanMeal(Uint8List jpegBytes) async =>
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
      );

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
    expect(find.text('USDA + GEMINI'), findsOneWidget);
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
}
