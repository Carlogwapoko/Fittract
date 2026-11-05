import 'dart:math';

import 'package:flutter/material.dart';

import '../services/activity_tracking_service.dart';
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
  }

  String _timeLabel(int? milliseconds) {
    if (milliseconds == null) return '';
    final time = DateTime.fromMillisecondsSinceEpoch(milliseconds);
    final hour = time.hour % 12 == 0 ? 12 : time.hour % 12;
    return '$hour:${time.minute.toString().padLeft(2, '0')} '
        '${time.hour >= 12 ? 'PM' : 'AM'}';
  }

  @override
  Widget build(BuildContext context) => live((c) {
    final stepGoal = store.stepGoal;
    final activities = List<Map>.from(store.acts.whereType<Map>());
    return screen([
      hdr(c, 'Daily steps', 'Your movement today.', back: true),
      card(
        color: tintOf(c),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              store.withThousands(store.steps),
              style: TextStyle(
                color: primaryOf(c),
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
                Text('${store.actKc()} kcal burned', style: muted),
              ],
            ),
          ],
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
              store.d['steps'] = max(
                0,
                store.steps - (steps is num ? steps.toInt() : 0),
              );
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
                  color: kRed,
                  semanticLabel: 'Remove activity',
                ),
              ],
            ),
          ),
    ]);
  });
}
