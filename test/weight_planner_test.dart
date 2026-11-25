import 'package:flutter_test/flutter_test.dart';

import 'package:fittract/services/weight_plan_ai_service.dart';
import 'package:fittract/services/weight_planner.dart';

void main() {
  final today = DateTime(2026, 11, 14);

  WeightPlan buildPlan({
    required double targetKg,
    DateTime? targetDate,
    double currentKg = 70,
    double heightCm = 170,
  }) => WeightPlanner.build(
    WeightPlanInput(
      currentKg: currentKg,
      targetKg: targetKg,
      ageYears: 30,
      heightCm: heightCm,
      sex: 'other',
      activityLevel: 'moderate',
      workoutsPerWeek: 3,
      targetDate: targetDate,
      today: today,
    ),
  );

  test(
    'normal loss goal follows the requested date with descending milestones',
    () {
      final targetDate = today.add(const Duration(days: 84));
      final plan = buildPlan(targetKg: 65, targetDate: targetDate);

      expect(plan.requestedWeeklyChangeKg, closeTo(5 / 12, 0.0001));
      expect(plan.weeklyChangeKg, closeTo(-5 / 12, 0.0001));
      expect(plan.projectedDate, targetDate);
      expect(plan.milestones.map((milestone) => milestone.kg), [
        68.75,
        67.5,
        66.25,
        65,
      ]);
    },
  );

  test(
    'eleven-week loss goal has no unsafe-date warning and stays a deficit',
    () {
      final plan = buildPlan(
        targetKg: 65,
        targetDate: today.add(const Duration(days: 77)),
      );

      expect(
        plan.warnings.any((warning) => warning.contains('This date needs')),
        isFalse,
      );
      expect(plan.dailyCalories, lessThan(plan.maintenanceCalories));
    },
  );

  test('too-fast goal has one warning and exposes its earliest safe date', () {
    final plan = buildPlan(
      targetKg: 65,
      targetDate: today.add(const Duration(days: 7)),
    );

    expect(plan.requestedWeeklyChangeKg, 5);
    expect(plan.weeklyChangeKg, -0.45);
    expect(plan.projectedDate, today.add(const Duration(days: 78)));
    expect(plan.warnings, [
      'This date needs 5.00 kg/week, which is too fast. The earliest safe date '
          'is ${WeightPlanner.formatDate(plan.projectedDate!)}.',
    ]);
    expect(
      WeightPlanner.unsafeTargetDateMessage(
        requestedWeeklyChangeKg: plan.requestedWeeklyChangeKg,
        safeWeeklyChangeKg: WeightPlanner.safeWeeklyRate(plan.goalType),
        projectedDate: plan.projectedDate,
      ),
      plan.warnings.single,
    );
  });

  test('past target date uses a safe default pace and warns', () {
    final plan = buildPlan(
      targetKg: 65,
      targetDate: today.subtract(const Duration(days: 1)),
    );

    expect(plan.requestedWeeklyChangeKg, isNull);
    expect(plan.weeklyChangeKg, -0.45);
    expect(plan.projectedDate, today.add(const Duration(days: 78)));
    expect(
      plan.warnings.any(
        (warning) => warning.contains('has passed or is today'),
      ),
      isTrue,
    );
  });

  test('today target date warns without creating a requested pace', () {
    final plan = buildPlan(targetKg: 65, targetDate: today);

    expect(plan.requestedWeeklyChangeKg, isNull);
    expect(plan.weeklyChangeKg, -0.45);
    expect(plan.warnings.single, contains('has passed or is today'));
  });

  test('empty date uses the safe default and maintain goals have no pace', () {
    final noDate = buildPlan(targetKg: 65);
    final atTarget = buildPlan(targetKg: 70);
    final withinMaintainRange = buildPlan(targetKg: 70.4);

    expect(noDate.requestedWeeklyChangeKg, isNull);
    expect(noDate.warnings, isEmpty);
    expect(atTarget.goalType, WeightGoalType.maintain);
    expect(atTarget.projectedDate, isNull);
    expect(withinMaintainRange.goalType, WeightGoalType.maintain);
    expect(withinMaintainRange.projectedDate, isNull);
  });

  test('gain goal has ascending milestones toward its target', () {
    final targetDate = today.add(const Duration(days: 56));
    final plan = buildPlan(targetKg: 72, targetDate: targetDate);

    expect(plan.goalType, WeightGoalType.gain);
    expect(plan.requestedWeeklyChangeKg, closeTo(0.25, 0.0001));
    expect(plan.projectedDate, targetDate);
    expect(plan.milestones.map((milestone) => milestone.kg), [
      70.5,
      71,
      71.5,
      72,
    ]);
  });

  test('moderate workout estimate is capped at 350 kcal', () {
    final plan = buildPlan(targetKg: 65, currentKg: 110);

    expect(plan.sessionBurnKcal, 350);
  });

  test('overweight BMI warning begins at BMI 25', () {
    final atThreshold = buildPlan(targetKg: 100, currentKg: 70, heightCm: 200);
    final belowThreshold = buildPlan(
      targetKg: 99.9,
      currentKg: 70,
      heightCm: 200,
    );

    expect(atThreshold.targetBmi, 25);
    expect(
      atThreshold.warnings.any(
        (warning) => warning.contains('Your target BMI'),
      ),
      isTrue,
    );
    expect(
      atThreshold.warnings.single,
      'Your target BMI is 25.0 at your height of 200 cm '
      '(overweight range starts at 25). Check your height in Profile.',
    );
    expect(
      belowThreshold.warnings.any(
        (warning) => warning.contains('overweight BMI'),
      ),
      isFalse,
    );
  });

  test('BMI warning includes target BMI, height and range threshold', () {
    expect(
      WeightPlanner.bmiWarning(65, 160),
      'Your target BMI is 25.4 at your height of 160 cm '
      '(overweight range starts at 25). Check your height in Profile.',
    );
    expect(WeightPlanner.bmiCategory(18.49), 'underweight');
    expect(WeightPlanner.bmiCategory(18.5), 'healthy');
    expect(WeightPlanner.bmiCategory(25), 'overweight');
    expect(WeightPlanner.bmiCategory(30), 'obesity');
  });

  test('AI signature changes with goal type and target weight', () {
    WeightPlanInput input({
      required double currentKg,
      required double targetKg,
    }) => WeightPlanInput(
      currentKg: currentKg,
      targetKg: targetKg,
      ageYears: 30,
      heightCm: 170,
      sex: 'other',
      activityLevel: 'moderate',
      workoutsPerWeek: 3,
      today: today,
    );

    final gainInput = input(currentKg: 70, targetKg: 75);
    final gainPlan = WeightPlanner.build(gainInput);
    final loseInput = input(currentKg: 80, targetKg: 75);
    final losePlan = WeightPlanner.build(loseInput);
    final otherTargetInput = input(currentKg: 70, targetKg: 74);
    final otherTargetPlan = WeightPlanner.build(otherTargetInput);

    expect(gainPlan.goalType, WeightGoalType.gain);
    expect(losePlan.goalType, WeightGoalType.lose);
    expect(
      weightPlanSignature(gainInput, gainPlan),
      isNot(weightPlanSignature(loseInput, losePlan)),
    );
    expect(
      weightPlanSignature(gainInput, gainPlan),
      isNot(weightPlanSignature(otherTargetInput, otherTargetPlan)),
    );
  });

  test('AI receives the chosen schedule and planner dates and calories', () {
    final targetDate = today.add(const Duration(days: 7));
    final input = WeightPlanInput(
      currentKg: 70,
      targetKg: 65,
      ageYears: 30,
      heightCm: 170,
      sex: 'other',
      activityLevel: 'moderate',
      workoutsPerWeek: 3,
      targetDate: targetDate,
      today: today,
    );
    final plan = WeightPlanner.build(input);
    final profile = WorkerWeightPlanAiService.profileJson(input, plan);
    final projected = plan.projectedDate!;
    final projectedKey =
        '${projected.year.toString().padLeft(4, '0')}-'
        '${projected.month.toString().padLeft(2, '0')}-'
        '${projected.day.toString().padLeft(2, '0')}';

    expect(profile['workouts_per_week'], 3);
    expect(profile['recommended_workouts'], 3);
    expect(profile['target_date'], '2026-11-21');
    expect(profile['projected_target_date'], projectedKey);
    expect(profile['daily_calories'], plan.dailyCalories);
  });
}
