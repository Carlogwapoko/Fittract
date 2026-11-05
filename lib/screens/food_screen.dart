import 'package:flutter/material.dart';

import '../store/store.dart';
import '../widgets/shared_widgets.dart';
import 'meal_picker_screen.dart';

class FoodScreen extends StatelessWidget {
  const FoodScreen({super.key});

  Future<void> _editNutritionGoals(BuildContext context) async {
    final updated = await showModalBottomSheet<Map<String, int>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _NutritionGoalsSheet(goals: store.nutritionGoals),
    );
    if (updated == null || !context.mounted) return;
    store.d['nutritionGoals'] = updated;
    store.save();
  }

  @override
  Widget build(BuildContext context) => live((c) {
    final calories = store.kcal();
    final goals = store.nutritionGoals;
    final calorieGoal = (goals['calories'] as num).toInt();
    final remaining = (calorieGoal - calories).clamp(0, calorieGoal);
    final meals = store.meals;

    return screen([
      hdr(c, 'Food & meals', 'Fuel your day.', back: true),
      card(
        color: tintOf(c),
        child: Row(
          children: [
            SizedBox(
              width: 112,
              height: 112,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox.expand(
                    child: CircularProgressIndicator(
                      value: progressOf(calories / calorieGoal),
                      strokeWidth: 10,
                      strokeCap: StrokeCap.round,
                      color: primaryOf(c),
                      backgroundColor: Theme.of(c).colorScheme.outlineVariant
                          .withValues(alpha: .55),
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '$calories',
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const Text('kcal eaten', style: muted),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: kGapLg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$remaining',
                    style: TextStyle(
                      color: primaryOf(c),
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const Text('kcal remaining', style: muted),
                  const SizedBox(height: 4),
                  Text('Daily goal · $calorieGoal kcal', style: muted),
                ],
              ),
            ),
          ],
        ),
      ),
      h3(
        'Daily nutrients',
        trailing: TextButton.icon(
          onPressed: () => _editNutritionGoals(c),
          icon: const Icon(Icons.tune, size: 17),
          label: const Text('Edit goals'),
        ),
      ),
      card(
        child: Column(
          children: [
            _nutrientRow(
              c,
              'Protein',
              store.macro('p'),
              (goals['protein'] as num).toInt(),
              Icons.egg_alt_outlined,
            ),
            const SizedBox(height: kGapMd),
            _nutrientRow(
              c,
              'Carbs',
              store.macro('c'),
              (goals['carbs'] as num).toInt(),
              Icons.grain,
            ),
            const SizedBox(height: kGapMd),
            _nutrientRow(
              c,
              'Fat',
              store.macro('f'),
              (goals['fat'] as num).toInt(),
              Icons.water_drop_outlined,
            ),
          ],
        ),
      ),
      h3(
        "Today's meals",
        trailing: Text('${meals.length} logged', style: muted),
      ),
      if (meals.isEmpty)
        card(
          child: Column(
            children: [
              Icon(
                Icons.restaurant_menu_outlined,
                size: 36,
                color: primaryOf(c),
              ),
              const SizedBox(height: 8),
              const Text(
                'Nothing logged yet',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              const Text(
                'Add a meal to see your daily nutrition here.',
                textAlign: TextAlign.center,
                style: muted,
              ),
            ],
          ),
        )
      else
        for (int i = 0; i < meals.length; i++) _mealCard(c, meals[i], i),
      btn('+  Log food', () => go(c, const MealPickerScreen())),
    ]);
  });

  Widget _nutrientRow(
    BuildContext context,
    String name,
    int amount,
    int goal,
    IconData icon,
  ) => Row(
    children: [
      Icon(icon, size: 19, color: primaryOf(context)),
      const SizedBox(width: kGapMd),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
                Text('$amount / $goal g', style: muted),
              ],
            ),
            bar(amount / goal),
          ],
        ),
      ),
    ],
  );

  Widget _mealCard(BuildContext context, Map meal, int index) {
    final description = meal['desc'] as String? ?? '';
    final rawIngredients = meal['ingredients'];
    final ingredients = rawIngredients is List
        ? rawIngredients
              .whereType<Map>()
              .map((ingredient) {
                final name = ingredient['name']?.toString().trim() ?? '';
                final amount = ingredient['amount'];
                final unit = ingredient['unit']?.toString() ?? 'g';
                if (name.isEmpty || amount is! num) return null;
                final formattedAmount = amount == amount.roundToDouble()
                    ? amount.toStringAsFixed(0)
                    : amount.toStringAsFixed(1);
                return '$name $formattedAmount $unit';
              })
              .whereType<String>()
              .toList()
        : const <String>[];
    return card(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          mealPicture(
            context,
            image:
                meal['img'] ?? mealImageAssetFor((meal['n'] ?? '').toString()),
            name: meal['n'],
            type: meal['t'],
            size: 42,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  meal['n'] as String? ?? 'Meal',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  '${meal['t']} · ${meal['k']} kcal',
                  style: TextStyle(
                    color: primaryOf(context),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (description.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(description, style: muted),
                ],
                if (ingredients.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Ingredients: ${ingredients.join(', ')}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: muted,
                  ),
                ],
                if (meal['hasAiNutritionFallback'] == true) ...[
                  const SizedBox(height: 4),
                  const Text('Includes estimated nutrition', style: muted),
                ],
                const SizedBox(height: kGapSm),
                Wrap(
                  spacing: 6,
                  children: [
                    _macroTag(context, 'P', meal['p']),
                    _macroTag(context, 'C', meal['c']),
                    _macroTag(context, 'F', meal['f']),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Remove meal',
            onPressed: () {
              store.meals.removeAt(index);
              store.save();
            },
            icon: const Icon(Icons.close, color: kMut),
          ),
        ],
      ),
    );
  }

  Widget _macroTag(BuildContext context, String label, dynamic value) =>
      Container(
        padding: const EdgeInsets.symmetric(
          horizontal: kGapSm,
          vertical: kGapXs,
        ),
        decoration: BoxDecoration(
          color: tintOf(context),
          borderRadius: BorderRadius.circular(99),
        ),
        child: Text('$label ${value ?? 0}g', style: muted),
      );
}

class _NutritionGoalsSheet extends StatefulWidget {
  final Map<String, dynamic> goals;

  const _NutritionGoalsSheet({required this.goals});

  @override
  State<_NutritionGoalsSheet> createState() => _NutritionGoalsSheetState();
}

class _NutritionGoalsSheetState extends State<_NutritionGoalsSheet> {
  late final _calories = TextEditingController(
    text: '${widget.goals['calories']}',
  );
  late final _protein = TextEditingController(
    text: '${widget.goals['protein']}',
  );
  late final _carbs = TextEditingController(text: '${widget.goals['carbs']}');
  late final _fat = TextEditingController(text: '${widget.goals['fat']}');

  @override
  void dispose() {
    _calories.dispose();
    _protein.dispose();
    _carbs.dispose();
    _fat.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        4,
        20,
        MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Daily nutrition goals',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            const Text(
              'Personalize your daily calorie and nutrient targets.',
              style: muted,
            ),
            const SizedBox(height: kGapLg),
            _goalInput(
              _calories,
              'Calories',
              'kcal',
              Icons.local_fire_department_outlined,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _goalInput(
                    _protein,
                    'Protein',
                    'g',
                    Icons.egg_alt_outlined,
                  ),
                ),
                const SizedBox(width: kGapMd),
                Expanded(child: _goalInput(_carbs, 'Carbs', 'g', Icons.grain)),
              ],
            ),
            const SizedBox(height: 12),
            _goalInput(_fat, 'Fat', 'g', Icons.water_drop_outlined),
            const SizedBox(height: kGapLg),
            btn('Save nutrition goals', _save),
          ],
        ),
      ),
    ),
  );

  Widget _goalInput(
    TextEditingController controller,
    String label,
    String unit,
    IconData icon,
  ) => TextField(
    controller: controller,
    keyboardType: TextInputType.number,
    decoration: InputDecoration(
      labelText: label,
      suffixText: unit,
      prefixIcon: Icon(icon),
    ),
  );

  void _save() {
    final values = {
      'calories': int.tryParse(_calories.text.trim()),
      'protein': int.tryParse(_protein.text.trim()),
      'carbs': int.tryParse(_carbs.text.trim()),
      'fat': int.tryParse(_fat.text.trim()),
    };
    final valid = values.entries.every((entry) {
      final value = entry.value;
      if (value == null) return false;
      return entry.key == 'calories'
          ? value >= 500 && value <= 10000
          : value >= 1 && value <= 1000;
    });
    if (!valid) {
      snack(
        context,
        'Enter calories from 500–10000 and nutrient goals from 1–1000 g.',
      );
      return;
    }
    Navigator.pop(context, values.cast<String, int>());
  }
}
