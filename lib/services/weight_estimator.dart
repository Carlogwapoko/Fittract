import 'dart:convert';

import 'package:crypto/crypto.dart';

class WeightEstimateDay {
  final DateTime date;
  final double kg;
  final bool complete;
  final bool anchor;
  final bool manuallyWeighed;
  final int? caloriesConsumed;
  final int caloriesBurned;
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
    this.meals = const [],
    this.activities = const [],
    this.workouts = const [],
  });

  bool get hasMeals => meals.isNotEmpty;

  String get dateKey => WeightEstimator._dateKey(date);

  Map<String, Object?> toJson() => {
    'd': dateKey,
    'kg': kg,
    'complete': complete,
    'anchor': anchor,
    'manuallyWeighed': manuallyWeighed,
    'caloriesConsumed': caloriesConsumed,
    'caloriesBurned': caloriesBurned,
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
    final archived = data['log'];
    if (archived is List) {
      for (final entry in archived.whereType<Map>()) {
        _addDatedRecords(mealsByDate, entry['meals'], entry['d']);
        _addDatedRecords(activitiesByDate, entry['act'], entry['d']);
      }
    }

    final todayKey = _dateKey(today);
    final currentDataDate = _parseDate(data['day']) ?? today;
    _addDatedRecords(mealsByDate, data['meals'], currentDataDate);
    _addDatedRecords(activitiesByDate, data['act'], currentDataDate);
    _addDatedRecords(workoutsByDate, data['hist'], null);
    mealsByDate.putIfAbsent(todayKey, () => []);
    activitiesByDate.putIfAbsent(todayKey, () => []);
    workoutsByDate.putIfAbsent(todayKey, () => []);

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
      final bmr = 10 * weight + 6.25 * height - 5 * age + sexAdjustment;
      final burned = [
        ...activities,
        ...workouts,
      ].fold<int>(0, (total, exercise) => total + _int(exercise['kc']));
      if (!isAnchor && hasMeals) {
        weight += (eaten - (bmr + burned)) / kcalPerKg;
        weight = weight.clamp(20, 300);
      }
      final manualWeight = manualWeightsByDate[key];
      if (manualWeight != null) weight = manualWeight;
      days.add(
        WeightEstimateDay(
          date: date,
          kg: weight,
          complete: complete,
          anchor: isAnchor,
          manuallyWeighed: manualWeight != null,
          caloriesConsumed: hasMeals ? eaten : null,
          caloriesBurned: burned,
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
      'estimateVersion': 3,
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
