import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:geolocator/geolocator.dart';

import 'daily_movement_tracking_service.dart';
import '../services/weight_estimator.dart';
import '../store/store.dart';

enum GpsStatus {
  searching,
  good,
  weak,
  denied,
  deniedForever,
  serviceOff,
  unavailable,
}

typedef PositionStreamFactory = Stream<Position> Function(
  LocationSettings settings,
);

class ActivityTrackingService with WidgetsBindingObserver, ChangeNotifier {
  ActivityTrackingService._({
    PositionStreamFactory? positionStream,
    Future<bool> Function()? locationServiceEnabled,
    Future<LocationPermission> Function()? permissionCheck,
    Future<LocationPermission> Function()? permissionRequest,
    bool? isWeb,
    TargetPlatform? platform,
    VoidCallback? saveQuiet,
  }) : _positionStream =
           positionStream ??
           ((settings) =>
               Geolocator.getPositionStream(locationSettings: settings)),
       _locationServiceEnabled =
           locationServiceEnabled ?? Geolocator.isLocationServiceEnabled,
       _permissionCheck = permissionCheck ?? Geolocator.checkPermission,
       _permissionRequest = permissionRequest ?? Geolocator.requestPermission,
       _isWeb = isWeb ?? kIsWeb,
       _platform = platform ?? defaultTargetPlatform,
       _saveQuiet = saveQuiet ?? store.saveQuiet;

  static final instance = ActivityTrackingService._();

  @visibleForTesting
  factory ActivityTrackingService.forTesting({
    required PositionStreamFactory positionStream,
    required Future<bool> Function() locationServiceEnabled,
    required Future<LocationPermission> Function() permissionCheck,
    required Future<LocationPermission> Function() permissionRequest,
    required TargetPlatform platform,
    bool isWeb = false,
    VoidCallback? saveQuiet,
  }) => ActivityTrackingService._(
    positionStream: positionStream,
    locationServiceEnabled: locationServiceEnabled,
    permissionCheck: permissionCheck,
    permissionRequest: permissionRequest,
    platform: platform,
    isWeb: isWeb,
    saveQuiet: saveQuiet,
  );

  final PositionStreamFactory _positionStream;
  final Future<bool> Function() _locationServiceEnabled;
  final Future<LocationPermission> Function() _permissionCheck;
  final Future<LocationPermission> Function() _permissionRequest;
  final bool _isWeb;
  final TargetPlatform _platform;
  final VoidCallback _saveQuiet;

  Map<String, dynamic>? _session;
  Timer? _ticker;
  StreamSubscription<Position>? _positionSubscription;
  Future<void>? _restoreFuture;
  Future<void> _subscriptionCancellation = Future<void>.value();
  Future<void>? _startFuture;
  bool _needsRebaseline = false;
  bool _observingLifecycle = false;
  GpsStatus _gpsStatus = GpsStatus.unavailable;

  Map<String, dynamic>? get session =>
      _session == null ? null : Map.unmodifiable(_session!);
  bool get hasSession => _session != null;
  bool get isTracking =>
      _session?['status'] == 'tracking' || _session?['status'] == 'paused';
  bool get isPaused => _session?['status'] == 'paused';
  bool get isStopped => _session?['status'] == 'stopped';
  bool get isRunning => _session?['status'] == 'tracking';
  GpsStatus get gpsStatus => _gpsStatus;
  bool get canOpenAppSettings => !_isWeb;
  String? get gpsMessage => _gpsStatusMessage;
  double get distanceMeters =>
      (_session?['distanceMeters'] as num?)?.toDouble() ?? 0;

  String? get _gpsStatusMessage {
    if (_session != null && !_needsGps) return null;
    return switch (_gpsStatus) {
      GpsStatus.searching => 'Searching for GPS…',
      GpsStatus.good => 'GPS signal is good',
      GpsStatus.weak => 'Weak GPS signal, move outdoors',
      GpsStatus.denied => 'Location permission is denied',
      GpsStatus.deniedForever =>
        _isWeb
            ? 'Chrome blocked location. Use localhost or HTTPS and allow location for this site.'
            : 'Location permission is denied',
      GpsStatus.serviceOff => 'Location is off',
      GpsStatus.unavailable => 'GPS is unavailable',
    };
  }

  Future<void> restore() {
    final pending = _restoreFuture;
    if (pending != null) return pending;
    final restoration = _restore();
    _restoreFuture = restoration;
    return restoration.whenComplete(() {
      if (identical(_restoreFuture, restoration)) _restoreFuture = null;
    });
  }

  Future<void> _restore() async {
    if (_session != null) return;
    if (!_observingLifecycle) {
      WidgetsBinding.instance.addObserver(this);
      _observingLifecycle = true;
    }
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
    final restoredGpsStatus = restored['gpsStatus'];
    _gpsStatus = GpsStatus.values.firstWhere(
      (status) => status.name == restoredGpsStatus,
      orElse: () => status == 'tracking' && _needsGps
          ? GpsStatus.searching
          : GpsStatus.unavailable,
    );
    if (status == 'tracking') {
      _gpsStatus = _needsGps ? GpsStatus.searching : GpsStatus.unavailable;
      _needsRebaseline = true;
      _startTicker();
      await _resumeGpsIfPossible();
    }
  }

  Future<void> start(
    String activityName, {
    Future<bool> Function()? confirmBackgroundPermission,
  }) async {
    if (_startFuture != null) return _startFuture!;
    final operation = _start(
      activityName,
      confirmBackgroundPermission: confirmBackgroundPermission,
    );
    _startFuture = operation;
    try {
      await operation;
    } finally {
      _startFuture = null;
    }
  }

  Future<void> _start(
    String activityName, {
    Future<bool> Function()? confirmBackgroundPermission,
  }) async {
    await restore();
    if (_session != null) return;
    final needsGps = activityName != 'Swimming' && activityName != 'Yoga';
    if (needsGps) {
      _gpsStatus = await _requestLocationPermission(
        confirmBackgroundPermission: confirmBackgroundPermission,
      );
    } else {
      _gpsStatus = GpsStatus.unavailable;
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    _session = {
      'name': activityName,
      'status': 'tracking',
      'startedAtMs': now,
      'segmentStartedAtMs': now,
      'elapsedMs': 0,
      'distanceMeters': 0.0,
      'gpsEnabled': needsGps && _hasLocationPermission(_gpsStatus),
    };
    _persist();
    _startTicker();
    if (needsGps && _hasLocationPermission(_gpsStatus)) {
      _setGpsStatus(GpsStatus.searching);
      await _startGpsStream();
    }
    notifyListeners();
  }

  bool _hasLocationPermission(GpsStatus status) =>
      status == GpsStatus.searching || status == GpsStatus.good;

  Future<GpsStatus> _requestLocationPermission({
    Future<bool> Function()? confirmBackgroundPermission,
  }) async {
    try {
      if (!await _locationServiceEnabled()) return GpsStatus.serviceOff;
      var permission = await _permissionCheck();
      if (_isWeb) {
        return switch (permission) {
          LocationPermission.deniedForever => GpsStatus.deniedForever,
          _ => GpsStatus.searching,
        };
      }
      if (permission == LocationPermission.denied) {
        permission = await _permissionRequest();
      }
      if (permission == LocationPermission.whileInUse &&
          _platform == TargetPlatform.android &&
          confirmBackgroundPermission != null &&
          await confirmBackgroundPermission()) {
        final backgroundPermission = await _permissionRequest();
        if (backgroundPermission == LocationPermission.denied ||
            backgroundPermission == LocationPermission.deniedForever) {
          final foregroundPermission = await _permissionCheck();
          permission =
              foregroundPermission == LocationPermission.whileInUse ||
                  foregroundPermission == LocationPermission.always
              ? foregroundPermission
              : backgroundPermission;
        } else {
          permission = backgroundPermission;
        }
      }
      return _permissionGpsStatus(permission);
    } on Exception {
      return GpsStatus.unavailable;
    }
  }

  GpsStatus _permissionGpsStatus(LocationPermission permission) =>
      switch (permission) {
        LocationPermission.denied => GpsStatus.denied,
        LocationPermission.deniedForever => GpsStatus.deniedForever,
        LocationPermission.always ||
        LocationPermission.whileInUse => GpsStatus.searching,
        LocationPermission.unableToDetermine => GpsStatus.unavailable,
      };

  Future<void> _resumeGpsIfPossible() async {
    if (!isRunning || !_needsGps) return;
    try {
      if (!await _locationServiceEnabled()) {
        _setGpsStatus(GpsStatus.serviceOff);
        unawaited(_cancelGpsStream());
        return;
      }
      final permission = await _permissionCheck();
      if (_isWeb &&
          (permission == LocationPermission.denied ||
              permission == LocationPermission.unableToDetermine)) {
        _setGpsStatus(GpsStatus.searching);
        await _startGpsStream();
        return;
      }
      final status = _permissionGpsStatus(permission);
      if (!_hasLocationPermission(status)) {
        _setGpsStatus(status);
        unawaited(_cancelGpsStream());
        return;
      }
      _setGpsStatus(GpsStatus.searching);
      await _startGpsStream();
    } on Exception {
      _setGpsStatus(GpsStatus.unavailable);
    }
  }

  bool get _needsGps =>
      _session?['name'] != 'Swimming' && _session?['name'] != 'Yoga';

  void _startTicker() {
    _ticker ??= Timer.periodic(const Duration(seconds: 1), (_) {
      if (_session == null || !isRunning) return;
      notifyListeners();
    });
  }

  Future<void> _startGpsStream() async {
    if (_positionSubscription != null || !isRunning) return;
    await _subscriptionCancellation;
    if (_positionSubscription != null || !isRunning) return;
    try {
      _positionSubscription = _positionStream(_locationSettings()).listen(
        _onPosition,
        onError: (Object error, StackTrace stack) {
          _positionSubscription = null;
          _setGpsStatus(
            error is PermissionDeniedException
                ? GpsStatus.deniedForever
                : GpsStatus.unavailable,
          );
        },
        cancelOnError: true,
      );
    } on Exception {
      _setGpsStatus(GpsStatus.unavailable);
    }
  }

  LocationSettings _locationSettings() {
    if (_isWeb) {
      return const LocationSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 5,
      );
    }
    return switch (_platform) {
      TargetPlatform.android => AndroidSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 5,
        intervalDuration: const Duration(seconds: 2),
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'Tracking your activity',
          notificationText: 'Fittract is measuring distance',
          enableWakeLock: true,
        ),
      ),
      TargetPlatform.iOS => AppleSettings(
        accuracy: LocationAccuracy.best,
        activityType: ActivityType.fitness,
        distanceFilter: 5,
        pauseLocationUpdatesAutomatically: false,
        showBackgroundLocationIndicator: true,
        allowBackgroundLocationUpdates: true,
      ),
      _ => const LocationSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 5,
      ),
    };
  }

  void _onPosition(Position position) {
    if (!isRunning) return;
    final previousLatitude = _session?['lastLatitude'] as num?;
    final previousLongitude = _session?['lastLongitude'] as num?;
    final previousAt = _session?['lastPositionAtMs'] as num?;
    if (!position.accuracy.isFinite || position.accuracy < 0) {
      _setGpsStatus(GpsStatus.weak);
      return;
    }

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    var positionAtMs = position.timestamp.millisecondsSinceEpoch;
    final hasPrevious =
        previousLatitude != null &&
        previousLongitude != null &&
        previousAt != null;
    var delta = 0.0;
    var elapsedSeconds = 0.0;
    var rebaseline = !hasPrevious || _needsRebaseline;

    if (hasPrevious) {
      delta = Geolocator.distanceBetween(
        previousLatitude.toDouble(),
        previousLongitude.toDouble(),
        position.latitude,
        position.longitude,
      );
      if (positionAtMs <= previousAt.toInt()) {
        positionAtMs = nowMs;
      }
      final elapsedMs = positionAtMs - previousAt.toInt();
      elapsedSeconds = math.max(1, elapsedMs) / 1000;
      if (elapsedSeconds > 60) rebaseline = true;
      if (rebaseline) {
        if (position.accuracy > 100) {
          _setGpsStatus(GpsStatus.weak);
          return;
        }
      } else {
        final maximumAccuracy = math.max(25.0, 2 * delta);
        if (position.accuracy > maximumAccuracy) {
          _setGpsStatus(GpsStatus.weak);
          return;
        }
      }
    } else if (position.accuracy > 100) {
      _setGpsStatus(GpsStatus.weak);
      return;
    }

    _setGpsStatus(GpsStatus.good);
    if (rebaseline) {
      _needsRebaseline = false;
      _session!['lastLatitude'] = position.latitude;
      _session!['lastLongitude'] = position.longitude;
      _session!['lastPositionAtMs'] = positionAtMs;
      _persist();
      notifyListeners();
      return;
    }

    if (delta < 3) return;
    final activityName = _session?['name'];
    final maxSpeed = activityName == 'Cycling' ? 30.0 : 12.0;
    if (delta / elapsedSeconds > maxSpeed) return;

    _session!['distanceMeters'] = distanceMeters + delta;
    _session!['lastLatitude'] = position.latitude;
    _session!['lastLongitude'] = position.longitude;
    _session!['lastPositionAtMs'] = positionAtMs;
    _persist();
    notifyListeners();
  }

  void _setGpsStatus(GpsStatus status) {
    if (_gpsStatus == status) return;
    _gpsStatus = status;
    if (_session != null) {
      _session!['gpsStatus'] = status.name;
      _persist();
    }
    notifyListeners();
  }

  Future<void> _cancelGpsStream() {
    final subscription = _positionSubscription;
    _positionSubscription = null;
    if (subscription == null) return _subscriptionCancellation;
    _subscriptionCancellation = subscription.cancel();
    return _subscriptionCancellation;
  }

  void pause() {
    if (!isRunning || _session == null) return;
    _session!['elapsedMs'] = elapsedMilliseconds;
    _session!['status'] = 'paused';
    _session!.remove('segmentStartedAtMs');
    _needsRebaseline = true;
    unawaited(_cancelGpsStream());
    _persist();
    notifyListeners();
  }

  void resume() {
    if (!isPaused || _session == null) return;
    _session!['status'] = 'tracking';
    _session!['segmentStartedAtMs'] = DateTime.now().millisecondsSinceEpoch;
    _persist();
    _startTicker();
    _needsRebaseline = true;
    unawaited(_resumeGpsIfPossible());
    notifyListeners();
  }

  void stop() {
    if (!isTracking || _session == null) return;
    _session!['elapsedMs'] = elapsedMilliseconds;
    _session!['status'] = 'stopped';
    _session!.remove('segmentStartedAtMs');
    _ticker?.cancel();
    _ticker = null;
    unawaited(_cancelGpsStream());
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
    return WeightEstimator.activeCaloriesFromMet(
      weightKg: weight,
      durationSeconds: durationSeconds,
      met: met,
    );
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
    final startedAt = _session!['startedAtMs'];
    final activityDate = startedAt is num
        ? DateTime.fromMillisecondsSinceEpoch(startedAt.toInt())
        : DateTime.now();
    final stepsCountedInDailyTotal =
        !dailyMovementTracking.hasPedometerReadingForToday;
    store.acts.add({
      'd': isoOf(activityDate),
      'n': name,
      'min': seconds == 0 ? 0 : math.max(1, (seconds / 60).round()),
      'durationSec': seconds,
      'km': distanceMetersToSave > 0
          ? double.parse((distanceMetersToSave / 1000).toStringAsFixed(2))
          : 0.0,
      'kc': caloriesFor(seconds),
      'st': steps,
      'stepsCounted': stepsCountedInDailyTotal,
      't': _session!['startedAtMs'],
    });
    if (stepsCountedInDailyTotal) {
      store.d['steps'] = store.steps + steps;
    }
    _clearSession();
    store.save();
  }

  void discard() {
    if (_session == null) return;
    _clearSession();
    store.save();
  }

  void _persist() {
    store.d['activeActivity'] = _session == null
        ? null
        : Map<String, dynamic>.from(_session!);
    _saveQuiet();
  }

  void _clearSession() {
    _ticker?.cancel();
    _ticker = null;
    unawaited(_cancelGpsStream());
    _session = null;
    store.d['activeActivity'] = null;
    notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (isRunning) unawaited(_resumeGpsIfPossible());
    } else if (_isWeb && isRunning) {
      unawaited(_cancelGpsStream());
    }
  }

  void observeLifecycle() {
    if (_observingLifecycle) return;
    WidgetsBinding.instance.addObserver(this);
    _observingLifecycle = true;
  }

  Future<void> openAppSettings() => Geolocator.openAppSettings();

  Future<void> openLocationSettings() => Geolocator.openLocationSettings();

  @override
  void dispose() {
    _ticker?.cancel();
    _ticker = null;
    unawaited(_cancelGpsStream());
    if (_observingLifecycle) {
      WidgetsBinding.instance.removeObserver(this);
      _observingLifecycle = false;
    }
    super.dispose();
  }
}

final activityTracking = ActivityTrackingService.instance;
