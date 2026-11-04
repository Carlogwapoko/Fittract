import 'package:flutter/material.dart';

import '../services/weight_estimator.dart';
import '../store/store.dart';
import '../widgets/log_activity_sheet.dart';
import '../widgets/shared_widgets.dart';
import 'food_screen.dart';
import 'meal_picker_screen.dart';
import 'routines_tab.dart';
import 'water_screen.dart';
import 'weight_screen.dart';
import 'workout_screen.dart';

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

  @override
  Widget build(BuildContext context) => live((c) {
    final now = DateTime.now();
    final hour = now.hour;
    final greeting = hour < 12
        ? 'Good morning'
        : hour < 17
        ? 'Good afternoon'
        : 'Good evening';
    final rawName = (store.d['name'] as String?)?.trim() ?? '';
    final weightEstimate = WeightEstimator.calculate(store.d);
    final firstName = rawName.isEmpty
        ? ''
        : rawName.split(RegExp(r'\s+')).first;
    final title = firstName.isEmpty ? '$greeting!' : '$greeting, $firstName';
    final reminders = store.notes().length;
    final newReminders = reminders > 0 && !_remindersOpened;
    final calorieGoal = (store.nutritionGoals['calories'] as num).toInt();
    final waterGoalMl = store.waterGoalMl;
    final stepGoal = store.stepGoal;
    final waterMl = store.water();
    final visibleWaterMl = waterMl.clamp(0, 99900);
    final todaysSchedules =
        store.sch
            .where((entry) => entry is Map && entry['d'] == today())
            .toList()
          ..sort((a, b) => '${a['t']}'.compareTo('${b['t']}'));
    final scheduled = todaysSchedules.isEmpty ? null : todaysSchedules.first;
    final todayHistory = store.hist
        .where((entry) => entry is Map && entry['d'] == today())
        .toList();
    final completed = todayHistory.isEmpty ? null : todayHistory.last;
    final activeWorkout = store.d['activeW'];
    final resumeRoutine = activeWorkout is Map
        ? (store.routine(activeWorkout['rid']) ??
              (activeWorkout['routine'] is Map
                  ? activeWorkout['routine'] as Map
                  : null))
        : null;

    return tabBody([
      hdr(
        c,
        niceDate(),
        title,
        act: [
          SizedBox(
            width: 48,
            height: 48,
            child: IconButton(
              tooltip: newReminders ? 'Reminders, $reminders new' : 'Reminders',
              onPressed: () => _openReminders(c),
              icon: Badge(
                isLabelVisible: newReminders,
                label: Text('$reminders'),
                child: const Icon(Icons.notifications_none),
              ),
            ),
          ),
        ],
      ),
      Text('🔥 ${store.streak()}-day streak · Keep showing up.', style: muted),
      const SizedBox(height: kGapMd),
      _workoutHero(
        c,
        scheduled: scheduled,
        completed: completed,
        resumeRoutine: resumeRoutine,
      ),
      h3('Your daily balance'),
      Padding(
        padding: const EdgeInsets.only(bottom: kGapMd),
        child: Text('Tap a card to log or see details.', style: muted),
      ),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: _DailyBalanceCard(
              icon: Icons.restaurant_outlined,
              value: '${store.withThousands(store.kcal())} kcal',
              detail: 'Food & meals · of ${store.withThousands(calorieGoal)}',
              progress: calorieGoal > 0 ? store.kcal() / calorieGoal : 0,
              action: '＋ Add meal',
              onTap: () => go(c, const FoodScreen()),
              onAction: () => go(c, const ManualMealScreen()),
            ),
          ),
          const SizedBox(width: kGapMd),
          Expanded(
            child: _DailyBalanceCard(
              icon: Icons.water_drop_outlined,
              value:
                  '${(visibleWaterMl / 1000).toStringAsFixed(1)}${waterMl > 99900 ? '+' : ''} L',
              detail: 'Water · of ${(waterGoalMl / 1000).toStringAsFixed(1)} L',
              progress: waterGoalMl > 0 ? waterMl / waterGoalMl : 0,
              action: '＋ 250 ml',
              onTap: () => go(c, const WaterScreen()),
              onAction: () => _addWater(c),
            ),
          ),
        ],
      ),
      const SizedBox(height: kGapMd),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: _DailyBalanceCard(
              icon: Icons.directions_walk_outlined,
              value: store.withThousands(store.steps),
              detail: 'Steps · of ${store.withThousands(stepGoal)}',
              progress: stepGoal > 0 ? store.steps / stepGoal : 0,
              action: '＋ Log activity',
              onTap: () => showLogActivity(c),
              onAction: () => showLogActivity(c),
            ),
          ),
          const SizedBox(width: kGapMd),
          Expanded(
            child: _DailyBalanceCard(
              icon: Icons.monitor_weight_outlined,
              value: !weightEstimate.hasAnchor
                  ? 'Not logged'
                  : store.wt(weightEstimate.currentWeightKg),
              detail: 'Current weight',
              progress: store.goalProgress(),
              action: '＋ Log weight',
              onTap: () => go(c, const WeightScreen()),
              onAction: () => go(c, const WeightScreen()),
            ),
          ),
        ],
      ),
      const SizedBox(height: kGapXl),
    ]);
  });

  Widget _workoutHero(
    BuildContext context, {
    required Map? scheduled,
    required Map? completed,
    required Map? resumeRoutine,
  }) {
    final routine = scheduled == null ? null : store.routine(scheduled['r']);
    final rawExercises = routine?['ex'];
    final exercises = rawExercises is List ? rawExercises : const [];
    final weeklyCount = store.wkCount(0);
    final weeklyGoal = store.weeklyWorkoutGoal;
    final titleColor = Colors.white;
    const detailColor = Colors.white70;

    Widget chip(String text) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white12,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: titleColor,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );

    final Widget content;
    if (resumeRoutine != null) {
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _HeroEyebrow('TODAY\'S WORKOUT'),
          const SizedBox(height: kGapSm),
          Text(
            '${resumeRoutine['name'] ?? 'Workout'}',
            style: TextStyle(
              color: titleColor,
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
          Text('Workout in progress', style: TextStyle(color: detailColor)),
          const SizedBox(height: kGapMd),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => go(context, WorkoutScreen(resumeRoutine)),
              icon: const Icon(Icons.play_arrow),
              label: const Text('Resume workout'),
              style: _heroPrimaryButton(),
            ),
          ),
        ],
      );
    } else if (completed != null) {
      final name = (completed['n'] ?? 'Workout').toString();
      final minutes = completed['min'] ?? 0;
      final done = completed['ex'] ?? 0;
      final total = completed['totalEx'] ?? done;
      final calories = completed['kc'] ?? 0;
      final sets = completed['sets'] ?? 0;
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _HeroEyebrow('TODAY\'S WORKOUT'),
          const SizedBox(height: kGapSm),
          Text(
            '✓ $name done',
            style: TextStyle(
              color: titleColor,
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(
            'Great work. $minutes min · $done of $total exercises',
            style: TextStyle(color: detailColor),
          ),
          const SizedBox(height: kGapMd),
          Wrap(
            spacing: kGapSm,
            runSpacing: kGapSm,
            children: [chip('🔥 $calories kcal'), chip('$sets sets')],
          ),
          const SizedBox(height: kGapMd),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () => widget.goTo(3),
              style: _heroSecondaryButton(),
              child: const Text('View summary'),
            ),
          ),
        ],
      );
    } else if (scheduled != null && routine != null) {
      final time = _formatScheduleTime('${scheduled['t'] ?? ''}');
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _HeroEyebrow('TODAY\'S WORKOUT'),
          const SizedBox(height: kGapSm),
          Text(
            '${routine['name'] ?? 'Workout'}',
            style: TextStyle(
              color: titleColor,
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
          Text('Scheduled for $time', style: TextStyle(color: detailColor)),
          const SizedBox(height: kGapMd),
          Wrap(
            spacing: kGapSm,
            runSpacing: kGapSm,
            children: [
              chip('${exercises.length} exercises'),
              chip('~${routineMinutes(exercises)} min'),
              chip('${routine['type'] ?? 'Strength'}'),
            ],
          ),
          const SizedBox(height: kGapMd),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => go(context, WorkoutScreen(routine)),
              icon: const Icon(Icons.play_arrow),
              label: const Text('Start workout'),
              style: _heroPrimaryButton(),
            ),
          ),
        ],
      );
    } else if (scheduled != null) {
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _HeroEyebrow('TODAY\'S WORKOUT'),
          const SizedBox(height: kGapSm),
          Text(
            'Workout unavailable',
            style: TextStyle(
              color: titleColor,
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(
            'This scheduled routine was removed.',
            style: TextStyle(color: detailColor),
          ),
          const SizedBox(height: kGapMd),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () => widget.goTo(2),
              style: _heroSecondaryButton(),
              child: const Text('Go to schedule'),
            ),
          ),
        ],
      );
    } else {
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _HeroEyebrow('TODAY\'S WORKOUT'),
          const SizedBox(height: kGapSm),
          Text(
            'Nothing planned yet',
            style: TextStyle(
              color: titleColor,
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(
            'Pick a routine to do today, or schedule it for later.',
            style: TextStyle(color: detailColor),
          ),
          const SizedBox(height: kGapMd),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => widget.goTo(1),
              style: _heroPrimaryButton(),
              child: const Text('Choose a routine'),
            ),
          ),
          const SizedBox(height: kGapSm),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () => widget.goTo(2),
              style: _heroSecondaryButton(),
              child: const Text('Schedule a workout'),
            ),
          ),
        ],
      );
    }

    return Container(
      padding: const EdgeInsets.all(kGapLg),
      decoration: BoxDecoration(
        color: kDk,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: kDk.withValues(alpha: .16),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          content,
          const SizedBox(height: kGapLg),
          Text(
            'This week · $weeklyCount / $weeklyGoal workouts',
            style: TextStyle(
              color: titleColor,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: kGapSm),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: progressOf(weeklyCount / weeklyGoal),
              minHeight: 8,
              color: kMint,
              backgroundColor: Colors.white24,
            ),
          ),
        ],
      ),
    );
  }

  ButtonStyle _heroPrimaryButton() => FilledButton.styleFrom(
    backgroundColor: kMint,
    foregroundColor: kInk,
    minimumSize: const Size.fromHeight(52),
    textStyle: const TextStyle(fontWeight: FontWeight.w800),
  );

  ButtonStyle _heroSecondaryButton() => OutlinedButton.styleFrom(
    foregroundColor: Colors.white,
    side: const BorderSide(color: Colors.white70),
    minimumSize: const Size.fromHeight(48),
    textStyle: const TextStyle(fontWeight: FontWeight.w700),
  );

  String _formatScheduleTime(String raw) {
    final parts = raw.split(':');
    if (parts.length != 2) return raw;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null || hour < 0 || hour > 23) return raw;
    final displayHour = hour % 12 == 0 ? 12 : hour % 12;
    return '$displayHour:${minute.toString().padLeft(2, '0')} ${hour < 12 ? 'AM' : 'PM'}';
  }
}

class _HeroEyebrow extends StatelessWidget {
  final String label;
  const _HeroEyebrow(this.label);

  @override
  Widget build(BuildContext context) => Text(
    label,
    style: TextStyle(
      color: kMint,
      fontSize: 11,
      fontWeight: FontWeight.w800,
      letterSpacing: .8,
    ),
  );
}

class _DailyBalanceCard extends StatefulWidget {
  final IconData icon;
  final String value;
  final String detail;
  final double progress;
  final String action;
  final VoidCallback onTap;
  final VoidCallback onAction;

  const _DailyBalanceCard({
    required this.icon,
    required this.value,
    required this.detail,
    required this.progress,
    required this.action,
    required this.onTap,
    required this.onAction,
  });

  @override
  State<_DailyBalanceCard> createState() => _DailyBalanceCardState();
}

class _DailyBalanceCardState extends State<_DailyBalanceCard> {
  bool _highlighted = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final dark = isDark(context);
    final accent = dark ? const Color(0xFF2FC2AD) : const Color(0xFF007A6C);
    final actionBackground = dark
        ? const Color(0xFF17413C)
        : const Color(0xFFCDF0E6);
    final actionForeground = dark
        ? const Color(0xFF7FE3D1)
        : const Color(0xFF005A50);
    const radius = 10.0;
    return AnimatedScale(
      scale: _highlighted ? .98 : 1,
      duration: const Duration(milliseconds: 100),
      child: Container(
        height: 172,
        decoration: BoxDecoration(
          color: accent,
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: accent, width: 2),
          boxShadow: [
            BoxShadow(
              color: kDk.withValues(alpha: .12),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(radius - 2),
            child: Column(
              children: [
                Expanded(
                  child: Material(
                    color: colorScheme.surface,
                    child: Semantics(
                      button: true,
                      label: '${widget.detail}, ${widget.value}',
                      child: InkWell(
                        onTap: widget.onTap,
                        onHighlightChanged: (value) =>
                            setState(() => _highlighted = value),
                        focusColor: dark
                            ? accent.withValues(alpha: .2)
                            : accent.withValues(alpha: .1),
                        highlightColor: dark
                            ? accent.withValues(alpha: .18)
                            : accent.withValues(alpha: .08),
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(widget.icon, color: accent, size: 21),
                                  const Spacer(),
                                  Icon(
                                    Icons.chevron_right,
                                    color: colorScheme.onSurfaceVariant,
                                    size: 22,
                                  ),
                                ],
                              ),
                              const SizedBox(height: kGapXs),
                              Text(
                                widget.value,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: colorScheme.onSurface,
                                  fontSize: 21,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                widget.detail,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                              ),
                              const Spacer(),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(99),
                                child: LinearProgressIndicator(
                                  value: progressOf(widget.progress),
                                  minHeight: 6,
                                  color: accent,
                                  backgroundColor: dark ? kLineDark : kLn,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Container(height: 2, color: accent),
                Semantics(
                  button: true,
                  label: widget.action,
                  child: Material(
                    color: actionBackground,
                    child: InkWell(
                      onTap: widget.onAction,
                      onHighlightChanged: (value) =>
                          setState(() => _highlighted = value),
                      focusColor: dark
                          ? Colors.white.withValues(alpha: .12)
                          : Colors.white.withValues(alpha: .4),
                      highlightColor: dark
                          ? Colors.white.withValues(alpha: .1)
                          : Colors.white.withValues(alpha: .3),
                      child: SizedBox(
                        height: 46,
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                widget.action,
                                style: TextStyle(
                                  color: actionForeground,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Container(height: 3, color: accent),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
