import 'dart:convert';

import 'package:crypto/crypto.dart';

class WeightEstimateDay {
  final DateTime date;
  final double kg;
  final bool complete;
  final bool anchor;

  const WeightEstimateDay({
    required this.date,
    required this.kg,
    required this.complete,
    this.anchor = false,
  });

  String get dateKey => WeightEstimator._dateKey(date);

  Map<String, Object> toJson() => {
    'd': dateKey,
    'kg': kg,
    'complete': complete,
    'anchor': anchor,
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

    final mealsByDate = <String, List<dynamic>>{};
    final activitiesByDate = <String, List<dynamic>>{};
    final stepsByDate = <String, int>{};
    final workoutsByDate = <String, int>{};
    final archived = data['log'];
    if (archived is List) {
      for (final entry in archived.whereType<Map>()) {
        final date = entry['d'];
        if (date is! String || _parseDate(date) == null) continue;
        mealsByDate[date] = _list(entry['meals']);
        activitiesByDate[date] = _list(entry['act']);
        stepsByDate[date] = _int(entry['steps']);
      }
    }

    final todayKey = _dateKey(today);
    mealsByDate[todayKey] = _list(data['meals']);
    activitiesByDate[todayKey] = _list(data['act']);
    stepsByDate[todayKey] = _int(data['steps']);

    final workouts = data['hist'];
    if (workouts is List) {
      for (final workout in workouts.whereType<Map>()) {
        final date = workout['d'];
        if (date is! String || _parseDate(date) == null) continue;
        workoutsByDate[date] =
            (workoutsByDate[date] ?? 0) + _int(workout['kc']);
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
    final activityFactor = switch (data['activityLevel']) {
      'sedentary' => 1.2,
      'light' => 1.375,
      'moderate' => 1.55,
      'active' => 1.725,
      'very_active' => 1.9,
      _ => 1.375,
    };

    var weight = anchor.$2;
    final days = <WeightEstimateDay>[];
    var date = anchor.$1;
    while (!date.isAfter(today)) {
      final key = _dateKey(date);
      if (key == _dateKey(anchor.$1)) {
        days.add(
          WeightEstimateDay(
            date: date,
            kg: weight,
            complete: true,
            anchor: true,
          ),
        );
      } else {
        final meals = mealsByDate[key] ?? const <dynamic>[];
        final complete = meals.isNotEmpty;
        if (complete) {
          final eaten = meals.fold<double>(
            0,
            (total, meal) => total + (meal is Map ? _number(meal['k']) : 0),
          );
          final bmr = 10 * weight + 6.25 * height - 5 * age + sexAdjustment;
          final baselineBurn = bmr * activityFactor;
          final workoutBurn = (workoutsByDate[key] ?? 0).toDouble();
          final activityBurn = (activitiesByDate[key] ?? const <dynamic>[])
              .fold<double>(
                0,
                (total, activity) =>
                    total + (activity is Map ? _number(activity['kc']) : 0),
              );
          final stepBurn = weight * .0005 * (stepsByDate[key] ?? 0);
          final burned = baselineBurn + workoutBurn + activityBurn + stepBurn;
          weight += (eaten - burned) / kcalPerKg;
          weight = weight.clamp(20, 300);
        }
        days.add(WeightEstimateDay(date: date, kg: weight, complete: complete));
      }
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
    if (anchors.isNotEmpty) return anchors.last;

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
      'today': _dateKey(DateTime.now()),
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

  static List<dynamic> _list(Object? value) =>
      value is List ? value : <dynamic>[];

  static int _int(Object? value) => _number(value).round().clamp(0, 1000000);

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
