import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/food_ai_service.dart';
import '../services/picked_photo_cleanup.dart';
import '../store/store.dart';
import '../widgets/shared_widgets.dart';

class _MealOption {
  final String name;
  final String type;
  final String description;
  final int calories;
  final int protein;
  final int carbs;
  final int fat;
  final IconData icon;

  const _MealOption(
    this.name,
    this.type,
    this.description,
    this.calories,
    this.protein,
    this.carbs,
    this.fat,
    this.icon,
  );

  Map<String, dynamic> toMeal() => {
    't': type,
    'n': name,
    'desc': description,
    'img': mealImageAssetFor(name),
    'k': calories,
    'p': protein,
    'c': carbs,
    'f': fat,
  };
}

const _mealOptions = [
  _MealOption(
    'Oatmeal with berries',
    'Breakfast',
    'Rolled oats with milk, blueberries, and a spoonful of honey.',
    320,
    12,
    54,
    7,
    Icons.breakfast_dining_outlined,
  ),
  _MealOption(
    'Egg and avocado toast',
    'Breakfast',
    'Two eggs and sliced avocado served over whole-grain toast.',
    390,
    20,
    35,
    20,
    Icons.egg_alt_outlined,
  ),
  _MealOption(
    'Greek yogurt parfait',
    'Breakfast',
    'Greek yogurt layered with granola, strawberries, and chia seeds.',
    280,
    18,
    38,
    7,
    Icons.icecream_outlined,
  ),
  _MealOption(
    'Chicken rice bowl',
    'Lunch',
    'Grilled chicken breast with brown rice, broccoli, and lemon.',
    520,
    42,
    58,
    12,
    Icons.rice_bowl_outlined,
  ),
  _MealOption(
    'Salmon and roasted vegetables',
    'Lunch',
    'Baked salmon with roasted seasonal vegetables and quinoa.',
    610,
    38,
    46,
    29,
    Icons.set_meal_outlined,
  ),
  _MealOption(
    'Turkey avocado wrap',
    'Lunch',
    'Whole-wheat wrap filled with turkey, avocado, lettuce, and tomato.',
    450,
    32,
    42,
    17,
    Icons.lunch_dining_outlined,
  ),
  _MealOption(
    'Apple with peanut butter',
    'Snack',
    'A crisp apple with one tablespoon of natural peanut butter.',
    190,
    5,
    26,
    9,
    Icons.energy_savings_leaf_outlined,
  ),
  _MealOption(
    'Cottage cheese and fruit',
    'Snack',
    'Cottage cheese served with pineapple and a handful of walnuts.',
    230,
    20,
    22,
    8,
    Icons.local_cafe_outlined,
  ),
  _MealOption(
    'Banana protein smoothie',
    'Snack',
    'Blended banana, milk, and protein powder with a little cinnamon.',
    260,
    24,
    34,
    5,
    Icons.blender_outlined,
  ),
  _MealOption(
    'Beef and vegetable stir-fry',
    'Dinner',
    'Lean beef with mixed vegetables and rice in a light soy-ginger sauce.',
    570,
    39,
    61,
    18,
    Icons.dinner_dining_outlined,
  ),
  _MealOption(
    'Lentil curry',
    'Dinner',
    'Red lentils simmered with tomato, spinach, and mild curry spices.',
    490,
    24,
    72,
    11,
    Icons.soup_kitchen_outlined,
  ),
  _MealOption(
    'Tofu quinoa bowl',
    'Dinner',
    'Crispy tofu and quinoa with edamame, greens, and sesame dressing.',
    530,
    27,
    56,
    21,
    Icons.ramen_dining_outlined,
  ),
  _MealOption(
    'Shomai With Rice',
    'Lunch',
    'Shomai with rice and vegetables in a light sauce.',
    250,
    4,
    30,
    1,
    Icons.rice_bowl_outlined,
  ),
];

const _mealTypes = ['All', 'Breakfast', 'Lunch', 'Snack', 'Dinner'];

String mealImageAssetFor(String name) => switch (name) {
  'Oatmeal with berries' => 'assets/images/Oatmeal_with_berries.jpg',
  'Egg and avocado toast' => 'assets/images/egg_and_avocado_toast.jpg',
  'Greek yogurt parfait' => 'assets/images/Greek-Yogurt-Parfait.jpg',
  'Chicken rice bowl' => 'assets/images/chicken_rice_bowl.jpg',
  'Salmon and roasted vegetables' =>
    'assets/images/salmon_and_roasted_vegetables.jpg',
  'Turkey avocado wrap' => 'assets/images/turkey avocado wrap.jpg',
  'Apple with peanut butter' => 'assets/images/apple with peanut butter.jpg',
  'Cottage cheese and fruit' => 'assets/images/Cottage-cheese-and-fruit.jpg',
  'Banana protein smoothie' => 'assets/images/banana protein smoothie.jpg',
  'Beef and vegetable stir-fry' =>
    'assets/images/beef and vegetable stir fry.jpg',
  'Lentil curry' => 'assets/images/lentil curry.jpg',
  'Tofu quinoa bowl' => 'assets/images/tofu quinoa bowl.jpg',
  'Shomai With Rice' => 'assets/images/siomai with rice.jpg',
  _ => '',
};

/// Category icon shown when a meal does not have a usable picture.
/// Preset names keep their specific fallback; unknown/manual meals use their
/// category, and missing types safely use the dinner default.
IconData mealIconFor(Object? name, Object? type) {
  final n = (name ?? '').toString().trim().toLowerCase();
  for (final option in _mealOptions) {
    if (option.name.toLowerCase() == n) return option.icon;
  }
  return switch ((type ?? '').toString().trim().toLowerCase()) {
    'breakfast' => Icons.free_breakfast_outlined,
    'lunch' => Icons.lunch_dining_outlined,
    'snack' => Icons.cookie_outlined,
    _ => Icons.dinner_dining_outlined,
  };
}

Widget mealPicture(
  BuildContext context, {
  required Object? image,
  required Object? name,
  required Object? type,
  required double size,
}) {
  final path = (image ?? '').toString();
  final fallback = Container(
    width: size,
    height: size,
    alignment: Alignment.center,
    color: tintOf(context),
    child: Icon(mealIconFor(name, type), color: primaryOf(context)),
  );
  if (path.isEmpty) {
    return ClipRRect(borderRadius: BorderRadius.circular(14), child: fallback);
  }

  final imageWidget = path.startsWith('assets/')
      ? Image.asset(
          path,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => fallback,
        )
      : Image.network(
          path,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => fallback,
        );
  return ClipRRect(
    borderRadius: BorderRadius.circular(14),
    child: SizedBox(width: size, height: size, child: imageWidget),
  );
}

class MealPickerScreen extends StatefulWidget {
  const MealPickerScreen({super.key});

  @override
  State<MealPickerScreen> createState() => _MealPickerScreenState();
}

class _MealPickerScreenState extends State<MealPickerScreen> {
  final _search = TextEditingController();
  String _type = 'All';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => live((c) {
    final query = _search.text.trim().toLowerCase();
    final options = _mealOptions.where((meal) {
      final matchesType = _type == 'All' || meal.type == _type;
      final matchesSearch =
          query.isEmpty ||
          meal.name.toLowerCase().contains(query) ||
          meal.description.toLowerCase().contains(query);
      return matchesType && matchesSearch;
    }).toList();

    return screen([
      hdr(c, 'Add food', 'Choose a meal or add your own.', back: true),
      card(
        color: tintOf(c),
        child: Row(
          children: [
            Icon(Icons.restaurant_menu, color: primaryOf(c), size: 30),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Pick something you ate',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
            ),
            Text('${store.kcal()} kcal today', style: muted),
          ],
        ),
      ),
      TextField(
        controller: _search,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          hintText: 'Search meals or ingredients',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: _search.text.isEmpty
              ? null
              : IconButton(
                  tooltip: 'Clear search',
                  onPressed: () {
                    _search.clear();
                    setState(() {});
                  },
                  icon: const Icon(Icons.close),
                ),
        ),
      ),
      const SizedBox(height: 12),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final type in _mealTypes)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(type),
                  selected: _type == type,
                  onSelected: (_) => setState(() => _type = type),
                  selectedColor: tintOf(c),
                  labelStyle: TextStyle(
                    color: _type == type ? primaryOf(c) : null,
                    fontWeight: _type == type ? FontWeight.w700 : null,
                  ),
                  side: BorderSide(
                    color: _type == type
                        ? primaryOf(c)
                        : Theme.of(c).colorScheme.outlineVariant,
                  ),
                ),
              ),
          ],
        ),
      ),
      h3(
        'Ready-made meals',
        trailing: Text('${options.length} options', style: muted),
      ),
      if (options.isEmpty)
        card(
          child: const Text(
            'No meals match that search. Try another name or add your meal manually.',
            textAlign: TextAlign.center,
            style: muted,
          ),
        )
      else
        for (final meal in options) _optionCard(c, meal),
      card(
        color: tintOf(c),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Not on the list?',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            const Text(
              'Enter the meal name and nutrition details yourself.',
              style: muted,
            ),
            const SizedBox(height: 12),
            btn('＋  Add food manually', () => go(c, const ManualMealScreen())),
          ],
        ),
      ),
    ]);
  });

  Widget _optionCard(BuildContext context, _MealOption meal) => card(
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        mealPicture(
          context,
          image: mealImageAssetFor(meal.name),
          name: meal.name,
          type: meal.type,
          size: 44,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      meal.name,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  Text(
                    '${meal.calories} kcal',
                    style: TextStyle(
                      color: primaryOf(context),
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(meal.description, style: muted),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 5,
                children: [
                  tag(meal.type),
                  _macroChip(context, 'P', meal.protein),
                  _macroChip(context, 'C', meal.carbs),
                  _macroChip(context, 'F', meal.fat),
                ],
              ),
              const SizedBox(height: kGapMd),
              SizedBox(
                height: 38,
                child: FilledButton.tonalIcon(
                  onPressed: () => _addMeal(context, meal),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add to today'),
                  style: FilledButton.styleFrom(
                    foregroundColor: primaryOf(context),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _macroChip(BuildContext context, String label, int value) => Container(
    padding: const EdgeInsets.symmetric(horizontal: kGapSm, vertical: kGapXs),
    decoration: BoxDecoration(
      color: tintOf(context),
      borderRadius: BorderRadius.circular(99),
    ),
    child: Text('$label $value g', style: muted),
  );

  void _addMeal(BuildContext context, _MealOption meal) {
    store.meals.add(meal.toMeal());
    store.save();
    snack(context, '${meal.name} added to today.');
  }
}

class ManualMealScreen extends StatefulWidget {
  const ManualMealScreen({super.key, this.aiService});

  final FoodAiService? aiService;

  @override
  State<ManualMealScreen> createState() => _ManualMealScreenState();
}

class _ManualMealScreenState extends State<ManualMealScreen> {
  final _name = TextEditingController();
  final _description = TextEditingController();
  final _calories = TextEditingController();
  final _protein = TextEditingController();
  final _carbs = TextEditingController();
  final _fat = TextEditingController();
  final _imagePicker = ImagePicker();
  final _ingredients = <MealIngredient>[];
  List<MealIngredient> _photoDetectedIngredients = [];
  final _editedNutrition = <String>{};
  String _type = 'Breakfast';
  Uint8List? _foodImageBytes;
  String? _foodImageName;
  bool _saving = false;
  bool _scanning = false;
  bool _calculatingNutrition = false;
  bool _checkingPhotoMatch = false;
  bool _photoWasAnalyzed = false;
  bool _showPhotoMismatch = false;
  bool _keepPhotoMismatch = false;
  bool _retryPhotoMatch = false;
  bool _hasAiNutritionFallback = false;
  String? _nutritionError;
  String? _scanError;
  String? _photoError;
  Timer? _nutritionDebounce;
  int _nutritionRequest = 0;
  int _photoAnalysisRequest = 0;
  int _photoMatchRequest = 0;

  FoodAiService get _aiService =>
      widget.aiService ?? const FirebaseFoodAiService();

  @override
  void dispose() {
    _nutritionDebounce?.cancel();
    _foodImageBytes = null;
    _photoDetectedIngredients = [];
    _name.dispose();
    _description.dispose();
    _calories.dispose();
    _protein.dispose();
    _carbs.dispose();
    _fat.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final photoControls = Row(
      children: [
        Expanded(
          child: SizedBox(
            height: 52,
            child: FilledButton.icon(
              onPressed: _scanning || _saving
                  ? null
                  : () => _scanFood(ImageSource.camera),
              icon: const Icon(Icons.camera_alt_outlined),
              label: Text(_scanning ? 'Scanning your food…' : 'Scan your food'),
              style: FilledButton.styleFrom(
                backgroundColor: primaryOf(context),
                foregroundColor: theme.colorScheme.onPrimary,
                textStyle: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: kGapSm),
        Expanded(
          child: SizedBox(
            height: 52,
            child: OutlinedButton.icon(
              onPressed: _saving || _scanning
                  ? null
                  : () => _scanFood(ImageSource.gallery),
              icon: const Icon(Icons.photo_library_outlined),
              label: const Text('Choose from gallery'),
              style: OutlinedButton.styleFrom(
                foregroundColor: primaryOf(context),
                side: BorderSide(color: theme.colorScheme.outlineVariant),
              ),
            ),
          ),
        ),
      ],
    );

    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 140),
              children: [
                hdr(
                  context,
                  'Add your meal details',
                  'Build your meal and nutrition estimate.',
                  back: true,
                ),
                card(
                  color: tintOf(context),
                  child: const Row(
                    children: [
                      Icon(Icons.edit_note_outlined, color: kPri, size: 28),
                      SizedBox(width: kGapMd),
                      Expanded(
                        child: Text(
                          'Enter what you ate. Ingredients and nutrition can be filled in automatically.',
                          style: TextStyle(fontWeight: FontWeight.w500),
                        ),
                      ),
                    ],
                  ),
                ),
                photoControls,
                if (_foodImageBytes != null) ...[
                  const SizedBox(height: kGapSm),
                  Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: SizedBox(
                          width: 76,
                          height: 76,
                          child: Image.memory(
                            _foodImageBytes!,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                      const SizedBox(width: kGapMd),
                      Expanded(
                        child: Text(
                          _scanning
                              ? 'Scanning your food…'
                              : (_foodImageName ?? 'Meal photo'),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      TextButton(
                        onPressed: _scanning || _saving
                            ? null
                            : () => _scanFood(ImageSource.camera),
                        child: const Text('Scan again'),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: kGapSm),
                Text(
                  'A compressed photo is sent securely for ingredient analysis.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                if (_scanError != null)
                  _aiErrorCard(
                    message: _scanError!,
                    onRetry: _scanning ? null : _retryScan,
                    buttonLabel: 'Try again',
                  ),
                h3('Meal details'),
                Text(
                  'Meal type',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: kGapXs),
                Wrap(
                  spacing: kGapSm,
                  runSpacing: kGapSm,
                  children: [
                    for (final type in _mealTypes.skip(1))
                      ChoiceChip(
                        label: Text(type),
                        selected: _type == type,
                        onSelected: (selected) {
                          if (selected) setState(() => _type = type);
                        },
                        materialTapTargetSize: MaterialTapTargetSize.padded,
                        visualDensity: VisualDensity.standard,
                        labelStyle: TextStyle(
                          color: _type == type ? primaryOf(context) : null,
                          fontWeight: _type == type
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                        side: BorderSide(
                          color: _type == type
                              ? primaryOf(context)
                              : theme.colorScheme.outlineVariant,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: kGapMd),
                TextField(
                  controller: _name,
                  textCapitalization: TextCapitalization.sentences,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Meal name',
                    hintText: 'e.g. Homemade vegetable pasta',
                    floatingLabelBehavior: FloatingLabelBehavior.auto,
                  ),
                ),
                const SizedBox(height: kGapMd),
                TextField(
                  controller: _description,
                  textCapitalization: TextCapitalization.sentences,
                  minLines: 2,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Description (optional)',
                    hintText: 'Ingredients or serving details',
                    alignLabelWithHint: true,
                    floatingLabelBehavior: FloatingLabelBehavior.auto,
                  ),
                ),
                h3('Ingredients'),
                card(
                  color: tintOf(context),
                  child: const Text(
                    'Add what went into your meal and how much you ate.',
                    style: muted,
                  ),
                ),
                if (_ingredients.isEmpty)
                  card(
                    child: const Text(
                      'No ingredients yet. Scan your food or add them manually.',
                      style: muted,
                    ),
                  ),
                for (var index = 0; index < _ingredients.length; index++)
                  _ingredientTile(_ingredients[index], index: index),
                OutlinedButton.icon(
                  onPressed: _saving || _scanning
                      ? null
                      : () => _editIngredient(),
                  icon: const Icon(Icons.add),
                  label: const Text('Add ingredient'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                    foregroundColor: primaryOf(context),
                  ),
                ),
                if (_checkingPhotoMatch)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: kGapSm),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        SizedBox(width: kGapSm),
                        Text(
                          'Checking ingredients against your photo…',
                          style: muted,
                        ),
                      ],
                    ),
                  ),
                if (_photoError != null)
                  _aiErrorCard(
                    message: _photoError!,
                    onRetry: _checkingPhotoMatch
                        ? null
                        : (_retryPhotoMatch ? _checkPhotoMatch : _retryScan),
                    buttonLabel: 'Try again',
                  ),
                if (_showPhotoMismatch) _photoMismatchCard(),
                h3(
                  'Nutrition',
                  trailing: Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 4,
                    children: [
                      TextButton.icon(
                        onPressed: _ingredients.isEmpty || _calculatingNutrition
                            ? null
                            : () => _calculateNutrition(force: true),
                        icon: const Icon(Icons.refresh, size: 18),
                        label: const Text('Recalculate with AI'),
                      ),
                      Text(
                        'AI ESTIMATE',
                        style: TextStyle(
                          color: primaryOf(context),
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  'Values are estimates based on your ingredients and amounts.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                if (_ingredients.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: kGapSm),
                    child: Text('Add ingredients to calculate', style: muted),
                  ),
                if (_hasAiNutritionFallback)
                  const Padding(
                    padding: EdgeInsets.only(top: kGapXs),
                    child: Text(
                      'Some ingredient values are AI estimates because USDA data was unavailable.',
                      style: muted,
                    ),
                  ),
                if (_calculatingNutrition)
                  const Padding(
                    padding: EdgeInsets.only(top: kGapSm),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        SizedBox(width: kGapSm),
                        Text('Calculating with AI…', style: muted),
                      ],
                    ),
                  ),
                if (_nutritionError != null)
                  _aiErrorCard(
                    message: _nutritionError!,
                    onRetry: _calculatingNutrition ? null : _calculateNutrition,
                    buttonLabel: 'Try again',
                  ),
                const SizedBox(height: kGapSm),
                TextField(
                  controller: _calories,
                  onChanged: (_) => _markNutritionEdited('calories'),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: _fieldLabel('Calories', 'calories'),
                    suffixText: 'kcal',
                  ),
                ),
                const SizedBox(height: kGapMd),
                Row(
                  children: [
                    Expanded(
                      child: _macroInput(_protein, 'Protein', 'protein'),
                    ),
                    const SizedBox(width: kGapSm),
                    Expanded(child: _macroInput(_carbs, 'Carbs', 'carbs')),
                    const SizedBox(width: kGapSm),
                    Expanded(child: _macroInput(_fat, 'Fat', 'fat')),
                  ],
                ),
              ],
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                padding: const EdgeInsets.fromLTRB(20, 28, 20, 12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      theme.scaffoldBackgroundColor.withValues(alpha: 0),
                      theme.scaffoldBackgroundColor.withValues(alpha: .94),
                      theme.scaffoldBackgroundColor,
                    ],
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!(_canSave && !_saving && !_scanning))
                      const Padding(
                        padding: EdgeInsets.only(bottom: kGapSm),
                        child: Text(
                          'Add a meal name and calories.',
                          style: muted,
                        ),
                      ),
                    SizedBox(
                      height: 52,
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _canSave && !_saving && !_scanning
                            ? _save
                            : null,
                        child: Text(_saving ? 'Saving…' : 'Add to food log'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool get _canSave {
    final calories = _parseAmount(_calories.text);
    return _name.text.trim().isNotEmpty &&
        calories != null &&
        calories > 0 &&
        calories <= 10000;
  }

  Widget _macroInput(
    TextEditingController controller,
    String label,
    String key,
  ) => TextField(
    controller: controller,
    onChanged: (_) => _markNutritionEdited(key),
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    decoration: InputDecoration(
      labelText: _fieldLabel(label, key),
      suffixText: 'g',
      floatingLabelBehavior: FloatingLabelBehavior.auto,
    ),
  );

  String _fieldLabel(String label, String key) =>
      _editedNutrition.contains(key) ? '$label · Edited' : label;

  void _markNutritionEdited(String key) {
    setState(() => _editedNutrition.add(key));
  }

  Widget _ingredientTile(
    MealIngredient ingredient, {
    required int index,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: kGapSm),
    child: Material(
      color: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => _editIngredient(index: index),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: kGapMd),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          ingredient.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      const SizedBox(width: kGapSm),
                      Text(
                        '${_formatAmount(ingredient.amount)} ${ingredient.unit}',
                        style: muted,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (ingredient.source == 'AI estimate')
            const Padding(
              padding: EdgeInsets.only(right: kGapXs),
              child: Text('AI estimate', style: muted),
            ),
          IconButton(
            tooltip: 'Edit ${ingredient.name}',
            constraints: const BoxConstraints.tightFor(width: 44, height: 48),
            onPressed: () => _editIngredient(index: index),
            icon: const Icon(Icons.edit_outlined),
          ),
          SizedBox(
            width: 44,
            height: 48,
            child: IconButton(
              tooltip: 'Remove ${ingredient.name}',
              constraints: const BoxConstraints.tightFor(width: 44, height: 44),
              onPressed: () => _removeIngredient(index),
              icon: const Icon(Icons.close),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _photoMismatchCard() {
    final scheme = Theme.of(context).colorScheme;
    return card(
      color: scheme.secondaryContainer,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline, color: scheme.onSecondaryContainer),
              const SizedBox(width: kGapSm),
              const Expanded(
                child: Text(
                  "Your ingredients don't seem to match the photo. Review them?",
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: kGapSm),
          Wrap(
            spacing: kGapSm,
            children: [
              TextButton(
                onPressed: _reviewPhotoMismatch,
                child: const Text('Review'),
              ),
              TextButton(
                onPressed: () => setState(() {
                  _showPhotoMismatch = false;
                  _keepPhotoMismatch = true;
                }),
                child: const Text('Keep as is'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _aiErrorCard({
    required String message,
    required VoidCallback? onRetry,
    required String buttonLabel,
  }) => card(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(message, style: muted),
        const SizedBox(height: kGapSm),
        OutlinedButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh),
          label: Text(buttonLabel),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
          ),
        ),
      ],
    ),
  );

  Future<void> _editIngredient({int? index}) async {
    final current = index == null ? null : _ingredients[index];
    final result = await showDialog<MealIngredient>(
      context: context,
      builder: (_) => _IngredientEditorDialog(ingredient: current),
    );
    if (!mounted || result == null) return;
    setState(() {
      if (index == null) {
        _ingredients.add(result);
      } else {
        _ingredients[index] = result;
      }
    });
    _ingredientsChanged();
  }

  void _removeIngredient(int index) {
    setState(() {
      _ingredients.removeAt(index);
    });
    _ingredientsChanged();
  }

  bool _sameIngredients(List<MealIngredient> left, List<MealIngredient> right) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      final a = left[index];
      final b = right[index];
      if (a.name.toLowerCase() != b.name.toLowerCase() ||
          a.amount != b.amount ||
          a.unit != b.unit) {
        return false;
      }
    }
    return true;
  }

  void _ingredientsChanged({bool recalculateNutrition = true}) {
    _photoMatchRequest++;
    _keepPhotoMismatch = false;
    setState(() {
      _checkingPhotoMatch = false;
      _showPhotoMismatch = false;
    });
    if (recalculateNutrition) _scheduleNutrition();
    if (!_sameIngredients(_ingredients, _photoDetectedIngredients)) {
      if (_photoWasAnalyzed && _ingredients.isEmpty) {
        setState(() => _showPhotoMismatch = true);
      } else {
        _checkPhotoMatch();
      }
    }
  }

  void _scheduleNutrition() {
    _nutritionDebounce?.cancel();
    _nutritionRequest++;
    if (_ingredients.isEmpty) {
      setState(() {
        _calculatingNutrition = false;
        _nutritionError = null;
        _hasAiNutritionFallback = false;
        if (!_editedNutrition.contains('calories')) _calories.clear();
        if (!_editedNutrition.contains('protein')) _protein.clear();
        if (!_editedNutrition.contains('carbs')) _carbs.clear();
        if (!_editedNutrition.contains('fat')) _fat.clear();
      });
      return;
    }
    setState(() {
      _calculatingNutrition = true;
      _nutritionError = null;
      if (!_editedNutrition.contains('calories')) _calories.clear();
      if (!_editedNutrition.contains('protein')) _protein.clear();
      if (!_editedNutrition.contains('carbs')) _carbs.clear();
      if (!_editedNutrition.contains('fat')) _fat.clear();
    });
    _nutritionDebounce = Timer(
      const Duration(milliseconds: 700),
      () => _calculateNutrition(),
    );
  }

  Future<void> _calculateNutrition({bool force = false}) async {
    if (_ingredients.isEmpty) {
      if (force) {
        setState(() {
          _nutritionError = 'Add a confirmed ingredient before calculating.';
          _calculatingNutrition = false;
        });
      }
      return;
    }
    final request = ++_nutritionRequest;
    final ingredients = List<MealIngredient>.unmodifiable(_ingredients);
    setState(() {
      _calculatingNutrition = true;
      _nutritionError = null;
    });
    try {
      final estimate = await _aiService.estimateNutrition(ingredients);
      if (!mounted || request != _nutritionRequest) return;
      _applyEstimate(estimate, force: force);
      setState(() {
        _calculatingNutrition = false;
        if (estimate.ingredients.length == _ingredients.length) {
          for (var index = 0; index < _ingredients.length; index++) {
            _ingredients[index] = _ingredients[index].copyWith(
              source: estimate.ingredients[index].source,
            );
          }
        }
      });
    } on FirebaseFunctionsException catch (error) {
      _setNutritionFailure(request, _friendlyFunctionError(error));
    } on FirebaseException {
      _setNutritionFailure(request);
    } on FormatException {
      _setNutritionFailure(request);
    } on TimeoutException {
      _setNutritionFailure(request);
    } on StateError {
      _setNutritionFailure(request);
    }
  }

  void _applyEstimate(NutritionEstimate estimate, {bool force = false}) {
    setState(() {
      if (force || !_editedNutrition.contains('calories')) {
        _calories.text = _formatAmount(estimate.calories);
      }
      if (force || !_editedNutrition.contains('protein')) {
        _protein.text = _formatAmount(estimate.protein);
      }
      if (force || !_editedNutrition.contains('carbs')) {
        _carbs.text = _formatAmount(estimate.carbs);
      }
      if (force || !_editedNutrition.contains('fat')) {
        _fat.text = _formatAmount(estimate.fat);
      }
      if (force) _editedNutrition.clear();
      _nutritionError = null;
      _hasAiNutritionFallback = estimate.hasAiFallback;
    });
  }

  void _setNutritionFailure(int request, [String? message]) {
    if (!mounted || request != _nutritionRequest) return;
    setState(() {
      _calculatingNutrition = false;
      _nutritionError = message ?? 'Nutrition could not be calculated right now. Enter values manually or try again.';
    });
  }

  Future<void> _checkPhotoMatch() async {
    final bytes = _foodImageBytes;
    if (bytes == null ||
        !_photoWasAnalyzed ||
        _ingredients.isEmpty ||
        _sameIngredients(_ingredients, _photoDetectedIngredients) ||
        _keepPhotoMismatch) {
      return;
    }
    final request = ++_photoMatchRequest;
    final ingredients = List<MealIngredient>.unmodifiable(_ingredients);
    setState(() {
      _checkingPhotoMatch = true;
      _photoError = null;
      _retryPhotoMatch = true;
    });
    try {
      final matches = await _aiService.photoMatchesIngredients(
        bytes,
        ingredients,
      );
      if (!mounted || request != _photoMatchRequest) return;
      setState(() {
        _checkingPhotoMatch = false;
        _showPhotoMismatch = !matches;
        _keepPhotoMismatch = false;
      });
    } on FirebaseFunctionsException {
      _setPhotoMatchFailure(request);
    } on FirebaseException {
      _setPhotoMatchFailure(request);
    } on FormatException {
      _setPhotoMatchFailure(request);
    } on TimeoutException {
      _setPhotoMatchFailure(request);
    }
  }

  void _setPhotoMatchFailure(int request) {
    if (!mounted || request != _photoMatchRequest) return;
    setState(() {
      _checkingPhotoMatch = false;
      _photoError = 'Could not compare the ingredients with the photo. You can keep your list or try again.';
    });
  }

  Future<void> _reviewPhotoMismatch() async {
    setState(() {
      _ingredients
        ..clear()
        ..addAll(_photoDetectedIngredients);
      _showPhotoMismatch = false;
      _keepPhotoMismatch = false;
    });
    _ingredientsChanged();
  }

  Future<bool> _confirmScanPrivacy() async {
    final preferences = await SharedPreferences.getInstance();
    if (preferences.getBool('food_scan_privacy_notice_accepted') == true) {
      return true;
    }
    if (!mounted) return false;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('A note about food scanning'),
        content: const Text(
          'Your compressed meal photo and ingredient text are sent securely '
          'to Groq for food recognition and, when needed, nutrition estimates. '
          'Ingredient names are also sent to USDA FoodData Central. Groq says '
          'inference data is not retained by default, but may be temporarily '
          'logged for reliability or abuse monitoring. The scan service does '
          'not store your photo.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Not now'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    if (accepted == true) {
      await preferences.setBool('food_scan_privacy_notice_accepted', true);
      return true;
    }
    return false;
  }

  Future<void> _scanFood(ImageSource source) async {
    if (_scanning || _saving) return;
    setState(() => _scanning = true);
    try {
      if (!await _confirmScanPrivacy() || !mounted) return;
      final picked = await _imagePicker.pickImage(
        source: source,
        imageQuality: 80,
        maxWidth: 1024,
        maxHeight: 1024,
      );
      if (picked == null) return;
      final request = ++_photoAnalysisRequest;
      setState(() {
        _foodImageBytes = null;
        _foodImageName = picked.name;
        _scanError = null;
        _photoError = null;
        _nutritionError = null;
        _checkingPhotoMatch = false;
        _photoWasAnalyzed = false;
        _showPhotoMismatch = false;
        _keepPhotoMismatch = false;
        _photoDetectedIngredients = [];
        _photoMatchRequest++;
      });
      final compressed = await _compressPickedPhoto(picked);
      if (!mounted || request != _photoAnalysisRequest) return;
      setState(() {
        _foodImageBytes = compressed;
        _foodImageName = 'meal-scan.jpg';
      });
      await _runMealScan(compressed, request);
    } on PlatformException catch (error) {
      if (!mounted) return;
      if (source == ImageSource.camera &&
          (error.code.toLowerCase().contains('denied') ||
              error.code.toLowerCase().contains('camera_access'))) {
        await _showCameraPermissionDialog();
      } else {
        setState(() => _scanning = false);
        snack(
          context,
          'Could not open the photo source: ${error.message ?? error.code}.',
        );
      }
    } on FormatException catch (error) {
      if (mounted) {
        setState(() {
          _scanning = false;
          _scanError = error.message;
        });
      }
    } on Exception catch (error) {
      if (mounted) {
        setState(() {
          _scanning = false;
          _scanError = 'Could not read that photo. Try another image or enter ingredients manually.';
        });
        debugPrint('Meal photo read failed: $error');
      }
    } finally {
      if (mounted && _scanning) setState(() => _scanning = false);
    }
  }

  Future<Uint8List> _compressPickedPhoto(XFile picked) async {
    try {
      final imageBytes = await picked.readAsBytes();
      return await _aiService.compressPhoto(imageBytes);
    } finally {
      try {
        await deletePickedPhoto(picked.path);
      } on Exception catch (error) {
        debugPrint('Could not delete the temporary meal photo: $error');
      }
    }
  }

  Future<void> _showCameraPermissionDialog() async {
    setState(() => _scanning = false);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Camera access needed'),
        content: const Text(
          'Camera access is needed to scan your meal. You can allow access in '
          'device settings, or choose a photo from your gallery instead.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              _scanFood(ImageSource.gallery);
            },
            child: const Text('Choose from gallery'),
          ),
        ],
      ),
    );
  }

  Future<void> _retryScan() async {
    final bytes = _foodImageBytes;
    if (bytes == null) {
      await _scanFood(ImageSource.gallery);
      return;
    }
    final request = ++_photoAnalysisRequest;
    setState(() {
      _scanning = true;
      _scanError = null;
      _photoError = null;
    });
    try {
      final compressed = await _aiService.compressPhoto(bytes);
      if (!mounted || request != _photoAnalysisRequest) return;
      setState(() {
        _foodImageBytes = compressed;
        _foodImageName = 'meal-scan.jpg';
      });
      await _runMealScan(compressed, request);
    } on FormatException catch (error) {
      _setScanFailure(request, error.message);
    } on Exception {
      _setScanFailure(request);
    }
  }

  Future<void> _runMealScan(Uint8List jpegBytes, int request) async {
    try {
      final result = await _aiService.scanMeal(jpegBytes);
      if (!mounted || request != _photoAnalysisRequest) return;
      if (!result.isFood || result.ingredients.isEmpty) {
        setState(() {
          _scanning = false;
          _photoWasAnalyzed = false;
          _photoDetectedIngredients = [];
          _scanError = "We couldn't recognise this food. Try again or add ingredients manually.";
        });
        return;
      }
      setState(() {
        _name.text = result.mealName;
        _type = result.mealType;
        _ingredients
          ..clear()
          ..addAll(result.ingredients);
        _photoDetectedIngredients = List.of(result.ingredients);
        _photoWasAnalyzed = true;
        _scanning = false;
        _scanError = null;
      });
      _ingredientsChanged();
    } on FirebaseFunctionsException catch (error) {
      _setScanFailure(request, _friendlyFunctionError(error));
    } on FirebaseException {
      _setScanFailure(request);
    } on TimeoutException {
      _setScanFailure(request);
    } on FormatException catch (error) {
      _setScanFailure(request, error.message);
    } on StateError {
      _setScanFailure(request);
    }
  }

  void _setScanFailure(int request, [String? message]) {
    if (!mounted || request != _photoAnalysisRequest) return;
    setState(() {
      _scanning = false;
      _scanError = message ?? 'We could not scan this photo right now. Try again or add ingredients manually.';
    });
  }

  String _friendlyFunctionError(FirebaseFunctionsException error) =>
      switch (error.code) {
        'resource-exhausted' =>
          'The food service is busy right now. Please try again in a moment.',
        'unavailable' || 'deadline-exceeded' => 'Could not reach the food service. Check your connection or enter ingredients and nutrition manually.',
        'not-found' =>
          'Food scanning is not available on the server yet. You can still add ingredients and nutrition manually.',
        'unauthenticated' => 'Sign in to scan food. You can still add ingredients and nutrition manually.',
        _ => error.message ?? 'Food scanning is unavailable. Try again or add ingredients manually.',
      };

  String _formatAmount(double value) => value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(1);

  Future<void> _save() async {
    if (_saving) return;
    final name = _name.text.trim();
    final calories = _parseAmount(_calories.text);
    final protein = _parseAmount(_protein.text);
    final carbs = _parseAmount(_carbs.text);
    final fat = _parseAmount(_fat.text);
    if (name.isEmpty) {
      snack(context, 'Enter a name for your meal.');
      return;
    }
    if (calories == null || calories <= 0 || calories > 10000) {
      snack(
        context,
        'Enter valid calories greater than 0 and no more than 10000.',
      );
      return;
    }
    if (protein == null ||
        carbs == null ||
        fat == null ||
        [protein, carbs, fat].any((value) => value < 0 || value > 1000)) {
      snack(context, 'Enter valid macro amounts from 0 to 1000 g.');
      return;
    }

    setState(() => _saving = true);

    store.meals.add({
      't': _type,
      'n': name,
      'desc': _description.text.trim(),
      'ingredients': [
        for (final ingredient in _ingredients) ingredient.toJson(),
      ],
      'k': calories.round(),
      'p': protein.round(),
      'c': carbs.round(),
      'f': fat.round(),
    });
    store.save();
    final cloudSaved = store.isCloudLinked ? await store.syncNow() : null;
    if (!mounted) return;
    setState(() => _saving = false);
    if (cloudSaved == false) {
      snack(
        context,
        '$name saved on this device, but cloud sync failed. Retry from Profile.',
      );
    } else {
      snack(context, '$name added to today.');
    }
    Navigator.pop(context);
  }

  double? _parseAmount(String value) {
    final text = value.trim();
    return text.isEmpty ? 0 : double.tryParse(text);
  }
}

class _IngredientEditorDialog extends StatefulWidget {
  const _IngredientEditorDialog({required this.ingredient});

  final MealIngredient? ingredient;

  @override
  State<_IngredientEditorDialog> createState() =>
      _IngredientEditorDialogState();
}

class _IngredientEditorDialogState extends State<_IngredientEditorDialog> {
  late final TextEditingController _name;
  late final TextEditingController _amount;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.ingredient?.name ?? '');
    _amount = TextEditingController(
      text: widget.ingredient?.amount.toString() ?? '',
    );
    _unit = widget.ingredient?.unit ?? 'g';
  }

  late String _unit;

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.ingredient == null ? 'Add ingredient' : 'Edit ingredient',
    ),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: _name,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Ingredient name',
            hintText: 'e.g. Egg',
          ),
        ),
        const SizedBox(height: kGapMd),
        TextField(
          controller: _amount,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Amount',
            hintText: 'e.g. 150',
          ),
        ),
        const SizedBox(height: kGapMd),
        DropdownButtonFormField<String>(
          initialValue: _unit,
          decoration: const InputDecoration(labelText: 'Unit'),
          items: const [
            DropdownMenuItem(value: 'g', child: Text('g')),
            DropdownMenuItem(value: 'ml', child: Text('ml')),
            DropdownMenuItem(value: 'pcs', child: Text('pcs')),
          ],
          onChanged: (value) {
            if (value != null) setState(() => _unit = value);
          },
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          final name = _name.text.trim();
          final amount = double.tryParse(_amount.text.trim());
          if (name.isEmpty || amount == null || amount <= 0) return;
          Navigator.pop(
            context,
            MealIngredient(name: name, amount: amount, unit: _unit),
          );
        },
        child: const Text('Save'),
      ),
    ],
  );
}
