import 'package:flutter_test/flutter_test.dart';

import 'package:fittract/services/weight_estimator.dart';

String dayKey(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

Map<String, dynamic> accountData({
  required String anchorDate,
  List<dynamic> meals = const [],
}) => {
  'weights': [
    [anchorDate, 72.0],
  ],
  'goal': {'sw': 72.0},
  'weightAnchorDate': anchorDate,
  'day': dayKey(DateTime.now()),
  'meals': meals,
  'act': <dynamic>[],
  'steps': 0,
  'log': <dynamic>[],
  'hist': <dynamic>[],
  'age': 30,
  'h': 170,
  'sex': 'other',
  'activityLevel': 'sedentary',
};

void main() {
  test('active MET calories exclude resting burn and scale realistically', () {
    expect(
      WeightEstimator.activeCaloriesFromMet(
        weightKg: 72,
        durationSeconds: 1800,
        met: 5,
      ),
      151,
    );
    expect(
      WeightEstimator.activeCaloriesFromMet(
        weightKg: 72,
        durationSeconds: 1800,
        met: 10,
      ),
      340,
    );
    expect(
      WeightEstimator.activeCaloriesFromMet(
        weightKg: 72,
        durationSeconds: 1800,
        met: 1,
      ),
      0,
    );
    expect(
      WeightEstimator.activeCaloriesFromMet(
        weightKg: 0,
        durationSeconds: 1800,
        met: 5,
      ),
      0,
    );
  });

  test(
    'step calorie estimates validate profile values and use step totals',
    () {
      expect(
        WeightEstimator.stepCaloriesFor(
          steps: 10000,
          weightKg: 72,
          heightCm: 170,
        ),
        (10000 * 72 * 170 * 0.000002075).round(),
      );
      expect(
        WeightEstimator.stepCaloriesFor(
          steps: 10000,
          weightKg: 0,
          heightCm: 170,
        ),
        0,
      );
    },
  );

  test('activity MET burn lowers the daily weight estimate', () {
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    final data = accountData(anchorDate: dayKey(yesterday));
    final activityCalories = WeightEstimator.activeCaloriesFromMet(
      weightKg: 72,
      durationSeconds: 1800,
      met: 5,
    );
    data['hist'] = [
      {
        'd': dayKey(DateTime.now()),
        'n': 'Strength',
        'min': 30,
        'kc': activityCalories,
      },
    ];

    final day = WeightEstimator.calculate(data).days.last;

    expect(day.activeCaloriesBurned, activityCalories);
    expect(day.weightChangeKg, closeTo(-activityCalories / 7700, .0001));
  });

  test('daily logged exercise calories work without a weight anchor', () {
    final date = dayKey(DateTime.now());
    final data = <String, dynamic>{
      'day': date,
      'act': [
        {'d': date, 'n': 'Running', 'min': 30, 'kc': 250},
      ],
      'hist': [
        {'d': date, 'n': 'Running', 'min': 30, 'kc': 250},
      ],
    };

    expect(
      WeightEstimator.loggedExerciseCaloriesForDate(data, DateTime.now()),
      250,
    );
  });

  test('days without meals stay incomplete and do not change weight', () {
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    final data = accountData(anchorDate: dayKey(yesterday));

    final series = WeightEstimator.calculate(data);

    expect(series.hasAnchor, isTrue);
    expect(series.days.last.complete, isFalse);
    expect(series.days.last.kg, 72);
  });

  test('a finished routine lowers weight even before meals are logged', () {
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    final data = accountData(anchorDate: dayKey(yesterday));
    data['hist'] = [
      {'d': dayKey(DateTime.now()), 'n': 'Strength', 'min': 45, 'kc': 420},
    ];

    final day = WeightEstimator.calculate(data).days.last;

    expect(day.complete, isFalse);
    expect(day.caloriesConsumed, isNull);
    expect(day.caloriesBurned, 420);
    expect(day.kg, closeTo(72 - 420 / 7700, .0001));
    expect(day.weightChangeKg, closeTo(-420 / 7700, .0001));
  });

  test('routine burns accumulate gradually and appear in weight trends', () {
    final anchor = DateTime.now().subtract(const Duration(days: 3));
    final firstWorkout = anchor.add(const Duration(days: 1));
    final secondWorkout = anchor.add(const Duration(days: 2));
    final data = accountData(anchorDate: dayKey(anchor));
    data['hist'] = [
      {'d': dayKey(firstWorkout), 'n': 'Strength', 'kc': 280},
      {'d': dayKey(secondWorkout), 'n': 'Cardio', 'kc': 420},
    ];

    final series = WeightEstimator.calculate(data);
    final routineDays = series.days
        .where((day) => day.caloriesBurned > 0)
        .toList();

    expect(routineDays, hasLength(2));
    expect(routineDays[1].kg, lessThan(routineDays[0].kg));
    expect(series.currentWeightKg, closeTo(72 - 700 / 7700, .0001));
    expect(WeightEstimator.hasEnoughTrendDays(series.days), isTrue);
  });

  test('steps add estimated calories to daily burn and weight change', () {
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    final data = accountData(anchorDate: dayKey(yesterday));
    data['steps'] = 10000;

    final day = WeightEstimator.calculate(data).days.last;
    final expectedStepCalories = (10000 * 72 * 170 * 0.000002075).round();
    final baselineStepCalories = (3000 * 72 * 170 * 0.000002075).round();
    final additionalCalories = expectedStepCalories - baselineStepCalories;

    expect(day.stepCalories, expectedStepCalories);
    expect(day.activeCaloriesBurned, expectedStepCalories);
    expect(day.weightChangeKg, closeTo(-additionalCalories / 7700, .0001));
    expect(day.contributesToTrend, isTrue);
  });

  test('steps already represented by a logged walk are not counted twice', () {
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    final data = accountData(anchorDate: dayKey(yesterday));
    data['steps'] = 5000;
    data['act'] = [
      {
        'd': dayKey(DateTime.now()),
        'n': 'Brisk walk',
        'min': 30,
        'kc': 300,
        'st': 5000,
      },
    ];

    final day = WeightEstimator.calculate(data).days.last;

    expect(day.stepCalories, 0);
    expect(day.caloriesBurned, 300);
    expect(day.activeCaloriesBurned, 300);
  });

  test('archived daily steps are included in past weight details', () {
    final anchor = DateTime.now().subtract(const Duration(days: 3));
    final stepDate = anchor.add(const Duration(days: 1));
    final data = accountData(anchorDate: dayKey(anchor));
    data['log'] = [
      {
        'd': dayKey(stepDate),
        'steps': 10000,
        'meals': <dynamic>[],
        'act': <dynamic>[],
      },
    ];

    final day = WeightEstimator.calculate(data).days[1];

    expect(day.stepCalories, greaterThan(0));
    expect(day.activeCaloriesBurned, day.stepCalories);
  });

  test('with meals logged the routine burn adds to the resting burn', () {
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    final data = accountData(
      anchorDate: dayKey(yesterday),
      meals: [
        {'d': dayKey(DateTime.now()), 'k': 2000},
      ],
    );
    data['hist'] = [
      {'d': dayKey(DateTime.now()), 'n': 'Strength', 'min': 30, 'kc': 400},
    ];

    final day = WeightEstimator.calculate(data).days.last;
    final bmr = 10 * 72 + 6.25 * 170 - 5 * 30 - 78;
    final maintenance = bmr * 1.2;

    expect(day.restingCalories, bmr.round());
    expect(day.activityCalories, (maintenance - bmr).round());
    expect(
      day.weightChangeKg,
      closeTo((2000 - (maintenance + 400)) / 7700, .0001),
    );
  });

  test('finishing a routine after logging meals lowers the estimate', () {
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    final data = accountData(
      anchorDate: dayKey(yesterday),
      meals: [
        {'d': dayKey(DateTime.now()), 'k': 2000},
      ],
    );

    final before = WeightEstimator.calculate(data).currentWeightKg;
    data['hist'] = [
      {'d': dayKey(DateTime.now()), 'n': 'Cardio', 'min': 40, 'kc': 350},
    ];
    final after = WeightEstimator.calculate(data).currentWeightKg;

    expect(after, lessThan(before));
    expect(before - after, closeTo(350 / 7700, .0001));
  });

  test('exercise on the weigh-in day lowers the weighed value', () {
    final data = accountData(anchorDate: dayKey(DateTime.now()));
    data['hist'] = [
      {'d': dayKey(DateTime.now()), 'n': 'Strength', 'min': 45, 'kc': 400},
    ];

    final day = WeightEstimator.calculate(data).days.last;

    expect(day.anchor, isTrue);
    expect(day.kg, closeTo(72 - 400 / 7700, .0001));
    expect(day.weightChangeKg, closeTo(-400 / 7700, .0001));
  });

  test('logged meal calories move weight using the Mifflin estimate', () {
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    final data = accountData(
      anchorDate: dayKey(yesterday),
      meals: [
        {'d': dayKey(DateTime.now()), 'k': 2000},
      ],
    );

    final series = WeightEstimator.calculate(data);
    final bmr = 10 * 72 + 6.25 * 170 - 5 * 30 - 78;
    final maintenance = bmr * 1.2;
    final expected = 72 + (2000 - maintenance) / 7700;

    expect(series.days.last.complete, isTrue);
    expect(series.currentWeightKg, closeTo(expected, .0001));
  });

  test('daily details report consumed and burned calories', () {
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    final data = accountData(
      anchorDate: dayKey(yesterday),
      meals: [
        {'d': dayKey(DateTime.now()), 'k': 2000},
      ],
    );
    data['act'] = [
      {'d': dayKey(DateTime.now()), 'kc': 250},
    ];
    data['steps'] = 3000;
    data['hist'] = [
      {'d': dayKey(DateTime.now()), 'n': 'Strength', 'min': 30, 'kc': 400},
    ];

    final day = WeightEstimator.calculate(data).days.last;

    expect(day.caloriesConsumed, 2000);
    expect(day.caloriesBurned, 650);
    expect(day.activities, hasLength(1));
    expect(day.workouts, hasLength(1));
    expect(day.hasMeals, isTrue);
    expect(day.calorieBalance, 2000 - day.totalBurnedCalories);
  });

  test('duplicate activity and workout records are not burned twice', () {
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    final data = accountData(anchorDate: dayKey(yesterday));
    data['act'] = [
      {'d': dayKey(DateTime.now()), 'n': 'Strength', 'min': 30, 'kc': 400},
    ];
    data['hist'] = [
      {'d': dayKey(DateTime.now()), 'n': 'Strength', 'min': 30, 'kc': 400},
    ];

    final day = WeightEstimator.calculate(data).days.last;

    expect(day.caloriesBurned, 400);
  });

  test(
    'days without meals show no consumed total and carry weight forward',
    () {
      final yesterday = DateTime.now().subtract(const Duration(days: 1));
      final data = accountData(anchorDate: dayKey(yesterday));

      final day = WeightEstimator.calculate(data).days.last;

      expect(day.caloriesConsumed, isNull);
      expect(day.caloriesBurned, 0);
      expect(day.kg, 72);
      expect(day.hasMeals, isFalse);
    },
  );

  test('manual weigh-ins override the estimate on their date', () {
    final twoDaysAgo = DateTime.now().subtract(const Duration(days: 2));
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    final data = accountData(anchorDate: dayKey(twoDaysAgo));
    data['log'] = [
      {
        'd': dayKey(yesterday),
        'meals': [
          {'k': 1800},
        ],
        'act': <dynamic>[],
      },
    ];
    data['weights'] = [
      [dayKey(twoDaysAgo), 72.0],
      [dayKey(yesterday), 71.5],
    ];

    final days = WeightEstimator.calculate(data).days;

    expect(days[1].kg, 71.5);
    expect(days[1].manuallyWeighed, isTrue);
    expect(days[2].kg, 71.5);
  });

  test('cached estimates are recomputed when meal data changes', () {
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    final data = accountData(
      anchorDate: dayKey(yesterday),
      meals: [
        {'d': dayKey(DateTime.now()), 'k': 2000},
      ],
    );

    final first = WeightEstimator.calculate(data).currentWeightKg;
    data['meals'] = [
      {'d': dayKey(DateTime.now()), 'k': 3000},
    ];
    final updated = WeightEstimator.calculate(data).currentWeightKg;

    expect(updated, greaterThan(first));
  });
}
