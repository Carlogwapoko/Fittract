import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:http/http.dart' as http;
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

  Map<String, Object?> toJson() => {
    'name': name.trim(),
    'amount': amount,
    'unit': unit,
    if (source != null) 'source': source,
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
    this.nutritionUnavailable = false,
  });

  final bool isFood;
  final String mealName;
  final String mealType;
  final List<MealIngredient> ingredients;
  final NutritionEstimate? nutrition;
  final bool nutritionUnavailable;
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

final class FoodAiException implements Exception {
  const FoodAiException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => message;
}

final class WorkerFoodAiService implements FoodAiService {
  /// Lets other AI features (for example the weight plan) reuse the same
  /// authenticated, retrying connection to the worker.
  Future<Map<String, dynamic>> callWorker(Map<String, Object?> data) =>
      _call(data);

  const WorkerFoodAiService();

  static final http.Client _client = http.Client();

  static const _workerUrl = String.fromEnvironment(
    'FOOD_API_URL',
    defaultValue:
        'https://fittrack-food-api.carloplaza2023.workers.dev/api/food',
  );

  // Counts photo-match requests so rapid ingredient edits only trigger one
  // Gemini call (the last one).
  static int _matchGeneration = 0;

  @override
  Future<Uint8List> compressPhoto(Uint8List imageBytes) async {
    if (imageBytes.isEmpty) {
      throw ArgumentError.value(imageBytes, 'imageBytes', 'Cannot be empty.');
    }
    // Decoding/resizing/encoding is CPU heavy in pure Dart. Run it off the UI
    // isolate so the app does not freeze while "analyzing".
    final jpeg = await compute(_compressToJpeg, imageBytes);
    if (jpeg == null) {
      throw const FormatException(
        'This photo format is not supported. Choose a JPEG or PNG image.',
      );
    }
    if (jpeg.length > 1024 * 1024) {
      throw const FormatException(
        'This photo is too large to scan. Choose a smaller image.',
      );
    }
    return jpeg;
  }

  @override
  Future<MealScanResult> scanMeal(Uint8List jpegBytes) async {
    final data = await _call({
      'action': 'scan',
      'imageBase64': base64Encode(jpegBytes),
      'mimeType': 'image/jpeg',
    });
    if (data['is_food'] is! bool || data['meal_name'] is! String) {
      throw const FormatException('Food scan returned invalid meal data.');
    }
    final isFood = data['is_food'] as bool;
    final ingredients = isFood
        ? _readIngredients(data['ingredients'])
        : const <MealIngredient>[];
    if (isFood && ingredients.isEmpty) {
      throw const FormatException('No ingredients were recognized. Try again.');
    }
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
      nutritionUnavailable: data['nutrition_unavailable'] == true,
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
    if (nutrition is! Map || data['ingredients'] is! List) {
      throw const FormatException('Nutrition service returned invalid data.');
    }
    return _readNutrition({
      ...Map<String, dynamic>.from(nutrition),
      'ingredients': data['ingredients'],
    });
  }

  @override
  Future<bool> photoMatchesIngredients(
    Uint8List jpegBytes,
    List<MealIngredient> ingredients,
  ) async {
    final generation = ++_matchGeneration;
    await Future<void>.delayed(const Duration(milliseconds: 1800));
    // A newer edit arrived while waiting. Skip this network call; the screen
    // already ignores results of superseded requests.
    if (generation != _matchGeneration) return true;
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

  /// Calls the worker and quietly retries short-lived failures (flaky mobile
  /// connection, worker/Gemini briefly overloaded) before showing an error.
  Future<Map<String, dynamic>> _call(Map<String, Object?> data) async {
    const retryDelays = [Duration(milliseconds: 350)];
    for (var attempt = 0; ; attempt++) {
      try {
        return await _callOnce(data);
      } on FoodAiException catch (error) {
        final transient = const {
          'network',
          'unavailable',
          'resource-exhausted',
        }.contains(error.code);
        if (!transient) rethrow;
        if (attempt >= retryDelays.length) {
          // The server answered (so the connection is fine) but could not
          // finish. Use a different code so the screen shows the real message
          // instead of "Check your connection".
          if (error.code == 'unavailable') {
            throw FoodAiException('service-error', error.message);
          }
          rethrow;
        }
      }
      await Future<void>.delayed(retryDelays[attempt]);
    }
  }

  Future<Map<String, dynamic>> _callOnce(Map<String, Object?> data) async {
    if (_workerUrl.isEmpty) {
      throw const FoodAiException(
        'configuration',
        'Food scanning is not configured in this app build.',
      );
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw const FoodAiException(
        'unauthenticated',
        'Sign in to scan food. You can still add a meal manually.',
      );
    }
    final String? token;
    try {
      token = await user
          .getIdToken()
          .timeout(const Duration(seconds: 10));
    } on FirebaseAuthException catch (error) {
      throw FoodAiException(
        error.code == 'network-request-failed' ? 'network' : 'unauthenticated',
        error.message ?? 'Could not verify your account for food scanning.',
      );
    } on TimeoutException {
      throw const FoodAiException(
        'timeout',
        'Account verification took too long. Please try scanning again.',
      );
    }
    if (token == null || token.isEmpty) {
      throw const FoodAiException(
        'unauthenticated',
        'Sign in again to scan food.',
      );
    }

    final Uri endpoint;
    try {
      endpoint = Uri.parse(_workerUrl);
      if (!endpoint.hasScheme ||
          !endpoint.hasAuthority ||
          endpoint.scheme != 'https') {
        throw const FormatException();
      }
    } on FormatException {
      throw const FoodAiException(
        'configuration',
        'The food service URL is invalid in this app build.',
      );
    }

    try {
      final response = await _client
          .post(
            endpoint,
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode(data),
          )
          .timeout(const Duration(seconds: 30));
      final Object? decoded;
      try {
        decoded = jsonDecode(response.body);
      } on FormatException {
        throw const FoodAiException(
          'data-loss',
          'The food service returned an invalid response.',
        );
      }
      if (decoded is! Map) {
        throw const FoodAiException(
          'data-loss',
          'The food service returned an invalid response.',
        );
      }
      final result = Map<String, dynamic>.from(decoded);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final error = result['error'];
        final code = error is Map && error['code'] is String
            ? error['code'] as String
            : 'unavailable';
        final message = error is Map && error['message'] is String
            ? error['message'] as String
            : 'The food service could not complete the request.';
        throw FoodAiException(code, message);
      }
      return result;
    } on http.ClientException {
      throw const FoodAiException(
        'network',
        'Could not reach the food service. Check your connection and try again.',
      );
    } on TimeoutException {
      throw const FoodAiException(
        'timeout',
        'The food service took too long to respond. Please try again.',
      );
    }
  }

  List<MealIngredient> _readIngredients(Object? raw) {
    if (raw is! List || raw.length > 30) {
      throw const FormatException(
        'Scan service returned an invalid ingredient list.',
      );
    }
    return raw.map((item) {
      if (item is! Map ||
          item['name'] is! String ||
          item['amount'] is! num ||
          item['unit'] is! String) {
        throw const FormatException(
          'Food service returned an invalid ingredient.',
        );
      }
      final name = (item['name'] as String).trim();
      final amount = (item['amount'] as num).toDouble();
      final unit = item['unit'] as String;
      if (name.isEmpty ||
          name.length > 80 ||
          !amount.isFinite ||
          amount <= 0 ||
          amount > 10000 ||
          unit.trim().isEmpty ||
          unit.length > 30 ||
          RegExp(r'[\u0000-\u001F\u007F]').hasMatch(unit)) {
        throw const FormatException(
          'Food service returned an invalid ingredient.',
        );
      }
      return MealIngredient(
        name: name,
        amount: amount,
        unit: unit,
        source: item['source'] is String ? item['source'] as String : null,
      );
    }).toList();
  }

  NutritionEstimate _readNutrition(Map<String, dynamic> data) {
    if (data['has_ai_fallback'] is! bool || data['ingredients'] is! List) {
      throw const FormatException('Nutrition service returned invalid data.');
    }
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
      hasAiFallback: data['has_ai_fallback'] as bool,
      ingredients: _readIngredients(data['ingredients']),
    );
  }

  String _mealType(Object? value) {
    if (value is String &&
        {'Breakfast', 'Lunch', 'Snack', 'Dinner'}.contains(value)) {
      return value;
    }
    throw const FormatException('Food scan returned an invalid meal type.');
  }
}

String _formatAmount(double value) => value == value.roundToDouble()
    ? value.toStringAsFixed(0)
    : value.toStringAsFixed(1);

/// Top-level so it can run in a background isolate via `compute`.
/// Returns null when the bytes are not a decodable image.
Uint8List? _compressToJpeg(Uint8List imageBytes) {
  final decodedImage = img.decodeImage(imageBytes);
  if (decodedImage == null) return null;
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
  return Uint8List.fromList(jpeg);
}
