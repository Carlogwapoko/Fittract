import 'dart:math' as math;

enum WeightGoalType { lose, gain, maintain }

/// Everything the planner needs. All values are validated by
/// [WeightPlanner.build], which throws [ArgumentError] for impossible input.
class WeightPlanInput {
  const WeightPlanInput({
    required this.currentKg,
    required this.targetKg,
    required this.ageYears,
    required this.heightCm,
    required this.sex,
    required this.activityLevel,
    required this.workoutsPerWeek,
    this.targetDate,
    this.today,
  });

  final double currentKg;
  final double targetKg;
  final int ageYears;
  final double heightCm;

  /// 'male', 'female' or anything else (treated as 'other').
  final String sex;

  /// 'sedentary', 'light', 'moderate', 'active' or 'very_active'.
  final String activityLevel;
  final int workoutsPerWeek;
  final DateTime? targetDate;

  /// Overridable "now" so results are testable. Defaults to DateTime.now().
  final DateTime? today;
}

class WeightPlanMilestone {
  const WeightPlanMilestone({required this.date, required this.kg});

  final DateTime date;
  final double kg;
}

class WeightPlan {
  const WeightPlan({
    required this.goalType,
    required this.restricted,
    required this.bmr,
    required this.maintenanceCalories,
    required this.dailyCalories,
    required this.calorieAdjustment,
    required this.exerciseKcalPerDay,
    required this.exerciseKcalPerWeek,
    required this.exerciseKcalPerWorkout,
    required this.sessionBurnKcal,
    required this.workoutsPerWeek,
    required this.recommendedWorkoutsPerWeek,
    required this.weeklyChangeKg,
    required this.requestedWeeklyChangeKg,
    required this.weeksToGoal,
    required this.projectedDate,
    required this.targetBmi,
    required this.milestones,
    required this.warnings,
  });

  final WeightGoalType goalType;

  /// True when the app deliberately does NOT build a weight-change plan
  /// (under 18, or a target that would be underweight). The plan then keeps
  /// calories at maintenance.
  final bool restricted;

  final int bmr;
  final int maintenanceCalories;
  final int dailyCalories;

  /// dailyCalories - maintenanceCalories (negative = deficit).
  final int calorieAdjustment;

  /// Calories the plan expects exercise to burn (lose goals only).
  final int exerciseKcalPerDay;
  final int exerciseKcalPerWeek;
  final int exerciseKcalPerWorkout;

  /// Typical burn of one 45-minute moderate workout for this person.
  final int sessionBurnKcal;

  final int workoutsPerWeek;
  final int recommendedWorkoutsPerWeek;

  /// Planned change per week in kg. Negative = losing. 0 = maintaining.
  final double weeklyChangeKg;

  /// What the chosen target date would require (kg/week, always positive),
  /// or null when no valid future date was given.
  final double? requestedWeeklyChangeKg;
  final double? weeksToGoal;
  final DateTime? projectedDate;
  final double targetBmi;
  final List<WeightPlanMilestone> milestones;
  final List<String> warnings;
}

class WeightPlanner {
  const WeightPlanner._();

  static const kcalPerKg = 7700.0;

  /// Largest calorie deficit taken from food alone.
  static const maxDietDeficitKcal = 750.0;

  /// Fastest recommended weight loss in this plan.
  static const maxWeeklyLossKg = 0.45;

  static const moderateWorkoutMet = 5.0;
  static const moderateWorkoutHours = 0.75;
  static const maxSessionBurnKcal = 350;

  /// Largest daily surplus used for gaining.
  static const maxSurplusKcal = 500.0;

  /// Share of a weight-loss deficit planned through eating less; the rest is
  /// planned through exercise.
  static const dietShareOfDeficit = 0.7;

  /// Above this many kcal per workout the plan is flagged as unrealistic.
  static const maxWorkoutKcal = 700;

  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  static double activityFactor(String level) => switch (level) {
    'sedentary' => 1.2,
    'light' => 1.375,
    'moderate' => 1.55,
    'active' => 1.725,
    'very_active' => 1.9,
    _ => 1.375,
  };

  /// Lowest daily calories this app will ever plan for a weight-loss goal.
  static int minimumCalories(String sex) => switch (sex) {
    'male' => 1500,
    'female' => 1200,
    _ => 1350,
  };

  static String bmiCategory(double bmi) => switch (bmi) {
    < 18.5 => 'underweight',
    < 25 => 'healthy',
    < 30 => 'overweight',
    _ => 'obesity',
  };

  static String? bmiWarning(double targetKg, double heightCm) {
    final heightM = heightCm / 100;
    final bmi = targetKg / (heightM * heightM);
    final category = bmiCategory(bmi);
    if (category == 'healthy') return null;

    final height = heightCm == heightCm.roundToDouble()
        ? heightCm.toStringAsFixed(0)
        : heightCm.toStringAsFixed(1);
    final range = switch (category) {
      'underweight' => 'underweight range is below 18.5',
      'overweight' => 'overweight range starts at 25',
      'obesity' => 'obesity range starts at 30',
      _ => 'healthy range is 18.5-24.9',
    };
    return 'Your target BMI is ${bmi.toStringAsFixed(1)} at your height of '
        '$height cm ($range). Check your height in Profile.';
  }

  static double safeWeeklyRate(WeightGoalType goalType) => switch (goalType) {
    WeightGoalType.lose => maxWeeklyLossKg,
    WeightGoalType.gain => maxSurplusKcal * 7 / kcalPerKg,
    WeightGoalType.maintain => 0,
  };

  static bool hasUnsafeTargetDate(WeightPlan plan) =>
      unsafeTargetDateMessage(
        requestedWeeklyChangeKg: plan.requestedWeeklyChangeKg,
        safeWeeklyChangeKg: safeWeeklyRate(plan.goalType),
        projectedDate: plan.projectedDate,
      ) !=
      null;

  static String? unsafeTargetDateMessage({
    required double? requestedWeeklyChangeKg,
    required double safeWeeklyChangeKg,
    required DateTime? projectedDate,
  }) {
    if (requestedWeeklyChangeKg == null ||
        requestedWeeklyChangeKg <= safeWeeklyChangeKg + 0.005 ||
        projectedDate == null) {
      return null;
    }
    return 'This date needs ${_kg(requestedWeeklyChangeKg)} kg/week, which is '
        'too fast. The earliest safe date is ${formatDate(projectedDate)}.';
  }

  /// Mifflin-St Jeor resting energy use (same formula as WeightEstimator).
  static double bmr(WeightPlanInput input) {
    final adjustment = switch (input.sex) {
      'male' => 5.0,
      'female' => -161.0,
      _ => -78.0,
    };
    return 10 * input.currentKg +
        6.25 * input.heightCm -
        5 * input.ageYears +
        adjustment;
  }

  static WeightPlan build(WeightPlanInput input) {
    _validate(input);
    final today = _dateOnly(input.today ?? DateTime.now());
    final bmrValue = bmr(input);
    final maintenance = bmrValue * activityFactor(input.activityLevel);
    final delta = input.targetKg - input.currentKg;
    final heightM = input.heightCm / 100;
    final targetBmi = input.targetKg / (heightM * heightM);
    final workouts = input.workoutsPerWeek.clamp(1, 7);
    final sessionBurn = math.min(
      maxSessionBurnKcal,
      (moderateWorkoutMet * input.currentKg * moderateWorkoutHours).round(),
    );
    final warnings = <String>[];

    var type = delta.abs() < 0.5
        ? WeightGoalType.maintain
        : delta < 0
        ? WeightGoalType.lose
        : WeightGoalType.gain;

    var restricted = false;
    if (input.ageYears < 18 && type != WeightGoalType.maintain) {
      restricted = true;
      warnings.add(
        'Weight-change plans are only available for adults. Your calories are kept at maintenance. Please talk to a doctor or dietitian about healthy weight goals.',
      );
    }
    final targetBmiWarning = bmiWarning(input.targetKg, input.heightCm);
    if (input.ageYears >= 18 &&
        type == WeightGoalType.lose &&
        targetBmi < 18.5) {
      restricted = true;
      warnings.add(
        '${targetBmiWarning ?? 'This target would be below a healthy BMI.'} '
        'No weight-loss plan is created. Choose a higher target weight, or talk '
        'to a doctor or dietitian.',
      );
    }
    if (restricted) type = WeightGoalType.maintain;
    if (targetBmi >= 25 && targetBmiWarning != null) {
      warnings.add(targetBmiWarning);
    }

    // ---- Maintain / restricted -------------------------------------------
    if (type == WeightGoalType.maintain) {
      return WeightPlan(
        goalType: type,
        restricted: restricted,
        bmr: bmrValue.round(),
        maintenanceCalories: maintenance.round(),
        dailyCalories: maintenance.round(),
        calorieAdjustment: 0,
        exerciseKcalPerDay: 0,
        exerciseKcalPerWeek: 0,
        exerciseKcalPerWorkout: 0,
        sessionBurnKcal: sessionBurn,
        workoutsPerWeek: workouts,
        recommendedWorkoutsPerWeek: 3,
        weeklyChangeKg: 0,
        requestedWeeklyChangeKg: null,
        weeksToGoal: null,
        projectedDate: null,
        targetBmi: targetBmi,
        milestones: const [],
        warnings: warnings,
      );
    }

    // ---- Lose / gain -----------------------------------------------------
    final losing = type == WeightGoalType.lose;
    final safeWeekly = losing
        ? maxWeeklyLossKg
        : maxSurplusKcal * 7 / kcalPerKg;
    final defaultWeekly = losing ? math.min(0.5, safeWeekly) : 0.25;

    final rawDate = input.targetDate;
    final daysToDate = rawDate == null
        ? null
        : _dateOnly(rawDate).difference(today).inDays;
    final hasFutureDate = daysToDate != null && daysToDate > 0;
    if (rawDate != null && !hasFutureDate) {
      warnings.add(
        'Your target date has passed or is today. Choose a future date. A gentle default pace is used for now.',
      );
    }
    final days = daysToDate;
    final requested = days != null && days > 0
        ? delta.abs() / (days / 7)
        : null;
    final planned = requested == null
        ? defaultWeekly
        : math.min(requested, safeWeekly);

    final weeks = delta.abs() / planned;
    final totalDays = (weeks * 7).ceil();
    final projected = today.add(Duration(days: totalDays));

    final unsafeDateMessage = unsafeTargetDateMessage(
      requestedWeeklyChangeKg: requested,
      safeWeeklyChangeKg: safeWeekly,
      projectedDate: projected,
    );
    if (unsafeDateMessage != null) warnings.add(unsafeDateMessage);

    final dailyEnergy = planned * kcalPerKg / 7;
    var dietPart = 0.0;
    var exerciseDaily = 0.0;
    double dailyCalories;
    int recommended;

    if (losing) {
      final minCal = minimumCalories(input.sex);
      final maxDiet = math.max(
        0.0,
        math.min(
          math.min(maintenance * 0.25, maxDietDeficitKcal),
          maintenance - minCal,
        ),
      );
      dietPart = math.min(dailyEnergy * dietShareOfDeficit, maxDiet);
      exerciseDaily = dailyEnergy - dietPart;
      dailyCalories = maintenance - dietPart;

      final weeklyExercise = exerciseDaily * 7;
      final needed = sessionBurn <= 0
          ? 3
          : (weeklyExercise / sessionBurn).ceil();
      recommended = needed.clamp(3, 6);

      final perWorkoutUser = weeklyExercise / workouts;
      final perWorkoutRecommended = weeklyExercise / recommended;
      if (perWorkoutRecommended > maxWorkoutKcal) {
        warnings.add(
          'This pace needs more exercise than is realistic. Choose a later target date for a safer, easier plan.',
        );
      } else if (perWorkoutUser > maxWorkoutKcal) {
        warnings.add(
          'At $workouts workouts per week each session would need about ${perWorkoutUser.round()} kcal. $recommended workouts per week would spread it out more comfortably.',
        );
      }
      if (workouts < 3) {
        warnings.add(
          'Aim for at least 3 workouts per week to support your weight-loss goal.',
        );
      }
    } else {
      dailyCalories = maintenance + dailyEnergy;
      recommended = 4;
    }

    final milestones = <WeightPlanMilestone>[];
    for (final fraction in const [0.25, 0.5, 0.75, 1.0]) {
      final milestoneDays = (totalDays * fraction).round();
      final changedKg = math.min(delta.abs(), planned * milestoneDays / 7);
      milestones.add(
        WeightPlanMilestone(
          date: today.add(Duration(days: milestoneDays)),
          kg: losing
              ? input.currentKg - changedKg
              : input.currentKg + changedKg,
        ),
      );
    }

    final weeklyExerciseKcal = exerciseDaily * 7;
    return WeightPlan(
      goalType: type,
      restricted: false,
      bmr: bmrValue.round(),
      maintenanceCalories: maintenance.round(),
      dailyCalories: dailyCalories.round(),
      calorieAdjustment: dailyCalories.round() - maintenance.round(),
      exerciseKcalPerDay: exerciseDaily.round(),
      exerciseKcalPerWeek: weeklyExerciseKcal.round(),
      exerciseKcalPerWorkout: (weeklyExerciseKcal / workouts).round(),
      sessionBurnKcal: sessionBurn,
      workoutsPerWeek: workouts,
      recommendedWorkoutsPerWeek: recommended,
      weeklyChangeKg: losing ? -planned : planned,
      requestedWeeklyChangeKg: requested,
      weeksToGoal: weeks,
      projectedDate: projected,
      targetBmi: targetBmi,
      milestones: milestones,
      warnings: warnings,
    );
  }

  static String formatDate(DateTime date) =>
      '${_months[date.month - 1]} ${date.day}, ${date.year}';

  static String _kg(double value) => value.toStringAsFixed(2);

  static DateTime _dateOnly(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  static void _validate(WeightPlanInput input) {
    bool inRange(double value, double min, double max) =>
        value.isFinite && value >= min && value <= max;
    if (!inRange(input.currentKg, 20, 300)) {
      throw ArgumentError.value(
        input.currentKg,
        'currentKg',
        'Must be 20-300.',
      );
    }
    if (!inRange(input.targetKg, 20, 300)) {
      throw ArgumentError.value(input.targetKg, 'targetKg', 'Must be 20-300.');
    }
    if (!inRange(input.heightCm, 100, 250)) {
      throw ArgumentError.value(input.heightCm, 'heightCm', 'Must be 100-250.');
    }
    if (input.ageYears < 13 || input.ageYears > 100) {
      throw ArgumentError.value(input.ageYears, 'ageYears', 'Must be 13-100.');
    }
  }
}
