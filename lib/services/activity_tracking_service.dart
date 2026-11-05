import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:geolocator/geolocator.dart';

import '../services/weight_estimator.dart';
import '../store/store.dart';

class ActivityTrackingService with WidgetsBindingObserver, ChangeNotifier {
  ActivityTrackingService._();

  static final instance = ActivityTrackingService._();

  Map<String, dynamic>? _session;
  Timer? _ticker;
  StreamSubscription<Position>? _positionSubscription;
  bool _restored = false;

  Map<String, dynamic>? get session =>
      _session == null ? null : Map.unmodifiable(_session!);
  bool get hasSession => _session != null;
  bool get isTracking =>
      _session?['status'] == 'tracking' || _session?['status'] == 'paused';
  bool get isPaused => _session?['status'] == 'paused';
  bool get isStopped => _session?['status'] == 'stopped';
  bool get isRunning => _session?['status'] == 'tracking';
  String? get gpsMessage => _session?['gpsMessage'] as String?;
  double get distanceMeters =>
      (_session?['distanceMeters'] as num?)?.toDouble() ?? 0;

  Future<void> restore() async {
    if (_restored) return;
    _restored = true;
    WidgetsBinding.instance.addObserver(this);
    final saved = store.d['activeActivity'];
    if (saved is! Map) return;
    final restored = Map<String, dynamic>.from(saved);
    final status = restored['status'];
    if (!{'tracking', 'paused', 'stopped'}.contains(status) ||
        restored['name'] is! String) {
      return;
    }
    _session = restored;
    notifyListeners();
    if (status == 'tracking') {
      _startTicker();
      await _resumeGpsIfPossible();
    }
  }

  Future<void> start(String activityName) async {
    await restore();
    if (_session != null) return;
    final needsGps = activityName != 'Swimming' && activityName != 'Yoga';
    var gpsReady = false;
    if (needsGps) gpsReady = await _requestLocationPermission();

    final now = DateTime.now().millisecondsSinceEpoch;
    _session = {
      'name': activityName,
      'status': 'tracking',
      'startedAtMs': now,
      'segmentStartedAtMs': now,
      'elapsedMs': 0,
      'distanceMeters': 0.0,
      'gpsEnabled': gpsReady,
      'gpsMessage': needsGps && !gpsReady
          ? 'GPS off, distance will be estimated'
          : null,
    };
    _persist();
    _startTicker();
    if (gpsReady) _startGpsStream();
    notifyListeners();
  }

  Future<bool> _requestLocationPermission() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return false;
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      return permission == LocationPermission.always ||
          permission == LocationPermission.whileInUse;
    } on Exception {
      return false;
    }
  }

  Future<void> _resumeGpsIfPossible() async {
    if (_session?['gpsEnabled'] != true || !isRunning) return;
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        _setGpsUnavailable();
        return;
      }
      final permission = await Geolocator.checkPermission();
      if (permission != LocationPermission.always &&
          permission != LocationPermission.whileInUse) {
        _setGpsUnavailable();
        return;
      }
      _startGpsStream();
    } on Exception {
      _setGpsUnavailable();
    }
  }

  void _startTicker() {
    _ticker ??= Timer.periodic(const Duration(seconds: 1), (_) {
      if (_session == null || !isRunning) return;
      notifyListeners();
    });
  }

  void _startGpsStream() {
    if (_positionSubscription != null || !isRunning) return;
    try {
      _positionSubscription =
          Geolocator.getPositionStream(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.best,
              distanceFilter: 5,
            ),
          ).listen(
            _onPosition,
            onError: (Object error, StackTrace stack) {
              _setGpsUnavailable();
            },
            cancelOnError: true,
          );
    } on Exception {
      _setGpsUnavailable();
    }
  }

  void _onPosition(Position position) {
    if (!isRunning || position.accuracy > 25) return;
    final previousLatitude = _session?['lastLatitude'] as num?;
    final previousLongitude = _session?['lastLongitude'] as num?;
    final previousAt = _session?['lastPositionAtMs'] as num?;
    if (previousLatitude != null &&
        previousLongitude != null &&
        previousAt != null) {
      final delta = Geolocator.distanceBetween(
        previousLatitude.toDouble(),
        previousLongitude.toDouble(),
        position.latitude,
        position.longitude,
      );
      final elapsedSeconds =
          (position.timestamp.millisecondsSinceEpoch - previousAt.toInt()) /
          1000;
      final activityName = _session?['name'];
      final maxSpeed = activityName == 'Cycling' ? 30.0 : 12.0;
      if (delta < 3 ||
          elapsedSeconds <= 0 ||
          delta / elapsedSeconds > maxSpeed) {
        return;
      }
      _session!['distanceMeters'] = distanceMeters + delta;
    }
    _session!['lastLatitude'] = position.latitude;
    _session!['lastLongitude'] = position.longitude;
    _session!['lastPositionAtMs'] = position.timestamp.millisecondsSinceEpoch;
    _persist();
    notifyListeners();
  }

  void pause() {
    if (!isRunning || _session == null) return;
    _session!['elapsedMs'] = elapsedMilliseconds;
    _session!['status'] = 'paused';
    _session!.remove('segmentStartedAtMs');
    _positionSubscription?.cancel();
    _positionSubscription = null;
    _persist();
    notifyListeners();
  }

  void resume() {
    if (!isPaused || _session == null) return;
    _session!['status'] = 'tracking';
    _session!['segmentStartedAtMs'] = DateTime.now().millisecondsSinceEpoch;
    _persist();
    _startTicker();
    _resumeGpsIfPossible();
    notifyListeners();
  }

  void stop() {
    if (!isTracking || _session == null) return;
    _session!['elapsedMs'] = elapsedMilliseconds;
    _session!['status'] = 'stopped';
    _session!.remove('segmentStartedAtMs');
    _ticker?.cancel();
    _ticker = null;
    _positionSubscription?.cancel();
    _positionSubscription = null;
    _persist();
    notifyListeners();
  }

  int get elapsedMilliseconds {
    if (_session == null) return 0;
    final accumulated = (_session!['elapsedMs'] as num?)?.toInt() ?? 0;
    if (!isRunning) return accumulated;
    final started =
        (_session!['segmentStartedAtMs'] as num?)?.toInt() ??
        DateTime.now().millisecondsSinceEpoch;
    return accumulated + DateTime.now().millisecondsSinceEpoch - started;
  }

  int get elapsedSeconds => elapsedMilliseconds ~/ 1000;

  int estimatedSteps([double? distanceOverrideMeters]) {
    final name = _session?['name'];
    if (name != 'Brisk walk' && name != 'Running') return 0;
    final height = store.d['h'];
    final heightCm = height is num && height > 0 ? height.toDouble() : 170.0;
    final stride = heightCm * (name == 'Running' ? .65 : .415) / 100;
    final distance = distanceOverrideMeters ?? distanceMeters;
    return stride <= 0 ? 0 : (distance / stride).round();
  }

  double? get currentWeightKg {
    final estimate = WeightEstimator.calculate(store.d);
    if (estimate.hasAnchor && estimate.currentWeightKg > 0) {
      return estimate.currentWeightKg;
    }
    final logged = store.lastW();
    if (logged > 0) return logged;
    final starting = store.goalField('sw');
    return starting > 0 ? starting : null;
  }

  int caloriesFor(int durationSeconds) {
    final weight = currentWeightKg;
    if (weight == null) return 0;
    final met = switch (_session?['name']) {
      'Brisk walk' => 4.3,
      'Running' => 9.8,
      'Cycling' => 7.5,
      'Swimming' => 6.0,
      'Yoga' => 2.5,
      _ => 0.0,
    };
    return (met * weight * durationSeconds / 3600).round();
  }

  void saveStopped({double? distanceKm}) {
    if (!isStopped || _session == null) return;
    final distanceMetersToSave = distanceKm == null
        ? distanceMeters
        : distanceKm * 1000;
    final name = _session!['name'] as String;
    final seconds = elapsedSeconds;
    final steps = (name == 'Brisk walk' || name == 'Running')
        ? estimatedSteps(distanceMetersToSave)
        : 0;
    store.acts.add({
      'n': name,
      'min': seconds == 0 ? 0 : math.max(1, (seconds / 60).round()),
      'durationSec': seconds,
      'km': distanceMetersToSave > 0
          ? double.parse((distanceMetersToSave / 1000).toStringAsFixed(2))
          : 0.0,
      'kc': caloriesFor(seconds),
      'st': steps,
      't': _session!['startedAtMs'],
    });
    store.d['steps'] = store.steps + steps;
    _clearSession();
    store.save();
  }

  void discard() {
    if (_session == null) return;
    _clearSession();
    store.save();
  }

  void _setGpsUnavailable() {
    if (_session == null) return;
    _session!['gpsEnabled'] = false;
    _session!['gpsMessage'] = 'GPS off, distance will be estimated';
    _positionSubscription?.cancel();
    _positionSubscription = null;
    _persist();
    notifyListeners();
  }

  void _persist() {
    store.d['activeActivity'] = _session == null
        ? null
        : Map<String, dynamic>.from(_session!);
    store.saveQuiet();
  }

  void _clearSession() {
    _ticker?.cancel();
    _ticker = null;
    _positionSubscription?.cancel();
    _positionSubscription = null;
    _session = null;
    store.d['activeActivity'] = null;
    notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _resumeGpsIfPossible();
    } else if (isRunning) {
      _positionSubscription?.cancel();
      _positionSubscription = null;
    }
  }

  void observeLifecycle() {
    WidgetsBinding.instance.addObserver(this);
  }
}

final activityTracking = ActivityTrackingService.instance;
