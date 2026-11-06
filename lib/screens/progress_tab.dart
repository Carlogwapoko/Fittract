import 'dart:math';

import 'package:flutter/material.dart';

import '../services/weight_estimator.dart';
import '../store/store.dart';
import '../widgets/shared_widgets.dart';
import 'weight_screen.dart';

class ProgressTab extends StatefulWidget {
  const ProgressTab({super.key});
  @override
  State<ProgressTab> createState() => _ProgressState();
}

class _ProgressState extends State<ProgressTab> {
  int tab = 0;
  bool all = false;

  Widget stat(IconData icon, String big, String sub) => Expanded(
    child: card(
      color: kDk,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: primaryOf(context), size: 18),
          const SizedBox(height: kGapSm),
          Text(
            big,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 26,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            sub,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ],
      ),
    ),
  );

  List<Widget> overview(BuildContext c) {
    // Dates are stringified rather than cast: retention keeps entries whose
    // date is missing, and they must not crash this screen.
    final recent = store.hist
        .where((h) => '${h['d']}'.compareTo(daysAgo(27)) >= 0)
        .toList();
    final mins = recent.fold<int>(
      0,
      (a, h) => a + (h['min'] is num ? (h['min'] as num).toInt() : 0),
    );
    final bs = [3, 2, 1, 0].map(store.wkCount).toList();
    final top = max(4, bs.reduce(max));
    final hist = store.hist.toList()
      ..sort((a, b) => '${b['d']}'.compareTo('${a['d']}'));
    return [
      Row(
        children: [
          stat(
            Icons.fitness_center,
            '${recent.length}',
            'Workouts · last 4 weeks',
          ),
          const SizedBox(width: kGapMd),
          stat(
            Icons.timer_outlined,
            '${mins ~/ 60}h ${mins % 60}m',
            'Time moving',
          ),
        ],
      ),
      card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: kGapSm,
              runSpacing: kGapSm,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Text(
                  'A stronger routine',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                tag('4 WEEKS'),
              ],
            ),
            const SizedBox(height: kGapMd),
            SizedBox(
              height: 120,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (final v in bs)
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Text(
                            '$v',
                            style: TextStyle(
                              color: primaryOf(c),
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: kGapXs),
                          Container(
                            margin: const EdgeInsets.symmetric(horizontal: 6),
                            height: max(8, v / top * 100),
                            decoration: BoxDecoration(
                              color: primaryOf(context),
                              borderRadius: BorderRadius.vertical(
                                top: Radius.circular(6),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            const Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                Text('W-3', style: muted),
                Text('W-2', style: muted),
                Text('W-1', style: muted),
                Text('Now', style: muted),
              ],
            ),
          ],
        ),
      ),
      h3('Workout history'),
      for (final h in hist.take(all ? 99 : 4))
        card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: Text(
                      '${h['n']}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  Text('${h['d']}', style: muted),
                ],
              ),
              const SizedBox(height: kGapXs),
              Text(
                '${h['min']} min · ${h['ex']} exercises · ${h['kc']} kcal',
                style: muted,
              ),
              const SizedBox(height: 6),
              Text(
                '✓ Completed',
                style: TextStyle(color: primaryOf(context), fontSize: 12),
              ),
            ],
          ),
        ),
      // Only offer the toggle when there is history to expand; a "View all"
      // button over an empty list is dead UI.
      if (hist.isNotEmpty)
        btn(
          all ? 'Show less' : 'View all',
          () => setState(() => all = !all),
          tonal: true,
          icon: all ? Icons.expand_less : Icons.list_alt,
        ),
    ];
  }

  List<Widget> daily() {
    final m = <String, Map<String, dynamic>>{};
    // Numeric fields are decoded through num so legacy snapshots that stored
    // values as doubles do not throw a cast error here; collection keys are
    // read defensively so a missing key falls back to empty.
    int numOf(Object? v) => v is num ? v.toInt() : 0;
    List listOf(Object? v) => v is List ? v : const [];
    for (final e in listOf(store.d['log'])) {
      final meals = listOf(e['meals']);
      m['${e['d']}'] = {
        'k': meals.fold<int>(0, (a, x) => a + numOf(x['k'])),
        's': numOf(e['steps']),
        'min': listOf(e['act']).fold<int>(0, (a, x) => a + numOf(x['min'])),
        'ml': 0,
        'n': meals.map((x) => x['n']).join(', '),
      };
    }
    m[store.d['day']] = {
      'k': store.kcal(),
      's': store.steps,
      'min': store.actMin(),
      'ml': 0,
      'n': store.meals.map((x) => x['n']).join(', '),
    };
    for (final w in listOf(store.d['water'])) {
      final key = '${w['d']}';
      m.putIfAbsent(key, () => {'k': 0, 's': 0, 'min': 0, 'ml': 0, 'n': ''});
      m[key]!['ml'] = numOf(m[key]!['ml']) + numOf(w['ml']);
    }
    final keys = m.keys.toList()..sort((a, b) => b.compareTo(a));
    return [
      const Padding(
        padding: EdgeInsets.only(bottom: kGapMd),
        child: Text(
          'Food, steps and activity reset every day. Past days are kept here.',
          style: muted,
        ),
      ),
      for (final k in keys)
        card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: Text(
                      k == today() ? 'Today' : k,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  Text('${m[k]!['min']} min active', style: muted),
                ],
              ),
              const SizedBox(height: kGapSm),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      children: [
                        Text(
                          '${m[k]!['k']}',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 2),
                        Text('kcal', style: muted),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Column(
                      children: [
                        Text(
                          '${m[k]!['s']}',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 2),
                        Text('steps', style: muted),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Column(
                      children: [
                        Text(
                          '${((m[k]!['ml'] as int) / 1000).toStringAsFixed(1)} L',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 2),
                        Text('water', style: muted),
                      ],
                    ),
                  ),
                ],
              ),
              if ((m[k]!['n'] as String).isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: kGapSm),
                  child: Text(m[k]!['n'], style: muted),
                ),
            ],
          ),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) => live((c) {
    final sw = store.goalField('sw'), gw = store.goalField('w');
    final weightEstimate = WeightEstimator.calculate(store.d);
    final hasWeight = weightEstimate.hasAnchor;
    final body = tab == 0
        ? overview(c)
        : tab == 1
        ? [
            card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    hasWeight
                        ? store.wt(weightEstimate.currentWeightKg)
                        : 'Not logged yet',
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    hasWeight
                        ? 'Started at ${store.wt(sw)}'
                        : 'Log your first weight to start tracking.',
                    style: muted,
                  ),
                ],
              ),
            ),
            btn(
              'Open weight tracker',
              () => go(c, const WeightScreen()),
              icon: Icons.monitor_weight_outlined,
            ),
          ]
        : tab == 2
        ? [
            card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    gw > 0
                        ? 'Target ${store.wt(gw)}${store.goal['d'] == '' ? '' : ' by ${store.goal['d']}'}'
                        : 'No weight goal set yet',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  bar(store.goalProgress()),
                  Text(
                    'Weekly workouts goal: ${store.weeklyWorkoutGoal} (this week ${store.wkCount(0)})',
                    style: muted,
                  ),
                ],
              ),
            ),
            btn(
              'Edit goals',
              () => go(c, const WeightScreen()),
              icon: Icons.flag_outlined,
            ),
          ]
        : daily();
    return tabBody([
      hdr(c, 'Your progress', "See how far you've come."),
      SizedBox(
        width: double.infinity,
        child: SegmentedButton<int>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: 0, label: Text('Overview')),
            ButtonSegment(value: 1, label: Text('Weight')),
            ButtonSegment(value: 2, label: Text('Goals')),
            ButtonSegment(value: 3, label: Text('Daily')),
          ],
          selected: {tab},
          onSelectionChanged: (s) => setState(() => tab = s.first),
        ),
      ),
      const SizedBox(height: 12),
      ...body,
    ]);
  });
}
