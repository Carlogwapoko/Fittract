import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:geolocator/geolocator.dart';
import 'package:pedometer/pedometer.dart';
import 'package:permission_handler/permission_handler.dart';

import '../store/store.dart';

enum DailyGpsStatus {
  searching,
  good,
  weak,
  denied,
  deniedForever,
  serviceOff,
  unavailable,
}

const _maxDailyGpsAccuracyMeters = 25.0;
const _maxDailyGpsFixAge = Duration(seconds: 30);
const _maxDailyGpsFutureSkew = Duration(seconds: 5);
const _maxDailyGpsSpeedMetersPerSecond = 6.0;

typedef DailyStepStreamFactory = Stream<int> Function();
typedef DailyPositionStreamFactory = Stream<Position> Function(
  LocationSettings settings,
);

class DailyMovementTrackingService with WidgetsBindingObserver, ChangeNotifier {
  DailyMovementTrackingService._({
    DailyStepStreamFactory? stepStream,
    DailyPositionStreamFactory? positionStream,
    Future<bool> Function()? motionPermission,
    Future<bool> Function()? locationServiceEnabled,
    Future<LocationPermission> Function()? locationPermission,
    Future<LocationPermission> Function()? requestLocationPermission,
    VoidCallback? saveQuiet,
  }) : _stepStream =
           stepStream ??
           (() => Pedometer.stepCountStream.map((event) => event.steps)),
       _positionStream =
           positionStream ??
           ((settings) =>
               Geolocator.getPositionStream(locationSettings: settings)),
       _motionPermission = motionPermission ?? _requestMotionPermission,
       _locationServiceEnabled =
           locationServiceEnabled ?? Geolocator.isLocationServiceEnabled,
       _locationPermission = locationPermission ?? Geolocator.checkPermission,
       _requestLocationPermission =
           requestLocationPermission ?? Geolocator.requestPermission,
       _saveQuiet = saveQuiet ?? store.saveQuiet;

  static final instance = DailyMovementTrackingService._();

  @visibleForTesting
  factory DailyMovementTrackingService.forTesting({
    required DailyStepStreamFactory stepStream,
    required DailyPositionStreamFactory positionStream,
    required Future<bool> Function() motionPermission,
    required Future<bool> Function() locationServiceEnabled,
    required Future<LocationPermission> Function() locationPermission,
    required Future<LocationPermission> Function() requestLocationPermission,
    VoidCallback? saveQuiet,
  }) => DailyMovementTrackingService._(
    stepStream: stepStream,
    positionStream: positionStream,
    motionPermission: motionPermission,
    locationServiceEnabled: locationServiceEnabled,
    locationPermission: locationPermission,
    requestLocationPermission: requestLocationPermission,
    saveQuiet: saveQuiet,
  );

  final DailyStepStreamFactory _stepStream;
  final DailyPositionStreamFactory _positionStream;
  final Future<bool> Function() _motionPermission;
  final Future<bool> Function() _locationServiceEnabled;
  final Future<LocationPermission> Function() _locationPermission;
  final Future<LocationPermission> Function() _requestLocationPermission;
  final VoidCallback _saveQuiet;

  StreamSubscription<int>? _stepSubscription;
  StreamSubscription<Position>? _positionSubscription;
  Future<void>? _startFuture;
  String? _startingAccountToken;
  int? _startingGeneration;
  String? _accountKey;
  String? _stepError;
  String? _locationError;
  DailyGpsStatus _gpsStatus = DailyGpsStatus.unavailable;
  double? _lastLatitude;
  double? _lastLongitude;
  DateTime? _lastPositionAt;
  double? _lastPositionAccuracyMeters;
  double? _lastGpsAccuracyMeters;
  int _generation = 0;
  bool _hasStepReadingToday = false;
  bool _observingLifecycle = false;
  bool _disposed = false;

  bool get isStepTracking => _stepSubscription != null;
  bool get isGpsTracking => _positionSubscription != null;
  bool get hasPedometerReadingForToday =>
      _hasStepReadingToday && _readLocalDay() == today();
  double get distanceMeters =>
      (store.d['distanceMeters'] as num?)?.toDouble() ?? 0;
  String? get stepError => _stepError;
  String? get locationError => _locationError;
  DailyGpsStatus get gpsStatus => _gpsStatus;
  bool get canOpenSettings => !kIsWeb;

  bool get hasConsentForCurrentAccount {
    if (!store.isInitialized || !store.hasActiveSession) return false;
    return store.sp.getBool(_consentKey(_currentAccountToken)) ?? false;
  }

  String get statusMessage {
    if (!hasConsentForCurrentAccount) {
      return 'Automatic step and distance tracking is off.';
    }
    if (isStepTracking && isGpsTracking) {
      final gpsMessage = switch (_gpsStatus) {
        DailyGpsStatus.searching => 'Waiting for a GPS fix.',
        DailyGpsStatus.good =>
          'GPS is live${_lastGpsAccuracyMeters == null ? '' : ' · accuracy ±${_lastGpsAccuracyMeters!.toStringAsFixed(0)} m'}.',
        DailyGpsStatus.weak =>
          'GPS accuracy is low. Move outdoors for a stronger signal.',
        _ => 'GPS distance tracking is unavailable.',
      };
      return 'Step sensor is live. $gpsMessage';
    }
    final messages = <String>[
      ?_stepError,
      ?_locationError,
      if (_stepError == null && !isStepTracking) 'Waiting for the step sensor.',
      if (_locationError == null && !isGpsTracking)
        _gpsStatus == DailyGpsStatus.serviceOff
            ? 'Turn on location services to track distance.'
            : 'Waiting for GPS.',
    ];
    return messages.join(' ');
  }

  String get _currentAccountToken {
    final uid = store.sessionUid;
    final localIdentity = store.d['user'];
    final identity =
        uid ??
        (localIdentity is String && localIdentity.isNotEmpty
            ? localIdentity
            : 'local-account');
    return sha256.convert(utf8.encode(identity)).toString().substring(0, 20);
  }

  String _consentKey(String token) => 'ft_daily_tracking_consent_$token';
  String _counterKey(String token) => 'ft_daily_step_counter_$token';
  String _counterDayKey(String token) => 'ft_daily_step_day_$token';

  String? _readLocalDay() {
    if (!store.isInitialized || !store.hasActiveSession) return null;
    return store.sp.getString(_counterDayKey(_currentAccountToken));
  }

  Future<void> startIfEnabled() async {
    if (!store.isInitialized || !store.hasActiveSession) {
      await stop();
      return;
    }
    final token = _currentAccountToken;
    if (!(store.sp.getBool(_consentKey(token)) ?? false)) {
      if (_accountKey != null) await stop();
      return;
    }
    await _startForAccount(token);
  }

  Future<void> enableAndStart() async {
    if (!store.isInitialized || !store.hasActiveSession) return;
    final token = _currentAccountToken;
    await store.sp.setBool(_consentKey(token), true);
    await _startForAccount(token);
  }

  Future<void> disableAndStop() async {
    if (store.isInitialized && store.hasActiveSession) {
      await store.sp.setBool(_consentKey(_currentAccountToken), false);
    }
    await stop();
  }

  Future<void> stop() async {
    _generation++;
    _accountKey = null;
    await _stopStreams();
    if (_observingLifecycle) {
      WidgetsBinding.instance.removeObserver(this);
      _observingLifecycle = false;
    }
    _hasStepReadingToday = false;
    _notify();
  }

  Future<void> _startForAccount(String token) {
    return _startForAccountSerially(token);
  }

  Future<void> _startForAccountSerially(String token) async {
    while (true) {
      final pending = _startFuture;
      if (pending != null) {
        final pendingToken = _startingAccountToken;
        final pendingGeneration = _startingGeneration;
        if (pendingToken != token) {
          _generation++;
          _accountKey = null;
          await _stopStreams();
        }
        await pending;
        if (pendingToken == token && pendingGeneration == _generation) return;
        continue;
      }

      final start = _start(token);
      _startFuture = start;
      _startingAccountToken = token;
      _startingGeneration = _generation;
      try {
        await start;
      } finally {
        if (identical(_startFuture, start)) {
          _startFuture = null;
          _startingAccountToken = null;
          _startingGeneration = null;
        }
      }
      return;
    }
  }

  Future<void> _start(String token) async {
    if (_accountKey != token) {
      _generation++;
      final generation = _generation;
      final stoppingStreams = _stopStreams();
      _accountKey = token;
      _hasStepReadingToday = false;
      _lastLatitude = null;
      _lastLongitude = null;
      _lastPositionAt = null;
      _lastPositionAccuracyMeters = null;
      _lastGpsAccuracyMeters = null;
      await stoppingStreams;
      if (generation != _generation || token != _accountKey) return;
    }
    if (!_observingLifecycle) {
      WidgetsBinding.instance.addObserver(this);
      _observingLifecycle = true;
    }
    if (isStepTracking && isGpsTracking) return;
    final generation = _generation;
    _stepError = null;
    _locationError = null;

    if (!isStepTracking) {
      try {
        if (await _motionPermission()) {
          if (generation != _generation) return;
          _stepSubscription = _stepStream().listen(
            (steps) => _onStepCount(steps, token, generation),
            onError: (Object error, StackTrace stackTrace) {
              if (generation != _generation) return;
              _stepSubscription = null;
              _stepError = 'The device step sensor is unavailable.';
              debugPrint('Daily step sensor failed: $error\n$stackTrace');
              _notify();
            },
            cancelOnError: true,
          );
        } else {
          _stepError = 'Allow motion access to count steps.';
        }
      } on Exception catch (error, stackTrace) {
        _stepError = 'Could not start the device step sensor.';
        debugPrint('Daily step sensor could not start: $error\n$stackTrace');
      }
    }

    if (!isGpsTracking) {
      try {
        if (!await _locationServiceEnabled()) {
          _gpsStatus = DailyGpsStatus.serviceOff;
        } else {
          var permission = await _locationPermission();
          if (permission == LocationPermission.denied) {
            permission = await _requestLocationPermission();
          }
          if (generation != _generation) return;
          _gpsStatus = _permissionStatus(permission);
          if (_gpsStatus == DailyGpsStatus.searching) {
            _positionSubscription =
                _positionStream(
                  const LocationSettings(
                    accuracy: LocationAccuracy.best,
                    distanceFilter: 3,
                  ),
                ).listen(
                  (position) => _onPosition(position, token, generation),
                  onError: (Object error, StackTrace stackTrace) {
                    if (generation != _generation) return;
                    _positionSubscription = null;
                    _gpsStatus = error is PermissionDeniedException
                        ? DailyGpsStatus.deniedForever
                        : DailyGpsStatus.unavailable;
                    _lastGpsAccuracyMeters = null;
                    _locationError = 'GPS distance tracking is unavailable.';
                    debugPrint('Daily GPS stream failed: $error\n$stackTrace');
                    _notify();
                  },
                  cancelOnError: true,
                );
          } else {
            _locationError = switch (_gpsStatus) {
              DailyGpsStatus.denied =>
                'Allow location access to track distance.',
              DailyGpsStatus.deniedForever =>
                'Allow location access in device settings to track distance.',
              DailyGpsStatus.serviceOff =>
                'Turn on location services to track distance.',
              _ => 'GPS distance tracking is unavailable.',
            };
          }
        }
      } on Exception catch (error, stackTrace) {
        if (generation != _generation) return;
        _gpsStatus = DailyGpsStatus.unavailable;
        _locationError = 'Could not start GPS distance tracking.';
        debugPrint('Daily GPS could not start: $error\n$stackTrace');
      }
    }
    _notify();
  }

  static Future<bool> _requestMotionPermission() async {
    if (kIsWeb) return false;
    final permission = switch (defaultTargetPlatform) {
      TargetPlatform.android => Permission.activityRecognition,
      TargetPlatform.iOS => Permission.sensors,
      _ => null,
    };
    if (permission == null) return false;
    var status = await permission.status;
    if (!status.isGranted) status = await permission.request();
    return status.isGranted;
  }

  DailyGpsStatus _permissionStatus(LocationPermission permission) =>
      switch (permission) {
        LocationPermission.denied => DailyGpsStatus.denied,
        LocationPermission.deniedForever => DailyGpsStatus.deniedForever,
        LocationPermission.whileInUse ||
        LocationPermission.always => DailyGpsStatus.searching,
        LocationPermission.unableToDetermine => DailyGpsStatus.unavailable,
      };

  void _onStepCount(int rawSteps, String token, int generation) {
    if (generation != _generation || token != _accountKey || rawSteps < 0) {
      return;
    }
    store.roll();
    final day = today();
    final dayKey = _counterDayKey(token);
    final counterKey = _counterKey(token);
    final savedDay = store.sp.getString(dayKey);
    final previous = store.sp.getInt(counterKey);
    _hasStepReadingToday = true;
    if (savedDay == day && previous != null && rawSteps >= previous) {
      final delta = rawSteps - previous;
      if (delta > 0) {
        store.d['steps'] = store.steps + delta;
        _saveQuiet();
      }
    }
    unawaited(store.sp.setString(dayKey, day));
    unawaited(store.sp.setInt(counterKey, rawSteps));
    _notify();
  }

  void _onPosition(Position position, String token, int generation) {
    if (generation != _generation || token != _accountKey) return;
    store.roll();
    final accuracy = position.accuracy;
    final latitude = position.latitude;
    final longitude = position.longitude;
    final positionTime = position.timestamp;
    final now = DateTime.now();
    _lastGpsAccuracyMeters = accuracy.isFinite && accuracy >= 0
        ? accuracy
        : null;
    if (!latitude.isFinite ||
        latitude < -90 ||
        latitude > 90 ||
        !longitude.isFinite ||
        longitude < -180 ||
        longitude > 180 ||
        !accuracy.isFinite ||
        accuracy < 0 ||
        accuracy > _maxDailyGpsAccuracyMeters ||
        now.difference(positionTime) > _maxDailyGpsFixAge ||
        positionTime.isAfter(now.add(_maxDailyGpsFutureSkew))) {
      _gpsStatus = DailyGpsStatus.weak;
      _notify();
      return;
    }
    final previousLatitude = _lastLatitude;
    final previousLongitude = _lastLongitude;
    final previousAt = _lastPositionAt;
    if (previousLatitude == null ||
        previousLongitude == null ||
        previousAt == null ||
        isoOf(previousAt) != today()) {
      _setGpsBaseline(latitude, longitude, positionTime, accuracy);
      return;
    }
    final elapsedMilliseconds = positionTime
        .difference(previousAt)
        .inMilliseconds;
    if (elapsedMilliseconds <= 0) {
      _gpsStatus = DailyGpsStatus.weak;
      _notify();
      return;
    }
    if (elapsedMilliseconds > const Duration(seconds: 60).inMilliseconds) {
      _setGpsBaseline(latitude, longitude, positionTime, accuracy);
      return;
    }

    final delta = Geolocator.distanceBetween(
      previousLatitude,
      previousLongitude,
      latitude,
      longitude,
    );
    final elapsedSeconds = elapsedMilliseconds / 1000;
    final previousAccuracy = _lastPositionAccuracyMeters;
    final minimumMovementMeters = math.max(
      3.0,
      ((previousAccuracy ?? accuracy) + accuracy) / 2,
    );
    if (!delta.isFinite) {
      _gpsStatus = DailyGpsStatus.weak;
      _notify();
      return;
    }
    if (delta < minimumMovementMeters) {
      _gpsStatus = DailyGpsStatus.good;
      _notify();
      return;
    }
    if (delta / elapsedSeconds > _maxDailyGpsSpeedMetersPerSecond) {
      _gpsStatus = DailyGpsStatus.weak;
      _notify();
      return;
    }

    _gpsStatus = DailyGpsStatus.good;
    _lastLatitude = latitude;
    _lastLongitude = longitude;
    _lastPositionAt = positionTime;
    _lastPositionAccuracyMeters = accuracy;
    store.d['distanceMeters'] = distanceMeters + delta;
    _saveQuiet();
    _notify();
  }

  void _setGpsBaseline(
    double latitude,
    double longitude,
    DateTime positionTime,
    double accuracy,
  ) {
    _gpsStatus = DailyGpsStatus.good;
    _lastLatitude = latitude;
    _lastLongitude = longitude;
    _lastPositionAt = positionTime;
    _lastPositionAccuracyMeters = accuracy;
    _notify();
  }

  Future<void> _stopStreams() async {
    final stepSubscription = _stepSubscription;
    final positionSubscription = _positionSubscription;
    _stepSubscription = null;
    _positionSubscription = null;
    _lastLatitude = null;
    _lastLongitude = null;
    _lastPositionAt = null;
    _lastPositionAccuracyMeters = null;
    _lastGpsAccuracyMeters = null;
    await Future.wait([
      ?stepSubscription?.cancel(),
      ?positionSubscription?.cancel(),
    ]);
  }

  Future<void> openSettings() async {
    await openAppSettings();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _generation++;
      unawaited(_stopStreams());
    } else if (state == AppLifecycleState.resumed) {
      unawaited(startIfEnabled());
    }
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(stop());
    super.dispose();
  }
}

final dailyMovementTracking = DailyMovementTrackingService.instance;
