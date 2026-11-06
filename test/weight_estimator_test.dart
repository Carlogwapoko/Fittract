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
  test('days without meals stay incomplete and do not change weight', () {
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    final data = accountData(anchorDate: dayKey(yesterday));

    final series = WeightEstimator.calculate(data);

    expect(series.hasAnchor, isTrue);
    expect(series.days.last.complete, isFalse);
    expect(series.days.last.kg, 72);
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
    final expected = 72 + (2000 - bmr) / 7700;

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
