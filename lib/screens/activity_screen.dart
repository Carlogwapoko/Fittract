import 'dart:math';

import 'package:flutter/material.dart';

import '../services/activity_tracking_service.dart';
import '../services/daily_movement_tracking_service.dart';
import '../services/weight_estimator.dart';
import '../store/store.dart';
import '../widgets/log_activity_sheet.dart';
import '../widgets/shared_widgets.dart';

class ActivityScreen extends StatefulWidget {
  const ActivityScreen({super.key});

  @override
  State<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends State<ActivityScreen> {
  @override
  void initState() {
    super.initState();
    activityTracking.restore();
    dailyMovementTracking.startIfEnabled();
  }

  Future<void> _enableDailyTracking() async {
    final agreed =
        await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Enable automatic tracking?'),
            content: const Text(
              'While Fittract is open, your device motion sensor will count '
              'steps and GPS will measure walking distance. Daily totals are '
              'saved to your Fittract account.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Not now'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Continue'),
              ),
            ],
          ),
        ) ??
        false;
    if (!agreed || !mounted) return;
    await dailyMovementTracking.enableAndStart();
  }

  String _timeLabel(int? milliseconds) {
    if (milliseconds == null) return '';
    final time = DateTime.fromMillisecondsSinceEpoch(milliseconds);
    final hour = time.hour % 12 == 0 ? 12 : time.hour % 12;
    return '$hour:${time.minute.toString().padLeft(2, '0')} '
        '${time.hour >= 12 ? 'PM' : 'AM'}';
  }

  ({int calories, bool usesDefaultWeight}) _dailyActiveCalories() {
    final estimate = WeightEstimator.calculate(store.d);
    if (estimate.days.isNotEmpty) {
      return (
        calories: estimate.days.last.activeCaloriesBurned,
        usesDefaultWeight: false,
      );
    }

    final loggedSteps = store.acts.whereType<Map>().fold<int>(0, (
      total,
      activity,
    ) {
      final raw = activity['st'];
      final steps = raw is num
          ? raw.toInt()
          : int.tryParse(raw?.toString() ?? '') ?? 0;
      return total + steps.clamp(0, 1000000).toInt();
    });
    final unpairedSteps = max(0, store.steps - loggedSteps).toInt();
    final savedWeight = store.lastW();
    final hasSavedWeight = savedWeight >= 20 && savedWeight <= 300;
    final rawHeight = store.d['h'];
    final heightCm = rawHeight is num && rawHeight.isFinite
        ? rawHeight.toDouble().clamp(100, 250).toDouble()
        : 170.0;
    final stepCalories = WeightEstimator.stepCaloriesFor(
      steps: unpairedSteps,
      weightKg: hasSavedWeight ? savedWeight : 70,
      heightCm: heightCm,
    );
    final activityCalories = WeightEstimator.loggedExerciseCaloriesForDate(
      store.d,
      DateTime.now(),
    );
    return (
      calories: stepCalories + activityCalories,
      usesDefaultWeight: !hasSavedWeight && unpairedSteps > 0,
    );
  }

  @override
  Widget build(BuildContext context) => live((c) {
    final stepGoal = store.stepGoal;
    final activities = List<Map>.from(store.acts.whereType<Map>());
    final activeCalories = _dailyActiveCalories();
    return screen([
      hdr(c, 'Daily steps', 'Your movement today.', back: true),
      ListenableBuilder(
        listenable: dailyMovementTracking,
        builder: (context, _) => card(
          color: tintOf(context),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                store.withThousands(store.steps),
                style: TextStyle(
                  color: primaryOf(context),
                  fontSize: 32,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                'of ${store.withThousands(stepGoal)} daily steps',
                style: muted,
              ),
              const SizedBox(height: kGapSm),
              bar(store.steps / stepGoal),
              const SizedBox(height: kGapSm),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${store.actMin()} min active',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    '${activeCalories.usesDefaultWeight ? '~' : ''}'
                    '${store.withThousands(activeCalories.calories)} kcal burned',
                    style: muted,
                  ),
                ],
              ),
              if (activeCalories.usesDefaultWeight) ...[
                const SizedBox(height: kGapXs),
                const Text(
                  'Add your weight in Profile for a personal calorie estimate.',
                  style: muted,
                ),
              ],
              const SizedBox(height: kGapSm),
              Text(
                '${(dailyMovementTracking.distanceMeters / 1000).toStringAsFixed(2)} km GPS distance today',
                style: muted,
              ),
              const SizedBox(height: kGapXs),
              Text(dailyMovementTracking.statusMessage, style: muted),
              if (!dailyMovementTracking.hasConsentForCurrentAccount)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _enableDailyTracking,
                    icon: const Icon(Icons.location_searching),
                    label: const Text('Enable automatic tracking'),
                  ),
                )
              else if (dailyMovementTracking.gpsStatus ==
                      DailyGpsStatus.deniedForever ||
                  dailyMovementTracking.stepError != null)
                TextButton(
                  onPressed: dailyMovementTracking.openSettings,
                  child: const Text('Open settings'),
                )
              else if (dailyMovementTracking.gpsStatus == DailyGpsStatus.denied)
                TextButton(
                  onPressed: dailyMovementTracking.enableAndStart,
                  child: const Text('Retry permissions'),
                )
              else
                TextButton(
                  onPressed: dailyMovementTracking.disableAndStop,
                  child: const Text('Turn off automatic tracking'),
                ),
            ],
          ),
        ),
      ),
      ListenableBuilder(
        listenable: activityTracking,
        builder: (context, _) => Column(
          children: [
            if (activityTracking.isTracking)
              Padding(
                padding: const EdgeInsets.only(bottom: kGapSm),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: ActionChip(
                    avatar: Icon(
                      Icons.fiber_manual_record,
                      size: 12,
                      color: primaryOf(context),
                    ),
                    label: const Text('Tracking in progress'),
                    backgroundColor: tintOf(context),
                    onPressed: () => showLogActivity(context),
                  ),
                ),
              ),
            btn(
              'Log an activity',
              () => showLogActivity(context),
              icon: Icons.add,
            ),
          ],
        ),
      ),
      h3('Today’s activity'),
      if (activities.isEmpty)
        card(
          child: Row(
            children: [
              Icon(Icons.directions_walk, color: primaryOf(c)),
              const SizedBox(width: kGapMd),
              const Expanded(
                child: Text(
                  'No activity logged today. Start a walk or workout.',
                  style: muted,
                ),
              ),
            ],
          ),
        )
      else
        for (final activity in activities)
          card(
            onTap: () async {
              if (!await confirm(c, 'Remove this activity?', 'Remove')) return;
              final index = store.acts.indexOf(activity);
              if (index < 0) {
                if (c.mounted) {
                  snack(c, 'That activity is no longer in the list.');
                }
                return;
              }
              final steps = activity['st'];
              if (activity['stepsCounted'] != false) {
                store.d['steps'] = max(
                  0,
                  store.steps - (steps is num ? steps.toInt() : 0),
                );
              }
              store.acts.removeAt(index);
              store.save();
            },
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: tintOf(c),
                  child: Icon(
                    activityIconFor(activity['n']),
                    color: primaryOf(c),
                  ),
                ),
                const SizedBox(width: kGapMd),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${activity['n']}',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        '${activity['t'] != null ? '${_timeLabel(activity['t'] is num ? (activity['t'] as num).toInt() : null)} · ' : ''}'
                        '${activity['min']} min · ${activity['km']} km',
                        style: muted,
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.delete_outline,
                  color: Theme.of(c).colorScheme.error,
                  semanticLabel: 'Remove activity',
                ),
              ],
            ),
          ),
    ]);
  });
}
