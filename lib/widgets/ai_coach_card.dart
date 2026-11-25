import 'dart:async';

import 'package:flutter/material.dart';

import '../services/food_ai_service.dart';
import '../services/weight_plan_ai_service.dart';
import '../services/weight_planner.dart';
import '../store/store.dart';
import 'shared_widgets.dart';

class _AiCoachIcon extends StatelessWidget {
  const _AiCoachIcon({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SizedBox.square(
      dimension: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: tintOf(context),
              borderRadius: BorderRadius.circular(size * 0.28),
            ),
            child: Center(
              child: Icon(
                Icons.monitor_heart_rounded,
                color: primaryOf(context),
                size: size * 0.72,
              ),
            ),
          ),
          Positioned(
            top: -size * 0.04,
            right: -size * 0.04,
            child: Container(
              width: size * 0.38,
              height: size * 0.38,
              decoration: BoxDecoration(
                color: colors.surface,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.bolt_rounded,
                color: colors.tertiary,
                size: size * 0.28,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// AI coach: asks the AI for a weekly workout schedule and nutrition tips.
///
/// The safe calorie numbers come from [WeightPlanner] (a fixed formula) and
/// are handed to the AI, which only writes the coaching around them.
class AiCoachCard extends StatefulWidget {
  const AiCoachCard({super.key, required this.currentKg, this.aiService});

  /// Current (estimated or weighed) weight in kg. 0 when tracking has not
  /// started yet.
  final double currentKg;
  final WeightPlanAiService? aiService;

  @override
  State<AiCoachCard> createState() => _AiCoachCardState();
}

class _AiCoachCardState extends State<AiCoachCard> {
  AiWeightPlan? _ai;
  String? _aiSignature;
  String? _aiFacts;
  bool _loading = false;
  String? _error;
  Object? _cachedRecord;

  WeightPlanAiService get _service =>
      widget.aiService ?? const WorkerWeightPlanAiService();

  @override
  void initState() {
    super.initState();
    store.addListener(_storeChanged);
    _readCachedPlan();
  }

  void _readCachedPlan() {
    final cached = store.d['aiWeightPlan'];
    _cachedRecord = cached;
    if (cached is Map) {
      _ai = AiWeightPlan.tryFromJson(cached['plan']);
      _aiSignature = cached['sig'] is String ? cached['sig'] as String : null;
      _aiFacts = cached['facts'] is String ? cached['facts'] as String : null;
    } else {
      _ai = null;
      _aiSignature = null;
      _aiFacts = null;
    }
  }

  void _storeChanged() {
    final cached = store.d['aiWeightPlan'];
    if (identical(cached, _cachedRecord)) return;
    _readCachedPlan();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    store.removeListener(_storeChanged);
    super.dispose();
  }

  ({WeightPlanInput? input, String? problem}) _readInput() {
    final kg = widget.currentKg;
    if (kg < 20 || kg > 300) {
      return (
        input: null,
        problem: 'Enter your starting weight above to use the AI coach.',
      );
    }
    final rawAge = store.d['age'];
    final rawHeight = store.d['h'];
    final age = rawAge is num ? rawAge.toInt() : null;
    final height = rawHeight is num ? rawHeight.toDouble() : null;
    if (age == null ||
        age < 13 ||
        age > 100 ||
        height == null ||
        height < 100 ||
        height > 250) {
      return (
        input: null,
        problem: 'Add your age and height in Profile to use the AI coach.',
      );
    }
    final target = store.goalField('w');
    final hasTarget = target >= 20 && target <= 300;
    final dateText = '${store.goal['d'] ?? ''}'.trim();
    final sex = store.d['sex'];
    final activity = store.d['activityLevel'];
    return (
      input: WeightPlanInput(
        currentKg: kg,
        targetKg: hasTarget ? target : kg,
        ageYears: age,
        heightCm: height,
        sex: sex is String ? sex : 'other',
        activityLevel: activity is String ? activity : 'light',
        workoutsPerWeek: store.weeklyWorkoutGoal,
        targetDate: dateText.isEmpty ? null : DateTime.tryParse(dateText),
      ),
      problem: null,
    );
  }

  String _factsOf(WeightPlan plan) {
    final daily = store.withThousands(plan.dailyCalories);
    if (plan.goalType == WeightGoalType.lose &&
        plan.exerciseKcalPerWorkout > 0) {
      final perWorkout = store.withThousands(plan.exerciseKcalPerWorkout);
      return 'Built for about $daily kcal a day and about $perWorkout kcal burned per workout.';
    }
    return 'Built for about $daily kcal a day.';
  }

  Future<void> _generate(
    WeightPlanInput input,
    WeightPlan plan,
    String signature,
  ) async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await _service.generate(input, plan);
      if (!mounted) return;
      if (!_matchesCurrentPlan(signature)) {
        setState(() {
          _loading = false;
        });
        return;
      }
      final facts = _factsOf(plan);
      store.d['aiWeightPlan'] = {
        'sig': signature,
        'facts': facts,
        'plan': result.toJson(),
      };
      store.save();
      setState(() {
        _ai = result;
        _aiSignature = signature;
        _aiFacts = facts;
        _loading = false;
      });
    } on FoodAiException catch (error) {
      if (!mounted) return;
      if (!_matchesCurrentPlan(signature)) {
        setState(() {
          _loading = false;
        });
        return;
      }
      setState(() {
        _loading = false;
        _error = error.message;
      });
    } on FormatException {
      if (!mounted) return;
      if (!_matchesCurrentPlan(signature)) {
        setState(() {
          _loading = false;
        });
        return;
      }
      setState(() {
        _loading = false;
        _error = 'The AI plan could not be read. Please try again.';
      });
    } catch (_) {
      if (!mounted) return;
      if (!_matchesCurrentPlan(signature)) {
        setState(() {
          _loading = false;
        });
        return;
      }
      setState(() {
        _loading = false;
        _error = 'The AI coach is unavailable right now. Please try again.';
      });
    }
  }

  bool _matchesCurrentPlan(String signature) {
    final input = _readInput().input;
    if (input == null) return false;
    try {
      return weightPlanSignature(input, WeightPlanner.build(input)) ==
          signature;
    } on ArgumentError {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final read = _readInput();
    final input = read.input;
    if (input == null) {
      return card(
        child: Row(
          children: [
            Icon(Icons.info_outline, color: primaryOf(context)),
            const SizedBox(width: kGapMd),
            Expanded(
              child: Text(
                read.problem ?? '',
                style: const TextStyle(height: 1.4),
              ),
            ),
          ],
        ),
      );
    }

    final WeightPlan plan;
    try {
      plan = WeightPlanner.build(input);
    } on ArgumentError {
      return card(
        child: const Text(
          'Check your weight, height and age to use the AI coach.',
          style: TextStyle(height: 1.4),
        ),
      );
    }

    final signature = weightPlanSignature(input, plan);
    final stale = _ai != null && _aiSignature != signature;
    final colors = Theme.of(context).colorScheme;
    final mutedColor = colors.onSurfaceVariant;

    return card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _AiCoachIcon(size: 32),
              const SizedBox(width: kGapMd),
              Expanded(
                child: Text(
                  'Get a weekly workout schedule and nutrition tips from the AI coach, based on your weight, goal and activity level.',
                  style: TextStyle(
                    color: mutedColor,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: kGapMd),
          if (stale)
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _loading
                    ? null
                    : () => _generate(input, plan, signature),
                icon: const Icon(Icons.refresh),
                label: const Text('Refresh AI plan'),
              ),
            ),
          if (stale)
            Padding(
              padding: const EdgeInsets.only(top: kGapSm),
              child: Text(
                'Out of date. Your goals changed, so this plan is hidden until refreshed.',
                style: TextStyle(color: mutedColor, fontSize: 12, height: 1.4),
              ),
            ),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: kGapMd),
              child: Row(
                children: [
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: kGapMd),
                  Text('Building your plan…'),
                ],
              ),
            )
          else if (_ai != null && !stale)
            _aiResult(context, _ai!)
          else if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: kGapSm),
              child: Text(
                _error!,
                style: TextStyle(color: colors.error, fontSize: 13),
              ),
            ),
          const SizedBox(height: kGapMd),
          if (_ai != null && !stale && !_loading)
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton.icon(
                onPressed: () => _generate(input, plan, signature),
                icon: const Icon(Icons.refresh),
                label: const Text('Refresh AI plan'),
              ),
            )
          else if (_ai == null && !_loading)
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton.icon(
                onPressed: () => _generate(input, plan, signature),
                icon: const _AiCoachIcon(size: 22),
                label: const Text('Get AI coaching plan'),
              ),
            ),
          const SizedBox(height: kGapMd),
          Text(
            'Estimates only, not medical advice. Check with a doctor or dietitian before making big changes to your eating or exercise.',
            style: TextStyle(color: mutedColor, fontSize: 12, height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget _aiResult(BuildContext context, AiWeightPlan ai) {
    final mutedColor = Theme.of(context).colorScheme.onSurfaceVariant;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(kGapMd),
      decoration: BoxDecoration(
        color: tintOf(context),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(ai.summary, style: const TextStyle(height: 1.4)),
          if (_aiFacts != null) ...[
            const SizedBox(height: kGapSm),
            Text(
              _aiFacts!,
              style: TextStyle(color: mutedColor, fontSize: 12, height: 1.4),
            ),
          ],
          const SizedBox(height: kGapMd),
          const Text(
            'Weekly workouts',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: kGapXs),
          for (final day in ai.workouts)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 96,
                    child: Text(
                      day.day,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  Expanded(child: Text('${day.focus} · ${day.minutes} min')),
                ],
              ),
            ),
          const SizedBox(height: kGapMd),
          const Text(
            'Nutrition tips',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: kGapXs),
          for (final tip in ai.nutritionTips)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('•  '),
                  Expanded(
                    child: Text(tip, style: const TextStyle(height: 1.35)),
                  ),
                ],
              ),
            ),
          if (ai.motivation.isNotEmpty) ...[
            const SizedBox(height: kGapMd),
            Text(
              ai.motivation,
              style: const TextStyle(fontStyle: FontStyle.italic, height: 1.4),
            ),
          ],
          if (ai.caution.isNotEmpty) ...[
            const SizedBox(height: kGapSm),
            Text(
              ai.caution,
              style: TextStyle(color: mutedColor, fontSize: 12, height: 1.4),
            ),
          ],
        ],
      ),
    );
  }
}
