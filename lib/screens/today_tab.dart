import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/weight_estimator.dart';
import '../store/store.dart';
import '../widgets/log_activity_sheet.dart';
import '../widgets/shared_widgets.dart';
import '../widgets/today_widgets.dart';
import 'activity_screen.dart';
import 'meal_picker_screen.dart';
import 'routines_tab.dart';
import 'water_screen.dart';
import 'weight_screen.dart';
import 'workout_screen.dart';

Future<void> showWaterActivity(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (context) => SizedBox(
        height: MediaQuery.sizeOf(context).height * .86,
        child: const WaterScreen(embedded: true),
      ),
    );

class TodayTab extends StatefulWidget {
  final void Function(int) goTo;
  const TodayTab({super.key, required this.goTo});

  @override
  State<TodayTab> createState() => _TodayTabState();
}

class _TodayTabState extends State<TodayTab> {
  bool _remindersOpened = false;

  Future<void> _openReminders(BuildContext context) async {
    setState(() => _remindersOpened = true);
    final action = await showTodayReminders(context);
    if (!context.mounted) return;
    if (action == 'water') {
      _addWater(context);
    } else if (action == 'activity') {
      showLogActivity(context);
    }
  }

  void _addWater(BuildContext context) {
    final entry = {
      'd': today(),
      'ml': 250,
      't': DateTime.now().millisecondsSinceEpoch,
    };
    final water = store.d['water'];
    if (water is List) {
      water.add(entry);
    } else {
      store.d['water'] = [entry];
    }
    store.save();

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: const Text('Added 250 ml of water'),
          duration: const Duration(seconds: 2),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () {
              final entries = store.d['water'];
              if (entries is List && entries.remove(entry)) store.save();
            },
          ),
        ),
      );
  }

  Future<void> _editDailyGoals(BuildContext context) async {
    final goals = store.nutritionGoals;
    final values = await showModalBottomSheet<Map<String, int>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _DailyGoalsSheet(
        calories: (goals['calories'] as num).toInt(),
        waterMl: store.waterGoalMl,
        steps: store.stepGoal,
      ),
    );
    if (values == null || !context.mounted) return;

    store.d['nutritionGoals'] = {...goals, 'calories': values['calories']};
    store.d['activityGoals'] = {
      ...store.activityGoals,
      'waterMl': values['water'],
      'steps': values['steps'],
    };
    store.save();
    snack(context, 'Daily goals saved.');
  }

  @override
  Widget build(BuildContext context) => live((c) {
    final now = DateTime.now();
    final greeting = now.hour < 12
        ? 'Good morning'
        : now.hour < 17
        ? 'Good afternoon'
        : 'Good evening';
    final rawName = (store.d['name'] as String?)?.trim() ?? '';
    final firstName = rawName.isEmpty
        ? ''
        : rawName.split(RegExp(r'\s+')).first;
    final title = firstName.isEmpty ? '$greeting!' : '$greeting, $firstName';
    final reminders = store.notes().length;
    final newReminders = reminders > 0 && !_remindersOpened;
    final calorieGoal = (store.nutritionGoals['calories'] as num).toInt();
    final caloriesEaten = store.kcal();
    final waterGoalMl = store.waterGoalMl;
    final waterMl = store.water();
    final weightEstimate = WeightEstimator.calculate(store.d);
    final weightEntries = _weightEntries();
    final manualWeightToday = weightEntries.any((entry) => entry.$1 == today());
    final currentWeightDay = weightEstimate.days.isEmpty
        ? null
        : weightEstimate.days.last;
    final estimatedWeight =
        weightEstimate.hasAnchor &&
        !manualWeightToday &&
        currentWeightDay != null &&
        !currentWeightDay.anchor &&
        currentWeightDay.complete &&
        !currentWeightDay.manuallyWeighed;
    final weeklyCount = store.wkCount(0);
    final weeklyGoal = store.weeklyWorkoutGoal;

    final schedules =
        store.sch
            .where((entry) => entry is Map && entry['d'] == today())
            .toList()
          ..sort((a, b) => '${a['t']}'.compareTo('${b['t']}'));
    final scheduled = schedules.isEmpty ? null : schedules.first as Map;
    final completedWorkouts = store.hist
        .where((entry) => entry is Map && entry['d'] == today())
        .toList();
    final completed = completedWorkouts.isEmpty
        ? null
        : completedWorkouts.last as Map;
    final activeWorkout = store.d['activeW'];
    final resumeRoutine = activeWorkout is Map
        ? (store.routine(activeWorkout['rid']) ??
              (activeWorkout['routine'] is Map
                  ? activeWorkout['routine'] as Map
                  : null))
        : null;
    final routine = scheduled == null ? null : store.routine(scheduled['r']);
    final rawExercises = routine?['ex'];
    final exercises = rawExercises is List ? rawExercises : const [];

    final weightSubtitle = estimatedWeight
        ? 'Estimated from calories consumed and burned'
        : _weightSubtitle(weightEstimate, weightEntries);
    final unreadCount = newReminders ? reminders : 0;
    final dark = isDark(c);
    final primary = primaryOf(c);
    final caloriesOverGoal = caloriesEaten > calorieGoal;
    final waterGoalReached = waterMl >= waterGoalMl;
    final stepGoal = store.stepGoal;

    Widget notificationButton() => Stack(
      clipBehavior: Clip.none,
      children: [
        RoundActionButton(
          icon: Icons.notifications_none,
          tooltip: newReminders ? 'Reminders, $reminders new' : 'Reminders',
          onPressed: () => _openReminders(c),
          backgroundColor: Theme.of(c).colorScheme.surface,
          foregroundColor: Theme.of(c).colorScheme.onSurface,
          circular: true,
          height: 44,
        ),
        if (unreadCount > 0)
          Positioned(
            right: -3,
            top: -3,
            child: Container(
              constraints: const BoxConstraints(minWidth: 17, minHeight: 17),
              padding: const EdgeInsets.symmetric(horizontal: 4),
              decoration: const BoxDecoration(
                color: Color(0xFFC83D3D),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Text(
                unreadCount > 9 ? '9+' : '$unreadCount',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
      ],
    );

    return SafeArea(
      child: ColoredBox(
        color: Theme.of(c).scaffoldBackgroundColor,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 24),
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            DateFormat('EEEE, MMMM d')
                                .format(now)
                                .toUpperCase(),
                            style: TextStyle(
                              color: primary,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Theme.of(c).colorScheme.onSurface,
                              fontSize: 25,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -.45,
                              height: 1.15,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    notificationButton(),
                  ],
                ),
                const SizedBox(height: 14),
                Align(
                  alignment: Alignment.centerLeft,
                  child: StreakChip(days: store.streak()),
                ),
                const SizedBox(height: 14),
                TodayWorkoutCard(
                  title: resumeRoutine == null
                      ? (completed == null
                            ? (scheduled == null
                                  ? null
                                  : routine == null
                                  ? '(deleted routine)'
                                  : '${routine['name'] ?? 'Workout'}')
                            : '✓ ${completed['n'] ?? 'Workout'} done')
                      : '${resumeRoutine['name'] ?? 'Workout'}',
                  detail: resumeRoutine != null
                      ? 'Workout in progress'
                      : completed != null
                      ? 'Great work. ${completed['min'] ?? 0} min · '
                            '${completed['ex'] ?? 0} of '
                            '${completed['totalEx'] ?? completed['ex'] ?? 0} exercises'
                      : routine == null
                      ? (scheduled == null
                            ? null
                            : 'This scheduled routine was deleted.')
                      : '${exercises.length} exercises · about '
                            '${routineMinutes(exercises)} min',
                  badges: resumeRoutine != null
                      ? const ['WORKOUT IN PROGRESS']
                      : completed != null
                      ? [
                          '🔥 ${completed['kc'] ?? 0} kcal',
                          '${completed['sets'] ?? 0} sets',
                        ]
                      : routine == null
                      ? const []
                      : [
                          'Scheduled for ${_formatScheduleTime(scheduled?['t'])}',
                          if ('${routine['type'] ?? ''}'.isNotEmpty)
                            '${routine['type']}',
                        ],
                  actionLabel: resumeRoutine != null
                      ? 'Resume workout'
                      : completed != null
                      ? 'View summary'
                      : routine != null
                      ? 'Start workout'
                      : scheduled != null
                      ? 'Schedule a workout'
                      : null,
                  onAction: resumeRoutine != null
                      ? () => go(c, WorkoutScreen(resumeRoutine))
                      : completed != null
                      ? () => widget.goTo(3)
                      : routine != null
                      ? () => go(c, WorkoutScreen(routine))
                      : scheduled != null
                      ? () => widget.goTo(2)
                      : null,
                  weeklyCount: weeklyCount,
                  weeklyGoal: weeklyGoal,
                  onChooseRoutine: () => widget.goTo(1),
                  onScheduleWorkout: () => widget.goTo(2),
                ),
                const SizedBox(height: 14),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Text(
                        'Your daily balance',
                        style: TextStyle(
                          color: Theme.of(c).colorScheme.onSurface,
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () => _editDailyGoals(c),
                      child: const Text('Edit goals'),
                    ),
                  ],
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    'Tap a card to log or see details',
                    style: TextStyle(
                      color: Theme.of(c).colorScheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: ProgressRingCard(
                        title: 'Meals',
                        value: store.withThousands(caloriesEaten),
                        unit: 'kcal',
                        subtitle: caloriesEaten == 0
                            ? 'Nothing logged yet. Add your first meal.'
                            : caloriesEaten < calorieGoal
                            ? '${store.withThousands(calorieGoal - caloriesEaten)} kcal left today'
                            : caloriesEaten > calorieGoal
                            ? '${store.withThousands(caloriesEaten - calorieGoal)} kcal over your goal'
                            : 'You reached your calorie goal.',
                        progress: caloriesEaten / calorieGoal,
                        icon: Icons.restaurant,
                        backgroundColor: caloriesOverGoal
                            ? (dark
                                  ? const Color(0xFF3A2D23)
                                  : const Color(0xFFFFF2E8))
                            : null,
                        subtitleColor: caloriesOverGoal
                            ? (dark
                                  ? const Color(0xFFFFBF80)
                                  : const Color(0xFF9A4D0A))
                            : null,
                        onTap: () => go(c, const ManualMealScreen()),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ProgressRingCard(
                        title: 'Water',
                        value:
                            '${(waterMl / 1000).toStringAsFixed(1)} of '
                            '${(waterGoalMl / 1000).toStringAsFixed(1)} L',
                        subtitle: waterMl == 0
                            ? 'Log your first glass.'
                            : waterGoalReached
                            ? 'Goal reached. Nice work.'
                            : '${((waterGoalMl - waterMl) / 1000).toStringAsFixed(1)} L to go',
                        progress: waterMl / waterGoalMl,
                        icon: Icons.water_drop,
                        accentColor: const Color(0xFF1D6FB8),
                        backgroundColor: waterGoalReached
                            ? const Color(0xFF1D6FB8)
                                  .withValues(alpha: dark ? .2 : .1)
                            : null,
                        subtitleColor: waterGoalReached
                            ? const Color(0xFF1D6FB8)
                            : null,
                        onTap: () => showWaterActivity(c),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: ProgressRingCard(
                        title: 'Daily steps',
                        value: store.withThousands(store.steps),
                        unit: 'steps',
                        subtitle:
                            'of ${store.withThousands(stepGoal)} steps today',
                        progress: store.steps / stepGoal,
                        icon: Icons.directions_run,
                        accentColor: const Color(0xFFB25E09),
                        onTap: () => go(c, const ActivityScreen()),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ProgressRingCard(
                        title: 'Weight',
                        value: weightEstimate.hasAnchor
                            ? weightEstimate.currentWeightKg.toStringAsFixed(1)
                            : 'Not set',
                        unit: weightEstimate.hasAnchor ? 'kg' : null,
                        subtitle: weightSubtitle,
                        icon: Icons.monitor_weight,
                        estimated: estimatedWeight,
                        onTap: () => go(c, const WeightScreen()),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  });

  List<(String, double)> _weightEntries() {
    final rawWeights = store.d['weights'];
    if (rawWeights is! List) return [];
    final entries = <(String, double)>[];
    for (final raw in rawWeights.whereType<List>()) {
      if (raw.length < 2 || raw[0] is! String || raw[1] is! num) continue;
      final date = raw[0] as String;
      final parsedDate = DateTime.tryParse(date);
      final weight = (raw[1] as num).toDouble();
      if (parsedDate == null || !weight.isFinite || weight <= 0) continue;
      entries.add((date, weight));
    }
    entries.sort((a, b) => a.$1.compareTo(b.$1));
    return entries;
  }

  String _weightSubtitle(
    WeightEstimateSeries estimate,
    List<(String, double)> entries,
  ) {
    if (!estimate.hasAnchor) {
      return 'Add your weight to personalize your goals.';
    }
    if (entries.length < 2) return 'Weight is being tracked.';
    final change = entries.last.$2 - entries[entries.length - 2].$2;
    if (change.abs() < .05) return 'Same as last week';
    final direction = change < 0 ? 'Down' : 'Up';
    return '$direction ${change.abs().toStringAsFixed(1)} kg this week';
  }

  String _formatScheduleTime(Object? value) {
    final parts = '$value'.split(':');
    if (parts.length != 2) return '$value';
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null || hour < 0 || hour > 23) {
      return '$value';
    }
    final displayHour = hour % 12 == 0 ? 12 : hour % 12;
    return '$displayHour:${minute.toString().padLeft(2, '0')} '
        '${hour < 12 ? 'AM' : 'PM'}';
  }
}

class _DailyGoalsSheet extends StatefulWidget {
  const _DailyGoalsSheet({
    required this.calories,
    required this.waterMl,
    required this.steps,
  });

  final int calories;
  final int waterMl;
  final int steps;

  @override
  State<_DailyGoalsSheet> createState() => _DailyGoalsSheetState();
}

class _DailyGoalsSheetState extends State<_DailyGoalsSheet> {
  late final _calories = TextEditingController(text: '${widget.calories}');
  late final _water = TextEditingController(text: '${widget.waterMl}');
  late final _steps = TextEditingController(text: '${widget.steps}');

  @override
  void dispose() {
    _calories.dispose();
    _water.dispose();
    _steps.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        4,
        20,
        MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Daily goals',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            const Text('Set targets that work for your day.', style: muted),
            const SizedBox(height: kGapLg),
            _goalField(
              _calories,
              'Calorie goal',
              'kcal',
              Icons.restaurant_outlined,
            ),
            const SizedBox(height: kGapMd),
            _goalField(_water, 'Water goal', 'ml', Icons.water_drop_outlined),
            const SizedBox(height: kGapMd),
            _goalField(
              _steps,
              'Step goal',
              'steps',
              Icons.directions_walk_outlined,
            ),
            const SizedBox(height: kGapLg),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(kGapLg),
              decoration: BoxDecoration(
                color: tintOf(context),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  Icon(Icons.tune, color: primaryOf(context)),
                  const SizedBox(width: kGapMd),
                  const Expanded(
                    child: Text(
                      'Your goals update the daily balance cards.',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: kGapLg),
            btn('Save changes', _save),
          ],
        ),
      ),
    ),
  );

  Widget _goalField(
    TextEditingController controller,
    String label,
    String unit,
    IconData icon,
  ) => TextField(
    controller: controller,
    keyboardType: TextInputType.number,
    decoration: InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon),
      suffixText: unit,
    ),
  );

  void _save() {
    final calories = int.tryParse(_calories.text.trim());
    final water = int.tryParse(_water.text.trim());
    final steps = int.tryParse(_steps.text.trim());

    if (calories == null || calories < 500 || calories > 10000) {
      snack(context, 'Calorie goal must be between 500 and 10,000 kcal.');
      return;
    }
    if (water == null || water < 500 || water > 10000) {
      snack(context, 'Water goal must be between 500 and 10,000 ml.');
      return;
    }
    if (steps == null || steps < 1000 || steps > 50000) {
      snack(context, 'Step goal must be between 1,000 and 50,000.');
      return;
    }

    Navigator.pop(context, {
      'calories': calories,
      'water': water,
      'steps': steps,
    });
  }
}
