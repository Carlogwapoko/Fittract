import 'dart:math';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/weight_estimator.dart';
import '../store/store.dart';
import '../widgets/shared_widgets.dart';

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
  }

  void _refreshFields() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _startingWeight.dispose();
    _manualWeight.dispose();
    _targetWeight.dispose();
    _targetDate.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => live((c) {
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
    final hasMealsToday = store.meals.isNotEmpty;
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
          hasMealData: hasMealsToday,
          profileIsIncomplete: age == null || height == null,
        ),
        _manualWeighInCard(c),
      ],
      h3('Weight goals'),
      _goalsCard(c, series.hasAnchor ? currentKg : 0),
    ]);
  });

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
    required bool hasMealData,
    required bool profileIsIncomplete,
  }) {
    final colors = Theme.of(context).colorScheme;
    final hasCurrentWeight = currentKg > 0;
    final changeColor = change == null || change.abs() < .05
        ? colors.onSurfaceVariant
        : change < 0
        ? const Color(0xFF21845A)
        : const Color(0xFF9A5A00);
    final pillBackground = change == null || change.abs() < .05
        ? colors.surfaceContainerHighest
        : change < 0
        ? const Color(0xFFE0F3E9)
        : const Color(0xFFFFF0D8);
    final dateText = DateFormat('EEE, MMM d').format(todayDate);
    final dailyDetails = series.days.length > 7
        ? series.days.sublist(series.days.length - 7).reversed.toList()
        : series.days.reversed.toList();
    final chartLabel = _chartDescription(visibleDays);

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
                  label: 'Estimated weight ${currentKg.toStringAsFixed(1)} kg',
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
              tag('AI ESTIMATE'),
            ],
          ),
          const SizedBox(height: kGapMd),
          if (change == null)
            Text(
              'Not enough complete days in this range to show a change yet.',
              style: muted,
            )
          else
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
          if (visibleDays.isEmpty)
            SizedBox(
              height: 185,
              child: Center(
                child: Text(
                  'No estimate points in this range yet.',
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
          if (!hasMealData)
            const Padding(
              padding: EdgeInsets.only(bottom: kGapMd),
              child: Text(
                'Log your meals to improve your estimate',
                style: TextStyle(color: kPri, fontWeight: FontWeight.w600),
              ),
            ),
          if (profileIsIncomplete)
            const Padding(
              padding: EdgeInsets.only(bottom: kGapMd),
              child: Text(
                'Add age and height in Profile to personalize your calorie-burn estimate.',
                style: muted,
              ),
            ),
          Text(
            'Estimated from calories you eat minus calories you burn. About 7,700 kcal is roughly 1 kg. Water and carbs can shift daily weight, so treat this as a trend.',
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
                for (final day in dailyDetails)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            DateFormat('EEE, MMM d').format(day.date),
                          ),
                        ),
                        if (!day.complete && !day.anchor)
                          Padding(
                            padding: const EdgeInsets.only(right: kGapSm),
                            child: Text('Incomplete', style: muted),
                          ),
                        Text(
                          '${day.kg.toStringAsFixed(1)} kg',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _chartDescription(List<WeightEstimateDay> days) {
    if (days.isEmpty) {
      return 'No weight estimates are available for this range.';
    }
    final entries = days
        .map(
          (day) =>
              '${DateFormat('MMM d').format(day.date)}: ${day.kg.toStringAsFixed(1)} kilograms${day.complete ? '' : ', incomplete day'}',
        )
        .join('; ');
    return 'Estimated weight trend. $entries. Incomplete days do not change the estimate.';
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
          child: FilledButton.tonal(
            onPressed: _validWeight(_manualWeight.text)
                ? () => _saveWeight(context)
                : null,
            child: const Text('Save weight'),
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
                            store.goal['wk'] = max(1, weeklyGoal - 1);
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
                            store.goal['wk'] = min(7, weeklyGoal + 1);
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

  ({String message, String? warning}) _paceMessage(double currentKg) {
    final target = double.tryParse(_targetWeight.text.trim());
    if (target == null || !target.isFinite || target < 20 || target > 300) {
      return (
        message: 'Enter a target weight to see your pace.',
        warning: null,
      );
    }
    if ((target - currentKg).abs() < .05) {
      return (
        message: 'You are at your target. Keep it steady.',
        warning: null,
      );
    }

    final todayDate = DateTime.now();
    final goalDate = DateTime.tryParse(_targetDate.text);
    final pace = _recentPace();
    final daysUntilGoal = goalDate == null
        ? null
        : DateTime(goalDate.year, goalDate.month, goalDate.day)
              .difference(
                DateTime(todayDate.year, todayDate.month, todayDate.day),
              )
              .inDays;
    final gainingGoal = target > currentKg;

    if (gainingGoal) {
      if (daysUntilGoal == null || daysUntilGoal <= 0) {
        return (
          message: 'Choose a future target date to see your gaining pace.',
          warning: daysUntilGoal != null
              ? 'Choose a future date for a gradual, realistic goal.'
              : null,
        );
      }
      final requiredWeeklyChange = (target - currentKg) * 7 / daysUntilGoal;
      final surplus =
          ((target - currentKg) * WeightEstimator.kcalPerKg / daysUntilGoal)
              .round();
      return (
        message:
            'To reach ${target.toStringAsFixed(1)} kg by your date, aim for about ${NumberFormat('#,##0').format(surplus)} kcal/day above what you burn.',
        warning: requiredWeeklyChange > 1
            ? 'That is a very ambitious pace. Consider a later target date for gradual progress.'
            : null,
      );
    }

    final loss = currentKg - target;
    if (pace == null) {
      return (
        message: 'Log meals for 14 days to get a reliable pace estimate.',
        warning: null,
      );
    }
    final ratePerDay = pace;
    final projectedDate = ratePerDay < 0
        ? DateTime.now().add(
            Duration(days: max(0, (loss / -ratePerDay).round())),
          )
        : null;
    final isOnTrack =
        goalDate != null &&
        daysUntilGoal != null &&
        daysUntilGoal > 0 &&
        projectedDate != null &&
        !projectedDate.isAfter(
          DateTime(goalDate.year, goalDate.month, goalDate.day),
        );
    final requiredWeeklyChange = daysUntilGoal != null && daysUntilGoal > 0
        ? loss * 7 / daysUntilGoal
        : 0.0;
    final unrealistic = requiredWeeklyChange > 1;

    if (isOnTrack || (goalDate == null && projectedDate != null)) {
      return (
        message:
            'On track. At your current pace you will reach ${target.toStringAsFixed(1)} kg around ${DateFormat('MMM d, yyyy').format(projectedDate)}.',
        warning: ratePerDay.abs() * 7 > 1
            ? 'Your recent pace is faster than about 1 kg per week. Consider a gentler goal.'
            : null,
      );
    }
    if (daysUntilGoal == null) {
      return (
        message: 'At your current pace, your goal is not yet moving in the right direction. Choose a target date to see a realistic plan.',
        warning: null,
      );
    }
    if (daysUntilGoal <= 0) {
      return (
        message: 'Your target date has passed. Choose a future date for a gradual plan.',
        warning: null,
      );
    }

    final requiredNetCalories =
        -loss * WeightEstimator.kcalPerKg / daysUntilGoal;
    final currentNetCalories = ratePerDay * WeightEstimator.kcalPerKg;
    final additionalDeficit = max(
      0,
      (currentNetCalories - requiredNetCalories).round(),
    );
    final projected = projectedDate == null
        ? null
        : DateFormat('MMM d, yyyy').format(projectedDate);
    if (additionalDeficit > 500) {
      return (
        message: projected == null
            ? 'At your current pace you are not yet moving toward ${target.toStringAsFixed(1)} kg. Reaching it by your target date would require an aggressive deficit.'
            : 'At your current pace you will reach ${target.toStringAsFixed(1)} kg around $projected, after your target date. Reaching it by your date would require an aggressive deficit.',
        warning: 'Consider a later target date rather than cutting calories drastically. FitTrack does not recommend extreme restriction.',
      );
    }
    return (
      message: projected == null
          ? 'At your current pace you are not yet moving toward ${target.toStringAsFixed(1)} kg. You would need about ${NumberFormat('#,##0').format(additionalDeficit)} kcal/day less than you burn.'
          : 'At your current pace you will reach ${target.toStringAsFixed(1)} kg around $projected, after your target date. You would need about ${NumberFormat('#,##0').format(additionalDeficit)} kcal/day less than you burn.',
      warning: unrealistic
          ? 'This target is more than about 1 kg per week. Consider a gentler pace and a later target date.'
          : null,
    );
  }

  double? _recentPace() {
    final series = WeightEstimator.calculate(store.d);
    final start = DateTime.now().subtract(const Duration(days: 14));
    final points = series.days
        .where(
          (day) =>
              day.complete &&
              !day.anchor &&
              !day.date.isBefore(DateTime(start.year, start.month, start.day)),
        )
        .toList();
    if (points.length < 2) return null;
    final elapsedDays = points.last.date.difference(points.first.date).inDays;
    if (elapsedDays == 0) return null;
    return (points.last.kg - points.first.kg) / elapsedDays;
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

  void _startTracking(BuildContext context) {
    final weight = double.tryParse(_startingWeight.text.trim());
    if (weight == null || weight < 20 || weight > 300) return;
    store.goal['sw'] = weight;
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
    store.goal['w'] = target ?? 0.0;
    store.goal['d'] = date;
    store.save();
    snack(context, 'Goals saved.');
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
    final labels = days.length == 1
        ? [days.first, days.first, days.first]
        : [days.first, days[days.length ~/ 2], days.last];

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
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  DateFormat('MMM d').format(labels.first.date),
                  style: muted,
                ),
                Text(DateFormat('MMM d').format(labels[1].date), style: muted),
                Text(
                  DateFormat('MMM d').format(labels.last.date),
                  style: muted,
                ),
              ],
            ),
          ],
        ),
      ),
    );
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
    for (var index = 1; index < points.length; index++) {
      if (days[index - 1].complete && days[index].complete) {
        canvas.drawLine(points[index - 1], points[index], line);
      }
    }

    for (var index = 0; index < points.length; index++) {
      final isToday = days[index].dateKey == todayKey;
      final dotColor = days[index].complete ? color : incompleteColor;
      canvas.drawCircle(
        points[index],
        isToday ? 5 : 3.5,
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
