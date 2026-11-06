import 'dart:async';

import 'package:flutter/material.dart';

import '../services/activity_tracking_service.dart';
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
];

/// Icons for removed activity types remain available for existing log rows.
IconData activityIconFor(Object? name) {
  final wanted = (name ?? '').toString().trim().toLowerCase();
  if (wanted == 'cycling') return Icons.directions_bike;
  if (wanted == 'swimming') return Icons.pool;
  if (wanted == 'yoga') return Icons.self_improvement;
  for (final activity in _activities) {
    if (activity.name.toLowerCase() == wanted) return activity.icon;
  }
  return Icons.fitness_center;
}

Future<void> showLogActivity(BuildContext context) => _showLogActivity(context);

Future<void> _showLogActivity(BuildContext context) async {
  await activityTracking.restore();
  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => const _LogActivitySheet(),
  );
}

class _LogActivitySheet extends StatefulWidget {
  const _LogActivitySheet();

  @override
  State<_LogActivitySheet> createState() => _LogActivitySheetState();
}

class _LogActivitySheetState extends State<_LogActivitySheet> {
  int _selected = 0;
  int _minutes = 30;
  bool _manualMode = false;
  bool _requestingLocation = false;
  final _distance = TextEditingController();

  _Activity get _activity => _activities[_selected];
  bool get _hasSession => activityTracking.hasSession;
  bool get _tracking => activityTracking.isTracking;
  bool get _stopped => activityTracking.isStopped;
  Map<String, dynamic>? get _session => activityTracking.session;
  String get _sessionName => _session?['name'] as String? ?? _activity.name;
  _Activity get _sessionActivity => _activities.firstWhere(
    (activity) => activity.name == _sessionName,
    orElse: () => _activity,
  );
  int get _calories => _minutes * _activity.caloriesPerMinute;
  int get _steps => _minutes * _activity.stepsPerMinute;
  double get _km => _distance.text.trim().isEmpty
      ? _minutes * _activity.kmPerMinute
      : num_(_distance.text);
  double? get _enteredDistanceKm {
    final value = _distance.text.trim();
    if (value.isEmpty) return null;
    return double.tryParse(value);
  }

  @override
  void initState() {
    super.initState();
    activityTracking.addListener(_trackingChanged);
    unawaited(_restoreSession());
  }

  Future<void> _restoreSession() async {
    await activityTracking.restore();
    _trackingChanged();
  }

  void _trackingChanged() {
    if (!mounted) return;
    final name = _session?['name'];
    final index = _activities.indexWhere((activity) => activity.name == name);
    setState(() {
      if (index >= 0) _selected = index;
    });
  }

  @override
  void dispose() {
    activityTracking.removeListener(_trackingChanged);
    _distance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tracked = _hasSession;
    final tracking = _tracking;
    final stopped = _stopped;
    final selectedActivity = tracked ? _sessionActivity : _activity;
    final elapsedSeconds = activityTracking.elapsedSeconds;
    final distanceMeters = activityTracking.distanceMeters;
    final distanceKm = distanceMeters / 1000;
    final estimatedSteps = activityTracking.estimatedSteps();
    final trackedCalories = activityTracking.caloriesFor(elapsedSeconds);
    final showManualControls = _manualMode && !tracked;

    return Padding(
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
                    onSelected: tracked
                        ? null
                        : (_) => setState(() => _selected = i),
                  ),
              ],
            ),
            if (activityTracking.gpsMessage case final message?) ...[
              const SizedBox(height: kGapSm),
              Text(message, style: muted),
            ],
            if (showManualControls) ...[
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
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Distance (km)',
                  hintText: 'Optional',
                  prefixIcon: Icon(Icons.route_outlined),
                  helperText: 'Leave blank to estimate from your activity.',
                ),
              ),
            ],
            const SizedBox(height: kGapLg),
            Container(
              padding: const EdgeInsets.symmetric(vertical: kGapLg),
              decoration: BoxDecoration(
                color: tintOf(context),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: tracked
                    ? stopped
                          ? [
                              _stat(_formatTime(elapsedSeconds), 'time'),
                              _stat(_stoppedDistance(distanceKm), 'km'),
                              _stat(_stoppedSteps(distanceKm), 'steps'),
                              _stat(trackedCalories.toString(), 'kcal'),
                            ]
                          : [
                              _stat(
                                tracking ? _formatTime(elapsedSeconds) : '--',
                                'time',
                              ),
                              _stat(
                                tracking ? _formatDistance(distanceKm) : '--',
                                'km',
                              ),
                              _stat(
                                tracking
                                    ? (selectedActivity.name == 'Brisk walk' ||
                                              selectedActivity.name == 'Running'
                                          ? store.withThousands(estimatedSteps)
                                          : '--')
                                    : '--',
                                'steps',
                              ),
                            ]
                    : showManualControls
                    ? [
                        _stat('$_calories', 'kcal'),
                        _stat('$_steps', 'steps'),
                        _stat(_km.toStringAsFixed(1), 'km'),
                      ]
                    : [
                        _stat('--', 'time'),
                        _stat('--', 'km'),
                        _stat('--', 'steps'),
                      ],
              ),
            ),
            if (stopped) ...[
              const SizedBox(height: kGapMd),
              TextField(
                controller: _distance,
                onChanged: (_) => setState(() {}),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Distance (km)',
                  hintText: 'Optional',
                  prefixIcon: Icon(Icons.route_outlined),
                ),
              ),
            ],
            const SizedBox(height: kGapLg),
            if (!tracked && !_manualMode)
              btn('Start', _start, icon: Icons.play_arrow)
            else if (tracking)
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _stop,
                  icon: const Icon(Icons.stop),
                  label: const Text('Stop'),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF9B3D3D),
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(50),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              )
            else if (_manualMode && !tracked)
              btn('Save activity', _saveManual, icon: Icons.save_outlined)
            else if (stopped)
              btn('Save activity', _saveTracked, icon: Icons.save_outlined),
            if (tracking) ...[
              Center(
                child: TextButton(
                  onPressed: activityTracking.isPaused
                      ? activityTracking.resume
                      : activityTracking.pause,
                  child: Text(activityTracking.isPaused ? 'Resume' : 'Pause'),
                ),
              ),
            ] else if (stopped) ...[
              Center(
                child: TextButton(
                  onPressed: activityTracking.discard,
                  child: const Text('Discard'),
                ),
              ),
            ] else if (!tracked && !_manualMode) ...[
              Center(
                child: TextButton(
                  onPressed: _requestingLocation
                      ? null
                      : () => setState(() => _manualMode = true),
                  child: const Text('Add manually instead'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _stat(String value, String label) => Column(
    children: [
      Text(
        value,
        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
      ),
      Text(label, style: muted),
    ],
  );

  Future<void> _start() async {
    if (_requestingLocation) return;
    setState(() => _requestingLocation = true);
    await activityTracking.start(_activity.name);
    if (mounted) setState(() => _requestingLocation = false);
  }

  void _stop() => activityTracking.stop();

  String _formatTime(int seconds) =>
      '${(seconds ~/ 60).toString().padLeft(2, '0')}:'
      '${(seconds % 60).toString().padLeft(2, '0')}';

  String _formatDistance(double km) =>
      km < 1 ? km.toStringAsFixed(2) : km.toStringAsFixed(1);

  String _stoppedDistance(double gpsKm) {
    final entered = _enteredDistanceKm;
    final km = entered ?? gpsKm;
    return km > 0 ? _formatDistance(km) : '--';
  }

  String _stoppedSteps(double gpsKm) {
    if (_sessionName != 'Brisk walk' && _sessionName != 'Running') {
      return '--';
    }
    final km = _enteredDistanceKm ?? gpsKm;
    if (km <= 0) return '--';
    return store.withThousands(activityTracking.estimatedSteps(km * 1000));
  }

  void _saveManual() {
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
      'd': today(),
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

  void _saveTracked() {
    final enteredDistance = _distance.text.trim();
    double? distance;
    if (enteredDistance.isNotEmpty) {
      distance = double.tryParse(enteredDistance);
      if (distance == null || !distance.isFinite || distance < 0) {
        snack(context, 'Enter a valid distance of 0 or more.');
        return;
      }
    }
    activityTracking.saveStopped(distanceKm: distance);
    Navigator.pop(context);
  }
}
