import 'dart:async';

import 'package:fittract/services/daily_movement_tracking_service.dart';
import 'package:fittract/store/store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final services = <DailyMovementTrackingService>[];
  final stepStreams = <StreamController<int>>[];
  final positionStreams = <StreamController<Position>>[];

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await store.init(rollDay: false);
    store.activateGoogleAccount(
      uid: 'daily-movement-test',
      email: 'daily-movement@example.com',
      displayName: 'Daily movement test',
    );
  });

  tearDown(() async {
    for (final service in services) {
      await service.stop();
    }
    for (final stream in stepStreams) {
      await stream.close();
    }
    for (final stream in positionStreams) {
      await stream.close();
    }
    services.clear();
    stepStreams.clear();
    positionStreams.clear();
  });

  DailyMovementTrackingService makeService({
    Future<bool> Function()? motionPermission,
    Future<bool> Function()? locationServiceEnabled,
    Future<LocationPermission> Function()? locationPermission,
    Future<LocationPermission> Function()? requestLocationPermission,
    void Function(LocationSettings settings)? onLocationSettings,
  }) {
    final steps = StreamController<int>.broadcast();
    final positions = StreamController<Position>.broadcast();
    stepStreams.add(steps);
    positionStreams.add(positions);
    final service = DailyMovementTrackingService.forTesting(
      stepStream: () => steps.stream,
      positionStream: (settings) {
        onLocationSettings?.call(settings);
        return positions.stream;
      },
      motionPermission: motionPermission ?? () async => true,
      locationServiceEnabled: locationServiceEnabled ?? () async => true,
      locationPermission:
          locationPermission ?? () async => LocationPermission.whileInUse,
      requestLocationPermission:
          requestLocationPermission ??
          () async => LocationPermission.whileInUse,
    );
    services.add(service);
    return service;
  }

  Position fix(double latitude, DateTime timestamp, {double accuracy = 5}) =>
      Position(
        longitude: 0,
        latitude: latitude,
        timestamp: timestamp,
        accuracy: accuracy,
        altitude: 0,
        altitudeAccuracy: 0,
        heading: 0,
        headingAccuracy: 0,
        speed: 0,
        speedAccuracy: 0,
      );

  Future<void> flushEvents() => Future<void>.delayed(Duration.zero);

  test('adds sensor step deltas once and persists daily totals', () async {
    final service = makeService();
    await service.enableAndStart();

    stepStreams.single.add(100);
    await flushEvents();
    stepStreams.single.add(107);
    await flushEvents();
    stepStreams.single.add(107);
    await flushEvents();

    expect(store.steps, 7);
    final saved = await store.readStoredAccount(
      'ft_account_daily-movement-test',
    );
    expect(saved, isNotNull);
    expect(saved!['steps'], 7);
  });

  test('resumes the saved sensor baseline without duplicate steps', () async {
    final firstService = makeService();
    await firstService.enableAndStart();
    stepStreams[0].add(200);
    await flushEvents();
    stepStreams[0].add(204);
    await flushEvents();
    await firstService.stop();

    final resumedService = makeService();
    await resumedService.startIfEnabled();
    stepStreams[1].add(207);
    await flushEvents();

    expect(store.steps, 7);
  });

  test(
    'accumulates reasonable GPS distance and ignores inaccurate fixes',
    () async {
      final service = makeService();
      await service.enableAndStart();
      final start = DateTime.now().subtract(const Duration(seconds: 10));

      positionStreams.single.add(fix(0, start));
      await flushEvents();
      positionStreams.single.add(
        fix(0.0001, start.add(const Duration(seconds: 5))),
      );
      await flushEvents();

      expect(service.distanceMeters, closeTo(11.1, 1));
      positionStreams.single.add(
        fix(0.0002, start.add(const Duration(seconds: 10)), accuracy: 150),
      );
      await flushEvents();
      expect(service.distanceMeters, closeTo(11.1, 1));

      final saved = await store.readStoredAccount(
        'ft_account_daily-movement-test',
      );
      expect((saved!['distanceMeters'] as num).toDouble(), closeTo(11.1, 1));
    },
  );

  test('filters GPS jitter using the reported fix accuracy', () async {
    LocationSettings? settings;
    final service = makeService(
      onLocationSettings: (value) => settings = value,
    );
    await service.enableAndStart();
    final start = DateTime.now().subtract(const Duration(seconds: 10));

    positionStreams.single.add(fix(0, start, accuracy: 8));
    await flushEvents();
    positionStreams.single.add(
      fix(0.00005, start.add(const Duration(seconds: 3)), accuracy: 8),
    );
    await flushEvents();
    expect(service.distanceMeters, 0);

    positionStreams.single.add(
      fix(0.00012, start.add(const Duration(seconds: 8)), accuracy: 8),
    );
    await flushEvents();

    expect(service.distanceMeters, closeTo(13.3, 0.2));
    expect(service.gpsStatus, DailyGpsStatus.good);
    expect(service.statusMessage, contains('accuracy ±8 m'));
    expect(settings?.accuracy, LocationAccuracy.best);
    expect(settings?.distanceFilter, 3);
  });

  test('rejects stale, invalid, and out-of-order GPS fixes', () async {
    final service = makeService();
    await service.enableAndStart();
    final start = DateTime.now().subtract(const Duration(seconds: 20));

    positionStreams.single.add(fix(0, start));
    await flushEvents();
    positionStreams.single.add(
      fix(0.0005, DateTime.now().subtract(const Duration(minutes: 2))),
    );
    await flushEvents();
    positionStreams.single.add(
      fix(double.nan, start.add(const Duration(seconds: 5))),
    );
    await flushEvents();
    expect(service.distanceMeters, 0);

    positionStreams.single.add(
      fix(0.0001, start.add(const Duration(seconds: 10))),
    );
    await flushEvents();
    expect(service.distanceMeters, closeTo(11.1, 1));

    positionStreams.single.add(
      fix(0.0002, start.add(const Duration(seconds: 8))),
    );
    await flushEvents();
    expect(service.distanceMeters, closeTo(11.1, 1));

    positionStreams.single.add(
      fix(0.0002, start.add(const Duration(seconds: 20))),
    );
    await flushEvents();
    expect(service.distanceMeters, closeTo(22.2, 1));
  });

  test(
    'requests location permission and does not start GPS when denied',
    () async {
      var permissionRequests = 0;
      var gpsStarted = false;
      final service = makeService(
        locationPermission: () async => LocationPermission.denied,
        requestLocationPermission: () async {
          permissionRequests++;
          return LocationPermission.denied;
        },
        onLocationSettings: (_) => gpsStarted = true,
      );

      await service.enableAndStart();

      expect(permissionRequests, 1);
      expect(gpsStarted, isFalse);
      expect(service.gpsStatus, DailyGpsStatus.denied);
      expect(service.locationError, contains('Allow location access'));
    },
  );

  test('archives steps and distance on daily rollover', () async {
    final service = makeService();
    store.d['day'] = daysAgo(1);
    store.d['steps'] = 12;
    store.d['distanceMeters'] = 35.5;
    await service.enableAndStart();

    stepStreams.single.add(100);
    await flushEvents();

    expect(store.steps, 0);
    expect(store.d['distanceMeters'], 0);
    final log = store.d['log'] as List;
    expect(log.single['steps'], 12);
    expect(log.single['distanceMeters'], 35.5);
  });
}
