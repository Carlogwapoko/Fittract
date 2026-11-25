import 'food_ai_service.dart';
import 'weight_planner.dart';

String weightPlanSignature(WeightPlanInput input, WeightPlan plan) {
  String? dateKey(DateTime? date) => date == null
      ? null
      : '${date.year.toString().padLeft(4, '0')}-'
            '${date.month.toString().padLeft(2, '0')}-'
            '${date.day.toString().padLeft(2, '0')}';

  return [
    'age:${input.ageYears}',
    'sex:${input.sex}',
    'height:${input.heightCm.toStringAsFixed(1)}',
    'current:${input.currentKg.toStringAsFixed(1)}',
    'target:${input.targetKg.toStringAsFixed(1)}',
    'targetDate:${dateKey(input.targetDate) ?? ''}',
    'activity:${input.activityLevel}',
    'workouts:${input.workoutsPerWeek}',
    'goalType:${plan.goalType.name}',
    'targetKg:${input.targetKg.toStringAsFixed(1)}',
    'dailyCalories:${plan.dailyCalories}',
    'projectedDate:${dateKey(plan.projectedDate) ?? ''}',
    'weeksToGoal:${plan.weeksToGoal?.toStringAsFixed(2) ?? ''}',
  ].join('|');
}

final class AiWorkoutDay {
  const AiWorkoutDay({
    required this.day,
    required this.focus,
    required this.minutes,
  });

  final String day;
  final String focus;
  final int minutes;

  Map<String, Object?> toJson() => {
    'day': day,
    'focus': focus,
    'minutes': minutes,
  };

  static AiWorkoutDay? tryFromJson(Object? value) {
    if (value is! Map) return null;
    final day = value['day'];
    final focus = value['focus'];
    final minutes = value['minutes'];
    if (day is! String || focus is! String || minutes is! num) return null;
    if (day.trim().isEmpty || focus.trim().isEmpty || !minutes.isFinite) {
      return null;
    }
    return AiWorkoutDay(
      day: day.trim(),
      focus: focus.trim(),
      minutes: minutes.round().clamp(5, 180),
    );
  }
}

/// The AI-written part of the plan. All numbers (calories, pace, dates) come
/// from [WeightPlanner]; the AI only writes the coaching around them.
final class AiWeightPlan {
  const AiWeightPlan({
    required this.summary,
    required this.workouts,
    required this.nutritionTips,
    required this.motivation,
    required this.caution,
  });

  final String summary;
  final List<AiWorkoutDay> workouts;
  final List<String> nutritionTips;
  final String motivation;
  final String caution;

  Map<String, Object?> toJson() => {
    'summary': summary,
    'workouts': workouts.map((day) => day.toJson()).toList(),
    'nutrition_tips': nutritionTips,
    'motivation': motivation,
    'caution': caution,
  };

  /// Returns null for anything that is not a complete, well-formed plan.
  /// Used both for server responses and for the copy cached on the device.
  static AiWeightPlan? tryFromJson(Object? value) {
    if (value is! Map) return null;
    final summary = value['summary'];
    final rawWorkouts = value['workouts'];
    final rawTips = value['nutrition_tips'];
    if (summary is! String ||
        summary.trim().isEmpty ||
        rawWorkouts is! List ||
        rawTips is! List) {
      return null;
    }
    final workouts = rawWorkouts
        .map(AiWorkoutDay.tryFromJson)
        .whereType<AiWorkoutDay>()
        .take(7)
        .toList();
    final tips = rawTips
        .whereType<String>()
        .map((tip) => tip.trim())
        .where((tip) => tip.isNotEmpty)
        .take(4)
        .toList();
    if (workouts.isEmpty || tips.isEmpty) return null;
    return AiWeightPlan(
      summary: summary.trim(),
      workouts: workouts,
      nutritionTips: tips,
      motivation: value['motivation'] is String
          ? (value['motivation'] as String).trim()
          : '',
      caution: value['caution'] is String
          ? (value['caution'] as String).trim()
          : '',
    );
  }
}

abstract interface class WeightPlanAiService {
  Future<AiWeightPlan> generate(WeightPlanInput input, WeightPlan plan);
}

final class WorkerWeightPlanAiService implements WeightPlanAiService {
  const WorkerWeightPlanAiService();

  @override
  Future<AiWeightPlan> generate(WeightPlanInput input, WeightPlan plan) async {
    final data = await const WorkerFoodAiService().callWorker({
      'action': 'plan',
      'profile': profileJson(input, plan),
    });
    final result = AiWeightPlan.tryFromJson(data['plan']);
    if (result == null) {
      throw const FormatException('The AI plan could not be read.');
    }
    return result;
  }

  /// The numbers sent to the AI. Only calculated values and enums: no name,
  /// email or other personal details leave the device.
  static Map<String, Object?> profileJson(
    WeightPlanInput input,
    WeightPlan plan,
  ) {
    String? dateKey(DateTime? date) => date == null
        ? null
        : '${date.year.toString().padLeft(4, '0')}-'
              '${date.month.toString().padLeft(2, '0')}-'
              '${date.day.toString().padLeft(2, '0')}';

    return {
      'age': input.ageYears,
      'sex': const {'male', 'female'}.contains(input.sex) ? input.sex : 'other',
      'height_cm': input.heightCm.round(),
      'current_kg': double.parse(input.currentKg.toStringAsFixed(1)),
      'target_kg': double.parse(input.targetKg.toStringAsFixed(1)),
      'activity_level': input.activityLevel,
      'workouts_per_week': plan.workoutsPerWeek,
      'target_date': dateKey(input.targetDate),
      'projected_target_date': dateKey(plan.projectedDate),
      'goal_type': plan.goalType.name,
      'weeks_to_goal': plan.weeksToGoal?.round(),
      'daily_calories': plan.dailyCalories,
      'maintenance_calories': plan.maintenanceCalories,
      'exercise_kcal_per_workout': plan.exerciseKcalPerWorkout,
      'recommended_workouts': plan.workoutsPerWeek,
      'weekly_change_kg': double.parse(plan.weeklyChangeKg.toStringAsFixed(2)),
      'restricted': plan.restricted,
    };
  }
}
