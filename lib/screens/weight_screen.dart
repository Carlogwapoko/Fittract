import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/daily_movement_tracking_service.dart';
import '../services/weight_estimator.dart';
import '../services/weight_planner.dart';
import '../store/store.dart';
import '../theme/app_palette.dart';
import '../widgets/shared_widgets.dart';

import '../widgets/ai_coach_card.dart';

class WeightScreen extends StatefulWidget {
  const WeightScreen({super.key});

  @override
  State<WeightScreen> createState() => _WeightState();
}

class _WeightState extends State<WeightScreen> {
  static const _rangeDays = [7, 30, 90];
  static const _rangeLabels = ['this week', 'this month', 'last 3 months'];

  int _range = 1;
  bool _dailyDetailsExpanded = false;
  String? _expandedDetailDate;
  Timer? _goalSaveDebounce;
  late final _startingWeight = TextEditingController();
  late final _manualWeight = TextEditingController();
  late final _targetWeight = TextEditingController(
    text: store.goalField('w') > 0
        ? store.goalField('w').toStringAsFixed(1)
        : '',
  );
  late final _targetDate = TextEditingController(
    text: store.goal['d']?.toString() ?? '',
  );

  @override
  void initState() {
    super.initState();
    _targetWeight.addListener(_refreshPace);
    _targetDate.addListener(_refreshPace);
    _startingWeight.addListener(_refreshFields);
    _manualWeight.addListener(_refreshFields);
  }

  void _refreshPace() {
    if (mounted) setState(() {});
    _goalSaveDebounce?.cancel();
    _goalSaveDebounce = Timer(const Duration(milliseconds: 600), () {
      _goalSaveDebounce = null;
      _saveValidGoalFields();
    });
  }

  void _refreshFields() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    if (_goalSaveDebounce?.isActive ?? false) {
      _goalSaveDebounce?.cancel();
      _goalSaveDebounce = null;
      _saveValidGoalFields();
    }
    _startingWeight.dispose();
    _manualWeight.dispose();
    _targetWeight.dispose();
    _targetDate.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: dailyMovementTracking,
    builder: (context, _) => live((c) {
      final series = WeightEstimator.calculate(store.d);
      final todayDate = DateTime.now();
      final todayKey = today();
      final todayEntry = _findDay(series.days, todayKey);
      final currentKg = todayEntry?.kg ?? series.currentWeightKg;
      final visibleDays = series.days
          .where(
            (day) => !day.date.isBefore(
              DateTime(
                todayDate.year,
                todayDate.month,
                todayDate.day,
              ).subtract(Duration(days: _rangeDays[_range] - 1)),
            ),
          )
          .toList();
      final change = _rangeChange(visibleDays);
      final age = store.d['age'];
      final height = store.d['h'];

      return screen([
        hdr(c, 'Weight & goals', 'Stronger, steadily.', back: true),
        if (!series.hasAnchor)
          _setupCard(c)
        else ...[
          _estimatedCard(
            c,
            series: series,
            currentKg: currentKg,
            todayDate: todayDate,
            visibleDays: visibleDays,
            change: change,
            todayEntry: todayEntry,
            profileIsIncomplete: age == null || height == null,
          ),
          _manualWeighInCard(c),
        ],
        h3('Weight goals'),
        _goalsCard(c, series.hasAnchor ? currentKg : 0),
        h3('AI coach'),
        AiCoachCard(currentKg: series.hasAnchor ? currentKg : 0),
      ]);
    }),
  );

  WeightEstimateDay? _findDay(List<WeightEstimateDay> days, String key) {
    for (final day in days) {
      if (day.dateKey == key) return day;
    }
    return null;
  }

  double? _rangeChange(List<WeightEstimateDay> days) {
    final complete = days.where((day) => day.complete).toList();
    if (complete.length < 2) return null;
    return complete.last.kg - complete.first.kg;
  }

  Widget _setupCard(BuildContext context) => card(
    color: tintOf(context),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Enter your starting weight',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurface,
            fontSize: 20,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: kGapSm),
        const Text(
          'One time only. After this, FitTrack estimates your weight automatically from the calories you eat and burn.',
          style: muted,
        ),
        const SizedBox(height: kGapLg),
        _weightField(controller: _startingWeight, label: 'Starting weight'),
        const SizedBox(height: kGapMd),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: FilledButton(
            onPressed: _validWeight(_startingWeight.text)
                ? () => _startTracking(context)
                : null,
            child: const Text('Start tracking'),
          ),
        ),
      ],
    ),
  );

  Widget _estimatedCard(
    BuildContext context, {
    required WeightEstimateSeries series,
    required double currentKg,
    required DateTime todayDate,
    required List<WeightEstimateDay> visibleDays,
    required double? change,
    required WeightEstimateDay? todayEntry,
    required bool profileIsIncomplete,
  }) {
    final colors = Theme.of(context).colorScheme;
    final hasCurrentWeight = currentKg > 0;
    final changeColor = colors.onSurfaceVariant;
    final pillBackground = colors.surfaceContainerHighest;
    final dateText = DateFormat('EEE, MMM d').format(todayDate);
    final dailyDetails = visibleDays.reversed.toList();
    final chartLabel = _chartDescription(visibleDays);
    final showTrendChart = WeightEstimator.hasEnoughTrendDays(visibleDays);

    return card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(dateText, style: muted.copyWith(fontSize: 13)),
          const SizedBox(height: kGapXs),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Semantics(
                  label: todayEntry?.manuallyWeighed == true
                      ? 'Manually weighed ${currentKg.toStringAsFixed(1)} kg'
                      : 'Estimated weight ${currentKg.toStringAsFixed(1)} kg',
                  child: Text(
                    hasCurrentWeight
                        ? '${currentKg.toStringAsFixed(1)} kg'
                        : 'Estimate unavailable',
                    style: const TextStyle(
                      fontSize: 40,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -1,
                    ),
                  ),
                ),
              ),
              if (todayEntry != null &&
                  todayEntry.complete &&
                  !todayEntry.anchor &&
                  !todayEntry.manuallyWeighed)
                tag('AI ESTIMATE'),
            ],
          ),
          const SizedBox(height: kGapMd),
          if (change != null)
            Semantics(
              label:
                  '${change < 0 ? 'Down' : 'Up'} ${change.abs().toStringAsFixed(1)} kilograms ${_rangeLabels[_range]}',
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: kGapMd,
                  vertical: kGapSm,
                ),
                decoration: BoxDecoration(
                  color: pillBackground,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${change < 0 ? '\u2212' : '+'}${change.abs().toStringAsFixed(1)} kg \u00b7 ${_rangeLabels[_range]}',
                  style: TextStyle(
                    color: changeColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          const SizedBox(height: kGapLg),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<int>(
              showSelectedIcon: false,
              style: const ButtonStyle(
                minimumSize: WidgetStatePropertyAll(Size(0, 44)),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.standard,
              ),
              segments: const [
                ButtonSegment(value: 0, label: Text('1 week')),
                ButtonSegment(value: 1, label: Text('1 month')),
                ButtonSegment(value: 2, label: Text('3 months')),
              ],
              selected: {_range},
              onSelectionChanged: (selected) =>
                  setState(() => _range = selected.first),
            ),
          ),
          const SizedBox(height: kGapLg),
          if (!showTrendChart)
            SizedBox(
              height: 185,
              child: Center(
                child: Text(
                  'Log meals or exercise on at least 2 days in this range to see your trend',
                  style: muted,
                ),
              ),
            )
          else
            _WeightChart(
              days: visibleDays,
              description: chartLabel,
              color: primaryOf(context),
            ),
          const SizedBox(height: kGapMd),
          if (profileIsIncomplete)
            const Padding(
              padding: EdgeInsets.only(bottom: kGapMd),
              child: Text(
                'Add age and height in Profile to personalize your calorie-burn estimate.',
                style: muted,
              ),
            ),
          Text(
            'Estimated from calories you eat minus calories you burn. About 7,700 kcal is roughly 1 kg. Resting burn is used only for this estimate and is not counted as exercise.',
            style: muted.copyWith(fontSize: 12),
          ),
          const SizedBox(height: kGapSm),
          Theme(
            data: Theme.of(context).copyWith(
              dividerColor: Colors.transparent,
              splashColor: tintOf(context),
            ),
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(bottom: kGapSm),
              initiallyExpanded: _dailyDetailsExpanded,
              onExpansionChanged: (expanded) =>
                  setState(() => _dailyDetailsExpanded = expanded),
              title: const Text(
                'Daily details',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              children: [
                SizedBox(
                  height: min(420.0, dailyDetails.length * 82.0),
                  child: ListView.builder(
                    itemCount: dailyDetails.length,
                    itemBuilder: (context, index) => _dailyDetailRow(
                      context,
                      day: dailyDetails[index],
                      allDays: series.days,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _dailyDetailRow(
    BuildContext context, {
    required WeightEstimateDay day,
    required List<WeightEstimateDay> allDays,
  }) {
    final isToday = day.dateKey == today();
    final isExpanded = _expandedDetailDate == day.dateKey;
    final dayIndex = allDays.indexWhere(
      (entry) => entry.dateKey == day.dateKey,
    );
    final previous = dayIndex > 0 ? allDays[dayIndex - 1] : null;
    final dailyChange = previous == null ? null : day.kg - previous.kg;
    final colors = Theme.of(context).colorScheme;
    final todayColor = tintOf(context);
    final primary = primaryOf(context);
    final activityColor = appTokensOf(context).activity;

    return Column(
      children: [
        Material(
          color: isToday ? todayColor : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: isToday
                ? null
                : () => setState(
                    () => _expandedDetailDate = isExpanded ? null : day.dateKey,
                  ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          DateFormat('EEE, MMM d').format(day.date),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        if (isToday)
                          Text(
                            'TODAY',
                            style: TextStyle(
                              color: primary,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              letterSpacing: .5,
                            ),
                          )
                        else if (isExpanded)
                          Text('Tap to collapse', style: muted),
                      ],
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: _dailyValue(
                      store.withThousands(day.caloriesConsumed ?? 0),
                      'consumed',
                      primary,
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: _dailyValue(
                      store.withThousands(day.activeCaloriesBurned),
                      'burned',
                      activityColor,
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '${day.kg.toStringAsFixed(1)} kg',
                          maxLines: 1,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          dailyChange == null
                              ? (day.manuallyWeighed
                                    ? 'weighed in'
                                    : 'estimate')
                              : '${dailyChange >= 0 ? '+' : ''}${dailyChange.toStringAsFixed(2)} kg',
                          maxLines: 1,
                          style: TextStyle(
                            color: colors.onSurfaceVariant,
                            fontSize: 10,
                          ),
                        ),
                        if (dailyChange != null)
                          Text(
                            !day.hasMeals && !day.manuallyWeighed
                                ? 'carried over'
                                : day.manuallyWeighed
                                ? 'weighed in'
                                : 'estimate',
                            maxLines: 1,
                            style: muted.copyWith(fontSize: 9),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (isExpanded) _dailyRecordDetails(day, primary, activityColor),
      ],
    );
  }

  Widget _dailyValue(String value, String label, Color color) => Column(
    crossAxisAlignment: CrossAxisAlignment.end,
    children: [
      Text(
        value,
        maxLines: 1,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
      Text(label, style: muted.copyWith(fontSize: 9)),
      Text('kcal', style: muted.copyWith(fontSize: 9)),
    ],
  );

  Widget _dailyRecordDetails(
    WeightEstimateDay day,
    Color primary,
    Color activityColor,
  ) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 1),
        const SizedBox(height: 8),
        _recordLine(
          'Resting energy',
          '${store.withThousands(day.restingCalories)} kcal',
        ),
        _recordLine(
          'Other activity',
          '${store.withThousands(day.activityCalories)} kcal',
        ),
        _recordLine('Steps', '${store.withThousands(day.stepCalories)} kcal'),
        _recordLine(
          'Exercise',
          '${store.withThousands(day.caloriesBurned)} kcal',
        ),
        _recordLine(
          'Total burned',
          '${store.withThousands(day.totalBurnedCalories)} kcal',
        ),
        if (day.calorieBalance != null)
          _recordLine(
            'Calorie balance',
            '${day.calorieBalance! >= 0 ? '+' : ''}${store.withThousands(day.calorieBalance!)} kcal',
          )
        else
          _recordLine('Calorie balance', '--'),
        _recordLine(
          'Daily calorie target',
          '${store.withThousands((store.nutritionGoals['calories'] as num).toInt())} kcal',
        ),
        const SizedBox(height: 8),
        Text(
          'Meals',
          style: TextStyle(color: primary, fontWeight: FontWeight.w700),
        ),
        if (day.meals.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 4),
            child: Text('No meals logged.', style: muted),
          )
        else
          for (final meal in day.meals)
            _recordLine(
              '${meal['n'] ?? meal['desc'] ?? 'Meal'}',
              '${store.withThousands(_recordCalories(meal['k']))} kcal',
            ),
        const SizedBox(height: 8),
        Text(
          'Activities',
          style: TextStyle(color: activityColor, fontWeight: FontWeight.w700),
        ),
        if (day.activities.isEmpty && day.workouts.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 4),
            child: Text('No activities logged.', style: muted),
          )
        else
          for (final activity in day.activities)
            _recordLine(
              '${activity['n'] ?? 'Activity'} · ${activity['min'] ?? 0} min · ${activity['km'] ?? 0} km',
              '${store.withThousands(_recordCalories(activity['kc']))} kcal',
            ),
        for (final workout in day.workouts)
          _recordLine(
            '${workout['n'] ?? 'Workout'} · ${workout['min'] ?? 0} min',
            '${store.withThousands(_recordCalories(workout['kc']))} kcal',
          ),
      ],
    ),
  );

  Widget _recordLine(String title, String calories) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      children: [
        Expanded(child: Text(title, style: muted)),
        Text(calories, style: const TextStyle(fontWeight: FontWeight.w600)),
      ],
    ),
  );

  int _recordCalories(Object? value) =>
      value is num && value.isFinite ? value.round().clamp(0, 1000000) : 0;

  String _chartDescription(List<WeightEstimateDay> days) {
    if (days.isEmpty) {
      return 'No weight estimates are available for this range.';
    }
    final entries = days
        .map(
          (day) =>
              '${DateFormat('MMM d').format(day.date)}: ${day.kg.toStringAsFixed(1)} kilograms${day.complete
                  ? ''
                  : day.activeCaloriesBurned > 0
                  ? ', activity-only estimate'
                  : ', no meal or exercise logged'}',
        )
        .join('; ');
    return 'Estimated weight trend. $entries. Days without meal or activity logs carry the previous estimate.';
  }

  Widget _manualWeighInCard(BuildContext context) => card(
    color: tintOf(context),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Weighed yourself? (optional)',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: kGapXs),
        const Text(
          'Enter your real weight to make the estimate more accurate.',
          style: muted,
        ),
        const SizedBox(height: kGapLg),
        _weightField(controller: _manualWeight, label: 'Your weight today'),
        const SizedBox(height: kGapMd),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: FilledButton.icon(
            onPressed: _validWeight(_manualWeight.text)
                ? () => _saveWeight(context)
                : null,
            icon: const Icon(Icons.save_outlined),
            label: const Text('Save weight'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(50),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ),
      ],
    ),
  );

  Widget _weightField({
    required TextEditingController controller,
    required String label,
  }) => TextField(
    controller: controller,
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    textInputAction: TextInputAction.done,
    decoration: InputDecoration(labelText: label, suffixText: 'kg'),
  );

  bool _validWeight(String text) {
    final value = double.tryParse(text.trim());
    return value != null && value.isFinite && value >= 20 && value <= 300;
  }

  Widget _goalsCard(BuildContext context, double currentKg) {
    final weeklyGoal = store.weeklyWorkoutGoal;
    final pace = _paceMessage(currentKg);
    final colors = Theme.of(context).colorScheme;

    return card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _weightField(controller: _targetWeight, label: 'Target weight'),
          const SizedBox(height: kGapMd),
          TextField(
            controller: _targetDate,
            readOnly: true,
            onTap: () => _pickGoalDate(context),
            decoration: InputDecoration(
              labelText: 'Target date',
              suffixIcon: _targetDate.text.isEmpty
                  ? const Icon(Icons.arrow_drop_down)
                  : IconButton(
                      tooltip: 'Clear target date',
                      onPressed: () => setState(() => _targetDate.clear()),
                      icon: const Icon(Icons.close),
                    ),
            ),
          ),
          const SizedBox(height: kGapMd),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(kGapMd),
            decoration: BoxDecoration(
              color: tintOf(context),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(pace.message, style: const TextStyle(height: 1.4)),
                if (pace.warning != null) ...[
                  const SizedBox(height: kGapSm),
                  Text(
                    pace.warning!,
                    style: TextStyle(
                      color: colors.onSurfaceVariant,
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                ],
                if (pace.earliestSafeDate != null) ...[
                  const SizedBox(height: kGapSm),
                  TextButton(
                    onPressed: () {
                      _targetDate.text = isoOf(pace.earliestSafeDate!);
                    },
                    child: const Text('Use earliest safe date'),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: kGapLg),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: colors.outlineVariant),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.calendar_view_week_outlined,
                  color: primaryOf(context),
                ),
                const SizedBox(width: kGapMd),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Weekly workouts',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      Text('Your activity target', style: muted),
                    ],
                  ),
                ),
                SizedBox(
                  width: 48,
                  height: 48,
                  child: IconButton.filledTonal(
                    tooltip: 'Decrease weekly workouts',
                    onPressed: weeklyGoal <= 1
                        ? null
                        : () {
                            store.ensureGoal()['wk'] = max(1, weeklyGoal - 1);
                            store.save();
                          },
                    icon: const Icon(Icons.remove),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: kGapMd),
                  child: Semantics(
                    label: '$weeklyGoal workouts per week',
                    child: Text(
                      '$weeklyGoal',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                      ),
                    ),
                  ),
                ),
                SizedBox(
                  width: 48,
                  height: 48,
                  child: IconButton.filledTonal(
                    tooltip: 'Increase weekly workouts',
                    onPressed: weeklyGoal >= 7
                        ? null
                        : () {
                            store.ensureGoal()['wk'] = min(7, weeklyGoal + 1);
                            store.save();
                          },
                    icon: const Icon(Icons.add),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: kGapLg),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton.icon(
              onPressed: () => _saveGoals(context),
              icon: const Icon(Icons.flag_outlined),
              label: const Text('Save goals'),
            ),
          ),
        ],
      ),
    );
  }

  ({String message, String? warning, DateTime? earliestSafeDate}) _paceMessage(
    double currentKg,
  ) {
    final target = double.tryParse(_targetWeight.text.trim());
    if (target == null || !target.isFinite || target < 20 || target > 300) {
      return (
        message: 'Enter a target weight to see your pace.',
        warning: null,
        earliestSafeDate: null,
      );
    }
    if (currentKg < 20 || currentKg > 300) {
      return (
        message: 'Start tracking your weight to see your projected date.',
        warning: null,
        earliestSafeDate: null,
      );
    }

    final age = store.d['age'];
    final height = store.d['h'];
    if (age is! num ||
        height is! num ||
        age < 13 ||
        age > 100 ||
        height < 100 ||
        height > 250) {
      return (
        message:
            'Add your age and height in Profile to see your projected date.',
        warning: null,
        earliestSafeDate: null,
      );
    }
    final sex = store.d['sex'];
    final activity = store.d['activityLevel'];
    final input = WeightPlanInput(
      currentKg: currentKg,
      targetKg: target,
      ageYears: age.toInt(),
      heightCm: height.toDouble(),
      sex: sex is String ? sex : 'other',
      activityLevel: activity is String ? activity : 'light',
      workoutsPerWeek: store.weeklyWorkoutGoal,
      targetDate: DateTime.tryParse(_targetDate.text.trim()),
    );
    final plan = WeightPlanner.build(input);
    final warning = plan.warnings.isEmpty ? null : plan.warnings.join(' ');
    final earliestSafeDate = WeightPlanner.hasUnsafeTargetDate(plan)
        ? plan.projectedDate
        : null;
    if (plan.goalType == WeightGoalType.maintain) {
      return (
        message: 'You are at your target. Keep it steady.',
        warning: warning,
        earliestSafeDate: null,
      );
    }

    final projected = plan.projectedDate;
    if (projected == null) {
      return (
        message: 'Choose a target date to see your required pace.',
        warning: warning,
        earliestSafeDate: null,
      );
    }
    final requiredRate = plan.requestedWeeklyChangeKg;
    final message = requiredRate == null
        ? 'At a safe rate of ${plan.weeklyChangeKg.abs().toStringAsFixed(2)} kg per week, your plan reaches ${target.toStringAsFixed(1)} kg around ${WeightPlanner.formatDate(projected)}.'
        : 'Reaching ${target.toStringAsFixed(1)} kg by your date requires ${requiredRate.toStringAsFixed(2)} kg per week. Your plan reaches it around ${WeightPlanner.formatDate(projected)}.';
    return (
      message: message,
      warning: warning,
      earliestSafeDate: earliestSafeDate,
    );
  }

  Future<void> _pickGoalDate(BuildContext context) async {
    final now = DateTime.now();
    final existing = DateTime.tryParse(_targetDate.text);
    final picked = await showDatePicker(
      context: context,
      initialDate: existing != null && !existing.isBefore(now) ? existing : now,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 20),
    );
    if (picked == null || !mounted) return;
    setState(() => _targetDate.text = isoOf(picked));
  }

  WeightPlan? _planForGoalDate(double target, DateTime date) {
    final series = WeightEstimator.calculate(store.d);
    final currentKg = series.currentWeightKg;
    final age = store.d['age'];
    final height = store.d['h'];
    if (!series.hasAnchor ||
        currentKg < 20 ||
        currentKg > 300 ||
        age is! num ||
        age < 13 ||
        age > 100 ||
        height is! num ||
        height < 100 ||
        height > 250) {
      return null;
    }

    final sex = store.d['sex'];
    final activity = store.d['activityLevel'];
    final input = WeightPlanInput(
      currentKg: currentKg,
      targetKg: target,
      ageYears: age.toInt(),
      heightCm: height.toDouble(),
      sex: sex is String ? sex : 'other',
      activityLevel: activity is String ? activity : 'light',
      workoutsPerWeek: store.weeklyWorkoutGoal,
      targetDate: date,
    );
    try {
      return WeightPlanner.build(input);
    } on ArgumentError {
      return null;
    }
  }

  bool _isTodayOrFutureDate(DateTime date) {
    final todayDate = DateTime.now();
    return !DateTime(
      date.year,
      date.month,
      date.day,
    ).isBefore(DateTime(todayDate.year, todayDate.month, todayDate.day));
  }

  String? _unsafeDateMessage(double? target, DateTime date) {
    if (target == null) return null;
    final plan = _planForGoalDate(target, date);
    if (plan == null) return null;
    return WeightPlanner.unsafeTargetDateMessage(
      requestedWeeklyChangeKg: plan.requestedWeeklyChangeKg,
      safeWeeklyChangeKg: WeightPlanner.safeWeeklyRate(plan.goalType),
      projectedDate: plan.projectedDate,
    );
  }

  void _saveValidGoalFields() {
    final target = double.tryParse(_targetWeight.text.trim());
    final goalTarget =
        target != null && target.isFinite && target >= 20 && target <= 300
        ? target
        : store.goalField('w');
    final date = _targetDate.text.trim();
    var changed = false;
    if (target != null && target.isFinite && target >= 20 && target <= 300) {
      store.ensureGoal()['w'] = target;
      changed = true;
    }
    if (date.isEmpty && store.goal['d'] != '') {
      store.ensureGoal()['d'] = '';
      changed = true;
    } else if (date.isNotEmpty) {
      final parsedDate = DateTime.tryParse(date);
      if (parsedDate != null) {
        final dateIsSafe =
            _isTodayOrFutureDate(parsedDate) &&
            _unsafeDateMessage(goalTarget, parsedDate) == null;
        if (dateIsSafe) {
          store.ensureGoal()['d'] = date;
          changed = true;
        } else if (store.goal['d'] != '') {
          store.ensureGoal()['d'] = '';
          changed = true;
        }
      }
    }
    if (changed) store.save();
  }

  void _startTracking(BuildContext context) {
    final weight = double.tryParse(_startingWeight.text.trim());
    if (weight == null || weight < 20 || weight > 300) return;
    store.ensureGoal()['sw'] = weight;
    store.d['weightAnchorDate'] = today();
    final weights = store.d['weights'] as List;
    weights.removeWhere(
      (entry) => entry is List && entry.isNotEmpty && entry.first == today(),
    );
    weights.add([today(), weight]);
    store.save();
    _startingWeight.clear();
    snack(context, 'Tracking started. Your estimate updates every day.');
  }

  void _saveWeight(BuildContext context) {
    final weight = double.tryParse(_manualWeight.text.trim());
    if (weight == null || weight < 20 || weight > 300) return;
    final weights = store.d['weights'] as List;
    weights.removeWhere(
      (entry) => entry is List && entry.isNotEmpty && entry.first == today(),
    );
    weights.add([today(), weight]);
    store.save();
    _manualWeight.clear();
    snack(context, 'Weight saved. Your estimate is now calibrated.');
  }

  void _saveGoals(BuildContext context) {
    final targetText = _targetWeight.text.trim();
    final target = targetText.isEmpty ? null : double.tryParse(targetText);
    if (targetText.isNotEmpty &&
        (target == null || !target.isFinite || target < 20 || target > 300)) {
      snack(context, 'Enter a target weight between 20 and 300 kg.');
      return;
    }
    final date = _targetDate.text.trim();
    if (date.isNotEmpty && DateTime.tryParse(date) == null) {
      snack(context, 'Choose a valid target date.');
      return;
    }
    final parsedDate = date.isEmpty ? null : DateTime.parse(date);
    final dateIsAllowed =
        parsedDate == null || _isTodayOrFutureDate(parsedDate);
    final unsafeDateMessage = parsedDate == null
        ? null
        : _unsafeDateMessage(target, parsedDate);
    store.ensureGoal()['w'] = target ?? 0.0;
    if (dateIsAllowed && unsafeDateMessage == null) {
      store.ensureGoal()['d'] = date;
    } else {
      store.ensureGoal()['d'] = '';
    }
    store.save();
    if (!dateIsAllowed) {
      snack(
        context,
        'Target weight saved. Choose a future date; this date was not saved.',
      );
    } else if (unsafeDateMessage != null) {
      snack(
        context,
        'Target weight saved. $unsafeDateMessage Use the earliest safe date instead.',
      );
    } else {
      snack(
        context,
        parsedDate != null && DateUtils.isSameDay(parsedDate, DateTime.now())
            ? 'Goals saved. Choose a future date for a weight-change goal.'
            : 'Goals saved.',
      );
    }
  }
}

class _WeightChart extends StatelessWidget {
  final List<WeightEstimateDay> days;
  final String description;
  final Color color;

  const _WeightChart({
    required this.days,
    required this.description,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final values = days.map((day) => day.kg).toList();
    final low = values.reduce(min);
    final high = values.reduce(max);
    final spread = max(.5, high - low);
    final minY = low - spread * .2;
    final maxY = high + spread * .2;
    final labelIndices = _dateLabelIndices(days.length);

    return Semantics(
      label: description,
      child: ExcludeSemantics(
        child: Column(
          children: [
            SizedBox(
              height: 144,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: 52,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${maxY.toStringAsFixed(1)} kg', style: muted),
                        Text(
                          '${((maxY + minY) / 2).toStringAsFixed(1)} kg',
                          style: muted,
                        ),
                        Text('${minY.toStringAsFixed(1)} kg', style: muted),
                      ],
                    ),
                  ),
                  Expanded(
                    child: CustomPaint(
                      painter: _WeightChartPainter(
                        days: days,
                        color: color,
                        gridColor: Theme.of(context).colorScheme.outlineVariant,
                        incompleteColor: Theme.of(context)
                            .colorScheme
                            .onSurfaceVariant
                            .withValues(alpha: .38),
                        minY: minY,
                        maxY: maxY,
                        todayKey: today(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: kGapSm),
            Row(
              children: [
                const SizedBox(width: 52),
                Expanded(
                  child: SizedBox(
                    height: 18,
                    child: Stack(
                      children: [
                        for (final index in labelIndices)
                          Positioned.fill(
                            child: Align(
                              alignment: index == 0
                                  ? Alignment.centerLeft
                                  : index == days.length - 1
                                  ? Alignment.centerRight
                                  : Alignment(
                                      2 * index / (days.length - 1) - 1,
                                      0,
                                    ),
                              child: Text(
                                DateFormat('MMM d').format(days[index].date),
                                style: muted,
                                maxLines: 1,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  List<int> _dateLabelIndices(int count) {
    if (count <= 1) return [0];
    final labelCount = count > 14 ? 5 : 3;
    return {
      for (var index = 0; index < labelCount; index++)
        (index * (count - 1) / (labelCount - 1)).round(),
    }.toList();
  }
}

class _WeightChartPainter extends CustomPainter {
  final List<WeightEstimateDay> days;
  final Color color;
  final Color gridColor;
  final Color incompleteColor;
  final double minY;
  final double maxY;
  final String todayKey;

  const _WeightChartPainter({
    required this.days,
    required this.color,
    required this.gridColor,
    required this.incompleteColor,
    required this.minY,
    required this.maxY,
    required this.todayKey,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (var index = 0; index < 3; index++) {
      final y = index * size.height / 2;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    if (days.isEmpty) return;

    final points = <Offset>[];
    for (var index = 0; index < days.length; index++) {
      final x = days.length == 1
          ? size.width / 2
          : index * size.width / (days.length - 1);
      final y = (maxY - days[index].kg) / (maxY - minY) * size.height;
      points.add(Offset(x, y));
    }

    final line = Paint()
      ..color = color
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    int? previousTrendPoint;
    for (var index = 0; index < points.length; index++) {
      if (!days[index].contributesToTrend) continue;
      if (previousTrendPoint != null) {
        canvas.drawLine(points[previousTrendPoint], points[index], line);
      }
      previousTrendPoint = index;
    }

    for (var index = 0; index < points.length; index++) {
      final isToday = days[index].dateKey == todayKey;
      final dotColor = days[index].complete
          ? color
          : days[index].activeCaloriesBurned > 0
          ? color.withValues(alpha: .65)
          : incompleteColor;
      canvas.drawCircle(
        points[index],
        isToday ? 6 : 4.5,
        Paint()..color = dotColor,
      );
      if (isToday) {
        canvas.drawCircle(
          points[index],
          8,
          Paint()
            ..color = color.withValues(alpha: .24)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _WeightChartPainter oldDelegate) =>
      oldDelegate.days != days ||
      oldDelegate.color != color ||
      oldDelegate.gridColor != gridColor ||
      oldDelegate.minY != minY ||
      oldDelegate.maxY != maxY ||
      oldDelegate.todayKey != todayKey;
}
