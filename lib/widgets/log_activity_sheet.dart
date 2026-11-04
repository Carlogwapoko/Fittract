import 'package:flutter/material.dart';

import '../store/store.dart';
import 'shared_widgets.dart';

class _Activity {
  final String name;
  final IconData icon;
  final int caloriesPerMinute;
  final int stepsPerMinute;
  final double kmPerMinute;

  const _Activity(
    this.name,
    this.icon,
    this.caloriesPerMinute,
    this.stepsPerMinute,
    this.kmPerMinute,
  );
}

const _activities = [
  _Activity('Brisk walk', Icons.directions_walk, 4, 110, .08),
  _Activity('Running', Icons.directions_run, 10, 160, .16),
  _Activity('Cycling', Icons.directions_bike, 7, 0, .30),
  _Activity('Swimming', Icons.pool, 8, 0, .03),
  _Activity('Yoga', Icons.self_improvement, 3, 0, 0),
  _Activity('Gym', Icons.fitness_center, 6, 0, 0),
];

/// Icon for a recorded activity, reusing the picker's canonical [_activities]
/// mapping so a log row and the sheet that created it always agree. Unknown
/// or legacy names get the neutral exercise default.
IconData activityIconFor(Object? name) {
  final wanted = (name ?? '').toString().trim().toLowerCase();
  for (final activity in _activities) {
    if (activity.name.toLowerCase() == wanted) return activity.icon;
  }
  return Icons.fitness_center;
}

Future<void> showLogActivity(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _LogActivitySheet(),
    );

class _LogActivitySheet extends StatefulWidget {
  const _LogActivitySheet();

  @override
  State<_LogActivitySheet> createState() => _LogActivitySheetState();
}

class _LogActivitySheetState extends State<_LogActivitySheet> {
  int _selected = 0;
  int _minutes = 30;
  final _distance = TextEditingController();

  _Activity get _activity => _activities[_selected];
  int get _calories => _minutes * _activity.caloriesPerMinute;
  int get _steps => _minutes * _activity.stepsPerMinute;
  double get _km => _distance.text.trim().isEmpty
      ? _minutes * _activity.kmPerMinute
      : num_(_distance.text);

  @override
  void dispose() {
    _distance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      20,
      0,
      20,
      MediaQuery.of(context).viewInsets.bottom + 20,
    ),
    child: SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Log an activity',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          const Text('Every bit of movement counts.', style: muted),
          const SizedBox(height: kGapLg),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var i = 0; i < _activities.length; i++)
                ChoiceChip(
                  avatar: Icon(
                    _activities[i].icon,
                    size: 18,
                    color: _selected == i
                        ? (isDark(context) ? kInk : Colors.white)
                        : primaryOf(context),
                  ),
                  label: Text(_activities[i].name),
                  selected: _selected == i,
                  showCheckmark: false,
                  selectedColor: primaryOf(context),
                  labelStyle: TextStyle(
                    color: _selected == i
                        ? (isDark(context) ? kInk : Colors.white)
                        : Theme.of(context).colorScheme.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                  onSelected: (_) => setState(() => _selected = i),
                ),
            ],
          ),
          const SizedBox(height: kGapLg),
          const Text('Duration', style: muted),
          const SizedBox(height: kGapSm),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton.filledTonal(
                onPressed: () => setState(
                  () => _minutes = (_minutes - 5).clamp(5, 300).toInt(),
                ),
                icon: const Icon(Icons.remove),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 22),
                child: Text(
                  '$_minutes min',
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              IconButton.filledTonal(
                onPressed: () => setState(
                  () => _minutes = (_minutes + 5).clamp(5, 300).toInt(),
                ),
                icon: const Icon(Icons.add),
              ),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (final minutes in [15, 30, 45, 60])
                Padding(
                  padding: const EdgeInsets.all(4),
                  child: ActionChip(
                    label: Text('$minutes min'),
                    onPressed: () => setState(() => _minutes = minutes),
                  ),
                ),
            ],
          ),
          const SizedBox(height: kGapMd),
          TextField(
            controller: _distance,
            onChanged: (_) => setState(() {}),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Distance (km)',
              hintText: 'Optional',
              prefixIcon: Icon(Icons.route_outlined),
              helperText: 'Leave blank to estimate from your activity.',
            ),
          ),
          const SizedBox(height: kGapLg),
          Container(
            padding: const EdgeInsets.symmetric(vertical: kGapLg),
            decoration: BoxDecoration(
              color: tintOf(context),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _stat('$_calories', 'kcal'),
                _stat('$_steps', 'steps'),
                _stat(_km.toStringAsFixed(1), 'km'),
              ],
            ),
          ),
          const SizedBox(height: kGapLg),
          btn('Save activity', _save, icon: Icons.save_outlined),
        ],
      ),
    ),
  );

  Widget _stat(String value, String label) => Column(
    children: [
      Text(
        value,
        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
      ),
      Text(label, style: muted),
    ],
  );

  void _save() {
    final enteredDistance = _distance.text.trim();
    if (enteredDistance.isNotEmpty) {
      final parsedDistance = double.tryParse(enteredDistance);
      if (parsedDistance == null ||
          !parsedDistance.isFinite ||
          parsedDistance < 0) {
        snack(context, 'Enter a valid distance of 0 or more.');
        return;
      }
    }
    store.acts.add({
      'n': _activity.name,
      'min': _minutes,
      'km': double.parse(_km.toStringAsFixed(1)),
      'kc': _calories,
      'st': _steps,
      't': DateTime.now().millisecondsSinceEpoch,
    });
    store.d['steps'] = store.steps + _steps;
    store.save();
    Navigator.pop(context);
  }
}
