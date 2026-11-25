import 'dart:convert';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';

class WeightEstimateDay {
  final DateTime date;
  final double kg;
  final bool complete;
  final bool anchor;
  final bool manuallyWeighed;
  final int? caloriesConsumed;
  final int caloriesBurned;
  final int stepCalories;

  /// Estimated resting (BMR) burn for the day. Not counted as exercise.
  final int restingCalories;
  final int activityCalories;

  int get totalBurnedCalories =>
      restingCalories + activityCalories + stepCalories + caloriesBurned;

  int get activeCaloriesBurned => caloriesBurned + stepCalories;

  int? get calorieBalance =>
      caloriesConsumed == null ? null : caloriesConsumed! - totalBurnedCalories;

  /// How much the estimate moved on this day (kg, negative = lost).
  final double weightChangeKg;
  final List<Map<String, dynamic>> meals;
  final List<Map<String, dynamic>> activities;
  final List<Map<String, dynamic>> workouts;

  const WeightEstimateDay({
    required this.date,
    required this.kg,
    required this.complete,
    this.anchor = false,
    this.manuallyWeighed = false,
    this.caloriesConsumed = 0,
    this.caloriesBurned = 0,
    this.stepCalories = 0,
    this.restingCalories = 0,
    this.activityCalories = 0,
    this.weightChangeKg = 0,
    this.meals = const [],
    this.activities = const [],
    this.workouts = const [],
  });

  bool get hasMeals => meals.isNotEmpty;

  bool get contributesToTrend =>
      complete || manuallyWeighed || activeCaloriesBurned > 0;

  String get dateKey => WeightEstimator._dateKey(date);

  Map<String, Object?> toJson() => {
    'd': dateKey,
    'kg': kg,
    'complete': complete,
    'anchor': anchor,
    'manuallyWeighed': manuallyWeighed,
    'caloriesConsumed': caloriesConsumed,
    'caloriesBurned': caloriesBurned,
    'stepCalories': stepCalories,
    'restingCalories': restingCalories,
    'activityCalories': activityCalories,
    'weightChangeKg': weightChangeKg,
    'meals': meals,
    'activities': activities,
    'workouts': workouts,
  };

  static WeightEstimateDay? fromJson(Object? value) {
    if (value is! Map) return null;
    final date = WeightEstimator._parseDate(value['d']);
    final kg = WeightEstimator._number(value['kg']);
    if (date == null || kg <= 0) return null;
    return WeightEstimateDay(
      date: date,
      kg: kg,
      complete: value['complete'] == true,
      anchor: value['anchor'] == true,
      manuallyWeighed: value['manuallyWeighed'] == true,
      caloriesConsumed: WeightEstimator._optionalInt(value['caloriesConsumed']),
      caloriesBurned: WeightEstimator._int(value['caloriesBurned']),
      stepCalories: WeightEstimator._int(value['stepCalories']),
      restingCalories: WeightEstimator._int(value['restingCalories']),
      activityCalories: WeightEstimator._int(value['activityCalories']),
      weightChangeKg: WeightEstimator._number(value['weightChangeKg']),
      meals: WeightEstimator._records(value['meals']),
      activities: WeightEstimator._records(value['activities']),
      workouts: WeightEstimator._records(value['workouts']),
    );
  }
}

class WeightEstimateSeries {
  final List<WeightEstimateDay> days;
  final bool hasAnchor;
  final double anchorWeightKg;

  const WeightEstimateSeries({
    required this.days,
    required this.hasAnchor,
    required this.anchorWeightKg,
  });

  double get currentWeightKg => days.isEmpty ? 0 : days.last.kg;
}

class WeightEstimator {
  static const kcalPerKg = 7700.0;

  static bool hasEnoughTrendDays(Iterable<WeightEstimateDay> days) =>
      days.where((day) => day.contributesToTrend).length >= 2;

  static int activeCaloriesFromMet({
    required double weightKg,
    required int durationSeconds,
    required double met,
  }) {
    if (!weightKg.isFinite ||
        !met.isFinite ||
        weightKg <= 0 ||
        durationSeconds <= 0 ||
        met <= 1) {
      return 0;
    }
    return ((met - 1) * 3.5 * weightKg * durationSeconds / 12000).round();
  }

  static int stepCaloriesFor({
    required int steps,
    required double weightKg,
    required double heightCm,
  }) {
    if (steps <= 0 ||
        !weightKg.isFinite ||
        weightKg < 20 ||
        weightKg > 300 ||
        !heightCm.isFinite ||
        heightCm < 100 ||
        heightCm > 250) {
      return 0;
    }
    return _stepCalories(steps, weightKg, heightCm);
  }

  static int loggedExerciseCaloriesForDate(
    Map<String, dynamic> data,
    DateTime date,
  ) {
    final key = _dateKey(date);
    final activitiesByDate = <String, List<Map<String, dynamic>>>{};
    final workoutsByDate = <String, List<Map<String, dynamic>>>{};
    final archived = data['log'];
    if (archived is List) {
      for (final entry in archived.whereType<Map>()) {
        final archivedDate = _parseDate(entry['d']);
        if (archivedDate == null || _dateKey(archivedDate) != key) {
          continue;
        }
        _addDatedRecords(activitiesByDate, entry['act'], entry['d']);
      }
    }

    final currentDataDate = _parseDate(data['day']) ?? DateTime.now();
    _addDatedRecords(activitiesByDate, data['act'], currentDataDate);
    _addDatedRecords(workoutsByDate, data['hist'], null);
    return _exerciseCalories(
      activitiesByDate[key] ?? const <Map<String, dynamic>>[],
      workoutsByDate[key] ?? const <Map<String, dynamic>>[],
    );
  }

  static WeightEstimateSeries calculate(Map<String, dynamic> data) {
    final signature = _signature(data);
    final cached = data['weightEstimateCache'];
    if (cached is Map && cached['signature'] == signature) {
      final rawDays = cached['days'];
      final days = rawDays is List
          ? rawDays
                .map(WeightEstimateDay.fromJson)
                .whereType<WeightEstimateDay>()
                .toList()
          : <WeightEstimateDay>[];
      final anchorWeight = _number(cached['anchorWeightKg']);
      return WeightEstimateSeries(
        days: days,
        hasAnchor: cached['hasAnchor'] == true && anchorWeight > 0,
        anchorWeightKg: anchorWeight,
      );
    }

    final result = _build(data);
    data['weightEstimateCache'] = {
      'signature': signature,
      'hasAnchor': result.hasAnchor,
      'anchorWeightKg': result.anchorWeightKg,
      'days': result.days.map((day) => day.toJson()).toList(),
    };
    return result;
  }

  static WeightEstimateSeries _build(Map<String, dynamic> data) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final anchor = _anchor(data, today);
    if (anchor == null) {
      return const WeightEstimateSeries(
        days: [],
        hasAnchor: false,
        anchorWeightKg: 0,
      );
    }

    final mealsByDate = <String, List<Map<String, dynamic>>>{};
    final activitiesByDate = <String, List<Map<String, dynamic>>>{};
    final workoutsByDate = <String, List<Map<String, dynamic>>>{};
    final stepsByDate = <String, int>{};
    final archived = data['log'];
    if (archived is List) {
      for (final entry in archived.whereType<Map>()) {
        _addDatedRecords(mealsByDate, entry['meals'], entry['d']);
        _addDatedRecords(activitiesByDate, entry['act'], entry['d']);
        final date = _parseDate(entry['d']);
        if (date != null) stepsByDate[_dateKey(date)] = _int(entry['steps']);
      }
    }

    final todayKey = _dateKey(today);
    final currentDataDate = _parseDate(data['day']) ?? today;
    _addDatedRecords(mealsByDate, data['meals'], currentDataDate);
    _addDatedRecords(activitiesByDate, data['act'], currentDataDate);
    _addDatedRecords(workoutsByDate, data['hist'], null);
    stepsByDate[_dateKey(currentDataDate)] = _int(data['steps']);
    mealsByDate.putIfAbsent(todayKey, () => []);
    activitiesByDate.putIfAbsent(todayKey, () => []);
    workoutsByDate.putIfAbsent(todayKey, () => []);
    stepsByDate.putIfAbsent(todayKey, () => 0);

    final manualWeightsByDate = <String, double>{};
    final rawWeights = data['weights'];
    if (rawWeights is List) {
      for (final entry in rawWeights.whereType<List>()) {
        if (entry.length < 2) continue;
        final date = _parseDate(entry[0]);
        final kg = _number(entry[1]);
        if (date != null && kg >= 20 && kg <= 300) {
          manualWeightsByDate[_dateKey(date)] = kg;
        }
      }
    }

    final age = _number(data['age'], fallback: 30).clamp(13, 100);
    final height = _number(data['h'], fallback: 170).clamp(100, 250);
    final sex = data['sex'];
    final sexAdjustment = switch (sex) {
      'male' => 5.0,
      'female' => -161.0,
      _ => -78.0,
    };
    var weight = anchor.$2;
    final days = <WeightEstimateDay>[];
    var date = anchor.$1;
    while (!date.isAfter(today)) {
      final key = _dateKey(date);
      final isAnchor = key == _dateKey(anchor.$1);
      final meals = mealsByDate[key] ?? const <Map<String, dynamic>>[];
      final activities =
          activitiesByDate[key] ?? const <Map<String, dynamic>>[];
      final workouts = workoutsByDate[key] ?? const <Map<String, dynamic>>[];
      final hasMeals = meals.isNotEmpty;
      final complete = isAnchor || hasMeals;
      final eaten = meals.fold<int>(
        0,
        (total, meal) => total + _int(meal['k']),
      );
      final weightBefore = weight;
      final bmr = 10 * weight + 6.25 * height - 5 * age + sexAdjustment;
      final burned = _exerciseCalories(activities, workouts);
      final activityLevel = data['activityLevel'];
      final activityFactor = switch (activityLevel) {
        'sedentary' => 1.2,
        'light' => 1.375,
        'moderate' => 1.55,
        'active' => 1.725,
        'very_active' => 1.9,
        _ => 1.375,
      };
      final resting = bmr.round();
      final stepCount = stepsByDate[key] ?? 0;
      final loggedActivitySteps = activities.fold<int>(
        0,
        (total, activity) => total + _int(activity['st']),
      );
      final unpairedSteps = math.max(0, stepCount - loggedActivitySteps);
      final stepCalories = _stepCalories(unpairedSteps, weight, height);
      final baselineSteps = switch (activityLevel) {
        'sedentary' => 3000,
        'light' => 5000,
        'moderate' => 7500,
        'active' => 10000,
        'very_active' => 12000,
        _ => 5000,
      };
      final baselineStepCalories = _stepCalories(
        math.min(baselineSteps, unpairedSteps),
        weight,
        height,
      );
      final activityCalories = math.max(
        0,
        (bmr * activityFactor - bmr - baselineStepCalories).round(),
      );
      final dailyMaintenance = resting + activityCalories;
      final extraStepCalories = math.max(
        0,
        stepCalories - baselineStepCalories,
      );
      final manualWeight = manualWeightsByDate[key];
      if (isAnchor || manualWeight != null) {
        // Weigh-in day: the weighed value is the starting point. Exercise
        // logged on the same day still counts (it is assumed to happen after
        // the weigh-in), so finishing a routine lowers the estimate right away.
        weight =
            (manualWeight ?? weight) - (burned + extraStepCalories) / kcalPerKg;
        weight = weight.clamp(20, 300);
      } else if (hasMeals) {
        // Logged meals: calories eaten minus BMR, normal activity, and exercise.
        weight +=
            (eaten - (dailyMaintenance + burned + stepCalories)) / kcalPerKg;
        weight = weight.clamp(20, 300);
      } else if (burned > 0 || extraStepCalories > 0) {
        // No meals logged yet, but there was exercise (for example a finished
        // routine). Assume normal eating (intake equal to resting burn) so the
        // exercise burn still lowers the estimate. Logging meals replaces this
        // assumption with the real numbers.
        weight -= (burned + extraStepCalories) / kcalPerKg;
        weight = weight.clamp(20, 300);
      }
      days.add(
        WeightEstimateDay(
          date: date,
          kg: weight,
          complete: complete,
          anchor: isAnchor,
          manuallyWeighed: manualWeight != null,
          caloriesConsumed: hasMeals ? eaten : null,
          caloriesBurned: burned,
          stepCalories: stepCalories,
          restingCalories: resting,
          activityCalories: activityCalories,
          weightChangeKg: weight - weightBefore,
          meals: meals,
          activities: activities,
          workouts: workouts,
        ),
      );
      date = DateTime(date.year, date.month, date.day + 1);
    }

    return WeightEstimateSeries(
      days: days,
      hasAnchor: true,
      anchorWeightKg: anchor.$2,
    );
  }

  static int _exerciseCalories(
    List<Map<String, dynamic>> activities,
    List<Map<String, dynamic>> workouts,
  ) {
    var total = 0;
    final duplicateKeys = <String>{};

    for (final activity in activities) {
      final kcal = _int(activity['kc']);
      final minutes = _int(activity['min']);
      final name = activity['n']?.toString().trim().toLowerCase() ?? '';
      final exactKey = '$name|$minutes|$kcal';
      final overlapKey = '$minutes|$kcal';
      final matchingWorkout = workouts.any((workout) {
        final workoutName = workout['n']?.toString().trim().toLowerCase() ?? '';
        final workoutMinutes = _int(workout['min']);
        final workoutKcal = _int(workout['kc']);
        final workoutExactKey = '$workoutName|$workoutMinutes|$workoutKcal';
        return exactKey == workoutExactKey ||
            overlapKey == '$workoutMinutes|$workoutKcal';
      });
      if (!matchingWorkout) {
        total += kcal;
      } else {
        duplicateKeys.add(overlapKey);
      }
    }

    for (final workout in workouts) {
      final kcal = _int(workout['kc']);
      final minutes = _int(workout['min']);
      final overlapKey = '$minutes|$kcal';
      if (!duplicateKeys.contains(overlapKey)) {
        total += kcal;
      } else {
        duplicateKeys.remove(overlapKey);
        total += kcal;
      }
    }
    return total;
  }

  static int _stepCalories(int steps, num weightKg, num heightCm) =>
      (steps * weightKg * heightCm * 0.000002075).round();

  static (DateTime, double)? _anchor(
    Map<String, dynamic> data,
    DateTime today,
  ) {
    final weights = data['weights'];
    final anchors = <(DateTime, double)>[];
    if (weights is List) {
      for (final entry in weights.whereType<List>()) {
        if (entry.length < 2) continue;
        final date = _parseDate(entry[0]);
        final kg = _number(entry[1]);
        if (date != null && !date.isAfter(today) && kg >= 20 && kg <= 300) {
          anchors.add((date, kg));
        }
      }
    }
    anchors.sort((a, b) => a.$1.compareTo(b.$1));
    if (anchors.isNotEmpty) return anchors.first;

    final goal = data['goal'];
    final startingWeight = goal is Map ? _number(goal['sw']) : 0.0;
    if (startingWeight < 20 || startingWeight > 300) return null;
    final requestedDate = _parseDate(data['weightAnchorDate']);
    final date = requestedDate == null || requestedDate.isAfter(today)
        ? today
        : requestedDate;
    return (date, startingWeight);
  }

  static String _signature(Map<String, dynamic> data) {
    final goal = data['goal'];
    final source = {
      'estimateVersion': 7,
      'today': _dateKey(DateTime.now()),
      'dataDay': data['day'],
      'weights': data['weights'],
      'goalStart': goal is Map ? goal['sw'] : null,
      'anchorDate': data['weightAnchorDate'],
      'meals': data['meals'],
      'act': data['act'],
      'steps': data['steps'],
      'log': data['log'],
      'hist': data['hist'],
      'age': data['age'],
      'height': data['h'],
      'sex': data['sex'],
      'activityLevel': data['activityLevel'],
    };
    return sha256.convert(utf8.encode(jsonEncode(source))).toString();
  }

  static List<Map<String, dynamic>> _records(Object? value) => value is List
      ? value.whereType<Map>().map(_stringMap).toList()
      : <Map<String, dynamic>>[];

  static Map<String, dynamic> _stringMap(Map value) => {
    for (final entry in value.entries) '${entry.key}': entry.value,
  };

  static void _addDatedRecords(
    Map<String, List<Map<String, dynamic>>> destination,
    Object? rawRecords,
    Object? fallbackDate,
  ) {
    if (rawRecords is! List) return;
    final fallback = _parseDate(fallbackDate);
    for (final record in rawRecords.whereType<Map>()) {
      final date = _parseDate(record['d']) ?? fallback;
      if (date == null) continue;
      destination.putIfAbsent(_dateKey(date), () => []).add(_stringMap(record));
    }
  }

  static int _int(Object? value) => _number(value).round().clamp(0, 1000000);

  static int? _optionalInt(Object? value) => value == null ? null : _int(value);

  static double _number(Object? value, {double fallback = 0}) {
    final parsed = value is num ? value.toDouble() : double.tryParse('$value');
    return parsed != null && parsed.isFinite ? parsed : fallback;
  }

  static DateTime? _parseDate(Object? value) {
    if (value is DateTime) {
      return DateTime(value.year, value.month, value.day);
    }
    if (value is! String) return null;
    final parsed = DateTime.tryParse(value);
    return parsed == null
        ? null
        : DateTime(parsed.year, parsed.month, parsed.day);
  }

  static String _dateKey(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}
