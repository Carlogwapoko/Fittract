import 'dart:math';

import 'package:flutter/material.dart';

import '../store/store.dart';
import '../widgets/log_activity_sheet.dart';
import '../widgets/shared_widgets.dart';

class WaterScreen extends StatelessWidget {
  const WaterScreen({super.key});

  String tf(int? ms) {
    if (ms == null) return '';
    final t = DateTime.fromMillisecondsSinceEpoch(ms);
    final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
    return '$h:${t.minute.toString().padLeft(2, '0')} ${t.hour >= 12 ? 'PM' : 'AM'}';
  }

  void addW(int ml) {
    (store.d['water'] as List).add({
      'd': today(),
      'ml': ml,
      't': DateTime.now().millisecondsSinceEpoch,
    });
    store.save();
  }

  @override
  Widget build(BuildContext context) => live((c) {
    final w = store.water();
    final waterGoalMl = store.waterGoalMl > 0 ? store.waterGoalMl : 2500;
    final stepGoal = store.stepGoal > 0 ? store.stepGoal : 8000;
    final filledCells = ((w * 10) / waterGoalMl).clamp(0, 10).floor();
    final wl = store.d['water'] as List;
    final todays = wl.where((e) => e['d'] == today()).toList();
    final last = todays.isEmpty ? null : todays.last;
    return screen([
      hdr(c, 'Water & activity · Today', 'Every bit counts.', back: true),
      card(
        color: kDk,
        pad: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Daily hydration',
                        style: TextStyle(color: Colors.white70),
                      ),
                      Text(
                        '${(w / 1000).toStringAsFixed(1)} L',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 34,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        'of ${(waterGoalMl / 1000).toStringAsFixed(1)} L goal · ${((w / waterGoalMl) * 100).clamp(0, 100).round()}% complete',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white12,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.water_drop, color: Colors.white),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                for (int i = 0; i < 10; i++)
                  Expanded(
                    child: Container(
                      height: 30,
                      margin: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: i < filledCells ? kMint : Colors.white12,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Icon(
                        Icons.local_drink_outlined,
                        size: 14,
                        color: i < filledCells ? kDk : Colors.white54,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: kGapSm),
            Text(
              '$filledCells of 10 marks · goal ${(waterGoalMl / 1000).toStringAsFixed(1)} L (${waterGoalMl ~/ 10} ml per mark)',
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
            const SizedBox(height: kGapMd),
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: () => addW(250),
                    style: FilledButton.styleFrom(
                      backgroundColor: primaryOf(c),
                      minimumSize: const Size.fromHeight(48),
                    ),
                    child: const Text('+ 250 ml'),
                  ),
                ),
                const SizedBox(width: kGapMd),
                Expanded(
                  child: FilledButton(
                    onPressed: () async {
                      final f = await form(c, 'Custom amount', [
                        F('ml', 'Millilitres', '330', type: 'number'),
                      ], ok: 'Add');
                      if (f == null || !c.mounted) return;
                      final ml = double.tryParse((f['ml'] ?? '').trim());
                      if (ml == null || ml <= 0) {
                        snack(c, 'Enter a positive amount of millilitres.');
                        return;
                      }
                      addW(ml.round());
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor: tintOf(c),
                      foregroundColor: primaryOf(c),
                      minimumSize: const Size.fromHeight(48),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.edit_outlined, size: 18),
                        SizedBox(width: 8),
                        Text('Custom'),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            last == null
                ? 'No drinks logged yet'
                : 'Last drink: ${last['ml']} ml${last['t'] != null ? ' at ${tf(last['t'])}' : ''}',
            style: muted,
          ),
          TextButton(
            // Disabled when there is nothing to undo, so the action always
            // does what it says instead of silently ignoring a tap.
            onPressed: todays.isEmpty
                ? null
                : () {
                    wl.remove(todays.last);
                    store.save();
                  },
            child: const Text('Undo'),
          ),
        ],
      ),
      h3('Move a little more'),
      card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${store.steps}',
              style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800),
            ),
            Text(
              'of ${store.withThousands(stepGoal)} daily steps',
              style: muted,
            ),
            bar(store.steps / stepGoal),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${store.actMin()} min active',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                Text('${store.actKc()} kcal burned', style: muted),
              ],
            ),
          ],
        ),
      ),
      for (final activity in List.of(store.acts))
        card(
          onTap: () async {
            // Capture the activity itself, not a list index: the confirm
            // dialog is async, and the list can change (e.g. the midnight
            // rollover) while it is open. Remove only this exact entry, and
            // only if it is still present.
            if (await confirm(c, 'Remove this activity?', 'Remove')) {
              final idx = store.acts.indexOf(activity);
              if (idx < 0) {
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
              store.acts.removeAt(idx);
              store.save();
            }
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
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${activity['n']}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      '${activity['t'] != null ? '${tf(activity['t'])} · ' : ''}${activity['min']} min · ${activity['km']} km',
                      style: muted,
                    ),
                  ],
                ),
              ),
              // The whole row's tap action is delete-with-confirmation, so
              // the trailing glyph says exactly that instead of a chevron
              // implying navigation. Confirmation stays on the row tap.
              Icon(
                Icons.delete_outline,
                color: kRed,
                semanticLabel: 'Remove activity',
              ),
            ],
          ),
        ),
      btn('+ Log physical activity', () => showLogActivity(c)),
      const SizedBox(height: kGapSm),
      btn(
        'Edit daily goals',
        () async {
          final f = await form(c, 'Daily goals', [
            F('w', 'Water goal (ml)', '${store.waterGoalMl}', type: 'number'),
            F('s', 'Step goal', '${store.stepGoal}', type: 'number'),
          ], ok: 'Save');
          if (f == null || !c.mounted) return;
          final water = int.tryParse((f['w'] ?? '').trim());
          final steps = int.tryParse((f['s'] ?? '').trim());
          if (water == null || water < 500 || water > 10000) {
            snack(c, 'Water goal must be between 500 and 10,000 ml.');
            return;
          }
          if (steps == null || steps < 1000 || steps > 50000) {
            snack(c, 'Step goal must be between 1,000 and 50,000.');
            return;
          }
          store.activityGoals['waterMl'] = water;
          store.activityGoals['steps'] = steps;
          store.save();
          snack(c, 'Daily goals saved.');
        },
        tonal: true,
        icon: Icons.tune,
      ),
    ]);
  });
}
