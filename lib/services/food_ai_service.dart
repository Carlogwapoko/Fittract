import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

final class MealIngredient {
  const MealIngredient({
    required this.name,
    required this.amount,
    this.unit = 'g',
    this.source,
  });

  final String name;
  final double amount;
  final String unit;
  final String? source;

  MealIngredient copyWith({
    String? name,
    double? amount,
    String? unit,
    String? source,
  }) => MealIngredient(
    name: name ?? this.name,
    amount: amount ?? this.amount,
    unit: unit ?? this.unit,
    source: source ?? this.source,
  );

  String get promptText => '${name.trim()} · ${_formatAmount(amount)} $unit';

  Map<String, Object> toJson() => {
    'name': name.trim(),
    'amount': amount,
    'unit': unit,
  };
}

final class NutritionEstimate {
  const NutritionEstimate({
    required this.calories,
    required this.protein,
    required this.carbs,
    required this.fat,
    this.hasAiFallback = false,
    this.ingredients = const [],
  });

  final double calories;
  final double protein;
  final double carbs;
  final double fat;
  final bool hasAiFallback;
  final List<MealIngredient> ingredients;
}

final class MealScanResult {
  const MealScanResult({
    required this.isFood,
    required this.mealName,
    required this.mealType,
    required this.ingredients,
    this.nutrition,
  });

  final bool isFood;
  final String mealName;
  final String mealType;
  final List<MealIngredient> ingredients;
  final NutritionEstimate? nutrition;
}

abstract interface class FoodAiService {
  Future<Uint8List> compressPhoto(Uint8List imageBytes);

  Future<MealScanResult> scanMeal(Uint8List jpegBytes);

  Future<NutritionEstimate> estimateNutrition(List<MealIngredient> ingredients);

  Future<bool> photoMatchesIngredients(
    Uint8List jpegBytes,
    List<MealIngredient> ingredients,
  );
}

final class FirebaseFoodAiService implements FoodAiService {
  const FirebaseFoodAiService();

  @override
  Future<Uint8List> compressPhoto(Uint8List imageBytes) async {
    if (imageBytes.isEmpty) {
      throw ArgumentError.value(imageBytes, 'imageBytes', 'Cannot be empty.');
    }
    final decodedImage = img.decodeImage(imageBytes);
    if (decodedImage == null) {
      throw const FormatException(
        'This photo format is not supported. Choose a JPEG or PNG image.',
      );
    }
    final decoded = img.bakeOrientation(decodedImage);
    final longestSide = decoded.width > decoded.height
        ? decoded.width
        : decoded.height;
    final resized = longestSide > 1024
        ? img.copyResize(
            decoded,
            width: decoded.width >= decoded.height
                ? 1024
                : (decoded.width * 1024 / decoded.height).round(),
            height: decoded.height > decoded.width
                ? 1024
                : (decoded.height * 1024 / decoded.width).round(),
            interpolation: img.Interpolation.average,
          )
        : decoded;
    var quality = 80;
    var jpeg = img.encodeJpg(resized, quality: quality);
    while (jpeg.length > 1024 * 1024 && quality > 45) {
      quality -= 5;
      jpeg = img.encodeJpg(resized, quality: quality);
    }
    if (jpeg.length > 1024 * 1024) {
      throw const FormatException(
        'This photo is too large to scan. Choose a smaller image.',
      );
    }
    return Uint8List.fromList(jpeg);
  }

  @override
  Future<MealScanResult> scanMeal(Uint8List jpegBytes) async {
    final data = await _call({
      'action': 'scan',
      'imageBase64': base64Encode(jpegBytes),
      'mimeType': 'image/jpeg',
    });
    final isFood = data['is_food'] == true;
    final ingredients = isFood
        ? _readIngredients(data['ingredients'])
        : const <MealIngredient>[];
    final rawNutrition = data['nutrition'];
    return MealScanResult(
      isFood: isFood,
      mealName: data['meal_name'] is String
          ? (data['meal_name'] as String).trim()
          : '',
      mealType: _mealType(data['meal_type']),
      ingredients: ingredients,
      nutrition: rawNutrition is Map
          ? _readNutrition({
              ...Map<String, dynamic>.from(rawNutrition),
              'ingredients': data['ingredients'],
            })
          : null,
    );
  }

  @override
  Future<NutritionEstimate> estimateNutrition(
    List<MealIngredient> ingredients,
  ) async {
    final data = await _call({
      'action': 'nutrition',
      'ingredients': ingredients
          .map((ingredient) => ingredient.toJson())
          .toList(),
    });
    final nutrition = data['nutrition'];
    if (nutrition is! Map) {
      throw const FormatException('Nutrition service returned invalid data.');
    }
    return _readNutrition(Map<String, dynamic>.from(nutrition));
  }

  @override
  Future<bool> photoMatchesIngredients(
    Uint8List jpegBytes,
    List<MealIngredient> ingredients,
  ) async {
    final data = await _call({
      'action': 'match',
      'imageBase64': base64Encode(jpegBytes),
      'mimeType': 'image/jpeg',
      'ingredients': ingredients
          .map((ingredient) => ingredient.toJson())
          .toList(),
    });
    if (data['matches_photo'] is! bool) {
      throw const FormatException('Photo comparison returned invalid data.');
    }
    return data['matches_photo'] as bool;
  }

  Future<Map<String, dynamic>> _call(Map<String, Object?> data) async {
    try {
      if (FirebaseAuth.instance.currentUser == null) {
        throw FirebaseFunctionsException(
          code: 'unauthenticated',
          message: 'Sign in to scan food. You can still add a meal manually.',
        );
      }
      final callable = FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable(
            'scanMeal',
            options: HttpsCallableOptions(
              timeout: const Duration(seconds: 120),
            ),
          );
      final response = await callable.call(data);
      return Map<String, dynamic>.from(response.data as Map);
    } on FirebaseFunctionsException catch (error) {
      debugPrint(
        'scanMeal callable failed: code=${error.code}, '
        'message=${error.message}, details=${error.details}',
      );
      rethrow;
    }
  }

  List<MealIngredient> _readIngredients(Object? raw) {
    if (raw is! List || raw.length > 30) {
      throw const FormatException(
        'Scan service returned an invalid ingredient list.',
      );
    }
    return [
      for (final item in raw)
        if (item is Map &&
            item['name'] is String &&
            item['amount'] is num &&
            item['unit'] is String)
          MealIngredient(
            name: (item['name'] as String).trim(),
            amount: (item['amount'] as num).toDouble(),
            unit: _unit(item['unit']),
            source: item['source'] is String ? item['source'] as String : null,
          ),
    ];
  }

  NutritionEstimate _readNutrition(Map<String, dynamic> data) {
    double read(String key) {
      final value = data[key];
      if (value is! num || !value.isFinite || value < 0) {
        throw FormatException('Nutrition service returned invalid $key data.');
      }
      return value.toDouble();
    }

    return NutritionEstimate(
      calories: read('calories'),
      protein: read('protein'),
      carbs: read('carbs'),
      fat: read('fat'),
      hasAiFallback: data['has_ai_fallback'] == true,
      ingredients: data['ingredients'] is List
          ? _readIngredients(data['ingredients'])
          : const [],
    );
  }

  String _mealType(Object? value) => switch (value) {
    'Breakfast' || 'Lunch' || 'Snack' || 'Dinner' => value as String,
    _ => 'Lunch',
  };

  String _unit(Object? value) => switch (value) {
    'g' || 'ml' || 'pcs' => value as String,
    _ => 'g',
  };
}

String _formatAmount(double value) => value == value.roundToDouble()
    ? value.toStringAsFixed(0)
    : value.toStringAsFixed(1);
