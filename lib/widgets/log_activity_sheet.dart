import 'dart:async';

import 'package:flutter/material.dart';

import '../services/activity_tracking_service.dart';
import '../store/store.dart';
import 'shared_widgets.dart';

class _Activity {
  final String name;
  final IconData icon;

  const _Activity(this.name, this.icon);
}

const _activities = [
  _Activity('Brisk walk', Icons.directions_walk),
  _Activity('Running', Icons.directions_run),
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
    final gpsMessage = activityTracking.gpsMessage;
    final elapsedSeconds = activityTracking.elapsedSeconds;
    final distanceMeters = activityTracking.distanceMeters;
    final distanceKm = distanceMeters / 1000;
    final estimatedSteps = activityTracking.estimatedSteps();
    final trackedCalories = activityTracking.caloriesFor(elapsedSeconds);

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
                          ? Theme.of(context).colorScheme.onPrimary
                          : primaryOf(context),
                    ),
                    label: Text(_activities[i].name),
                    selected: _selected == i,
                    showCheckmark: false,
                    selectedColor: primaryOf(context),
                    labelStyle: TextStyle(
                      color: _selected == i
                          ? Theme.of(context).colorScheme.onPrimary
                          : Theme.of(context).colorScheme.onSurface,
                      fontWeight: FontWeight.w600,
                    ),
                    onSelected: tracked
                        ? null
                        : (_) => setState(() => _selected = i),
                  ),
              ],
            ),
            if (tracking && gpsMessage != null) ...[
              const SizedBox(height: kGapSm),
              Row(
                children: [
                  Expanded(child: Text(gpsMessage, style: muted)),
                  if (activityTracking.gpsStatus == GpsStatus.deniedForever &&
                      activityTracking.canOpenAppSettings)
                    TextButton(
                      onPressed: activityTracking.openAppSettings,
                      child: const Text('Open settings'),
                    )
                  else if (activityTracking.gpsStatus == GpsStatus.serviceOff)
                    TextButton(
                      onPressed: activityTracking.openLocationSettings,
                      child: const Text('Turn on'),
                    ),
                ],
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
            if (!tracked)
              btn('Start', _start, icon: Icons.play_arrow)
            else if (tracking)
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _stop,
                  icon: const Icon(Icons.stop),
                  label: const Text('Stop'),
                  style: FilledButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.error,
                    foregroundColor: Theme.of(context).colorScheme.onError,
                    minimumSize: const Size.fromHeight(50),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              )
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
    final needsGps = _activity.name != 'Swimming' && _activity.name != 'Yoga';
    if (needsGps && !await _confirmLocationUse()) {
      if (mounted) setState(() => _requestingLocation = false);
      return;
    }
    await activityTracking.start(
      _activity.name,
      confirmBackgroundPermission: _confirmBackgroundLocation,
    );
    if (mounted) setState(() => _requestingLocation = false);
  }

  Future<bool> _confirmLocationUse() async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Measure activity distance'),
          content: const Text(
            'Fittract uses your location while tracking to measure distance. '
            'Location updates may continue when the screen is locked.',
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

  Future<bool> _confirmBackgroundLocation() async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Keep tracking in the background?'),
          content: const Text(
            'Allow background location so distance can keep updating while '
            'your phone is locked. You can continue without it.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Continue without'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Allow'),
            ),
          ],
        ),
      ) ??
      false;

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
