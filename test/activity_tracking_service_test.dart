import 'dart:async';

import 'package:fittract/services/activity_tracking_service.dart';
import 'package:fittract/store/store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';
import 'package:geolocator/geolocator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final services = <ActivityTrackingService>[];

  setUp(() {
    store.d = {};
  });

  tearDown(() {
    for (final service in services) {
      service.dispose();
    }
    services.clear();
    store.d = {};
  });

  ActivityTrackingService makeService({
    required StreamController<Position> positions,
    LocationPermission permission = LocationPermission.whileInUse,
    bool locationEnabled = true,
    TargetPlatform platform = TargetPlatform.android,
    bool isWeb = false,
    Future<LocationPermission> Function()? permissionRequest,
    void Function(LocationSettings settings)? onSettings,
  }) {
    final service = ActivityTrackingService.forTesting(
      positionStream: (settings) {
        onSettings?.call(settings);
        return positions.stream;
      },
      locationServiceEnabled: () async => locationEnabled,
      permissionCheck: () async => permission,
      permissionRequest: permissionRequest ?? () async => permission,
      platform: platform,
      isWeb: isWeb,
      saveQuiet: () {},
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

  Future<void> send(
    StreamController<Position> stream,
    Position position,
  ) async {
    stream.add(position);
    await Future<void>.delayed(Duration.zero);
  }

  test('accumulates distance across valid fixes', () async {
    final positions = StreamController<Position>.broadcast();
    final service = makeService(positions: positions);
    final start = DateTime.now().subtract(const Duration(seconds: 10));

    await service.start('Brisk walk');
    await send(positions, fix(0, start));
    await send(positions, fix(0.0001, start.add(const Duration(seconds: 5))));

    expect(service.distanceMeters, closeTo(11.1, 1));
    expect(service.gpsStatus, GpsStatus.good);
  });

  test('accepts a first fix with 60 metre accuracy', () async {
    final positions = StreamController<Position>.broadcast();
    final service = makeService(positions: positions);

    await service.start('Brisk walk');
    await send(positions, fix(0, DateTime.now(), accuracy: 60));

    expect(service.gpsStatus, GpsStatus.good);
    expect(service.session?['lastLatitude'], 0);
    expect(service.distanceMeters, 0);
  });

  test('allows accuracy up to twice the movement delta', () async {
    final positions = StreamController<Position>.broadcast();
    final service = makeService(positions: positions);
    final start = DateTime.now().subtract(const Duration(seconds: 10));

    await service.start('Brisk walk');
    await send(positions, fix(0, start));
    await send(
      positions,
      fix(0.0002, start.add(const Duration(seconds: 5)), accuracy: 30),
    );

    expect(service.distanceMeters, closeTo(22.2, 1));
  });

  test('rejects a jump above the maximum walking speed', () async {
    final positions = StreamController<Position>.broadcast();
    final service = makeService(positions: positions);
    final start = DateTime.now().subtract(const Duration(seconds: 20));

    await service.start('Brisk walk');
    await send(positions, fix(0, start));
    await send(positions, fix(0.001, start.add(const Duration(seconds: 1))));

    expect(service.distanceMeters, 0);
    expect(service.session?['lastLatitude'], 0);
  });

  test('uses the current time when fix timestamps do not increase', () async {
    final positions = StreamController<Position>.broadcast();
    final service = makeService(positions: positions);
    final start = DateTime.now().subtract(const Duration(seconds: 30));
    final secondTimestamp = start.add(const Duration(seconds: 5));

    await service.start('Brisk walk');
    await send(positions, fix(0, start));
    await send(positions, fix(0.0001, secondTimestamp));
    await send(positions, fix(0.0002, secondTimestamp));

    expect(service.distanceMeters, greaterThan(20));
  });

  test(
    're-baselines after pause and resume without counting the gap',
    () async {
      final positions = StreamController<Position>.broadcast();
      final service = makeService(positions: positions);
      final start = DateTime.now().subtract(const Duration(seconds: 20));

      await service.start('Brisk walk');
      await send(positions, fix(0, start));
      await send(positions, fix(0.0001, start.add(const Duration(seconds: 5))));
      final beforePause = service.distanceMeters;

      service.pause();
      await Future<void>.delayed(Duration.zero);
      service.resume();
      await Future<void>.delayed(Duration.zero);
      await send(
        positions,
        fix(0.001, DateTime.now().subtract(const Duration(seconds: 2))),
      );

      expect(service.distanceMeters, beforePause);
    },
  );

  test('re-baselines after a position gap longer than 60 seconds', () async {
    final positions = StreamController<Position>.broadcast();
    final service = makeService(positions: positions);
    final start = DateTime.now().subtract(const Duration(minutes: 2));

    await service.start('Brisk walk');
    await send(positions, fix(0, start));
    await send(positions, fix(0.001, start.add(const Duration(seconds: 61))));

    expect(service.distanceMeters, 0);
    expect(service.session?['lastLatitude'], 0.001);
  });

  test('reports searching, weak, denied and service-off statuses', () async {
    final searchingPositions = StreamController<Position>.broadcast();
    final searching = makeService(positions: searchingPositions);
    await searching.start('Brisk walk');
    expect(searching.gpsStatus, GpsStatus.searching);
    await send(searchingPositions, fix(0, DateTime.now(), accuracy: 101));
    expect(searching.gpsStatus, GpsStatus.weak);

    final deniedPositions = StreamController<Position>.broadcast();
    final denied = makeService(
      positions: deniedPositions,
      permission: LocationPermission.denied,
    );
    await denied.start('Brisk walk');
    expect(denied.gpsStatus, GpsStatus.denied);

    final deniedForeverPositions = StreamController<Position>.broadcast();
    final deniedForever = makeService(
      positions: deniedForeverPositions,
      permission: LocationPermission.deniedForever,
    );
    await deniedForever.start('Brisk walk');
    expect(deniedForever.gpsStatus, GpsStatus.deniedForever);

    final offPositions = StreamController<Position>.broadcast();
    final off = makeService(positions: offPositions, locationEnabled: false);
    await off.start('Brisk walk');
    expect(off.gpsStatus, GpsStatus.serviceOff);
  });

  test(
    'lets the browser stream request a pending location permission',
    () async {
      final positions = StreamController<Position>.broadcast();
      var permissionRequests = 0;
      var streamStarted = false;
      final service = ActivityTrackingService.forTesting(
        positionStream: (_) {
          streamStarted = true;
          return positions.stream;
        },
        locationServiceEnabled: () async => true,
        permissionCheck: () async => LocationPermission.denied,
        permissionRequest: () async {
          permissionRequests++;
          return LocationPermission.deniedForever;
        },
        platform: TargetPlatform.android,
        isWeb: true,
        saveQuiet: () {},
      );
      services.add(service);

      await service.start('Brisk walk');

      expect(service.gpsStatus, GpsStatus.searching);
      expect(permissionRequests, 0);
      expect(streamStarted, isTrue);
      await send(positions, fix(0, DateTime.now()));
      expect(service.gpsStatus, GpsStatus.good);
    },
  );

  test(
    'explains blocked Chrome location without opening app settings',
    () async {
      final positions = StreamController<Position>.broadcast();
      final service = makeService(
        positions: positions,
        permission: LocationPermission.deniedForever,
        isWeb: true,
      );

      await service.start('Brisk walk');

      expect(service.gpsStatus, GpsStatus.deniedForever);
      expect(service.gpsMessage, contains('localhost or HTTPS'));
      expect(service.canOpenAppSettings, isFalse);
    },
  );

  test(
    'keeps foreground tracking when background permission is declined',
    () async {
      final positions = StreamController<Position>.broadcast();
      var backgroundRequestCount = 0;
      final service = ActivityTrackingService.forTesting(
        positionStream: (_) => positions.stream,
        locationServiceEnabled: () async => true,
        permissionCheck: () async => LocationPermission.whileInUse,
        permissionRequest: () async {
          backgroundRequestCount++;
          return LocationPermission.deniedForever;
        },
        platform: TargetPlatform.android,
        saveQuiet: () {},
      );
      services.add(service);

      await service.start(
        'Brisk walk',
        confirmBackgroundPermission: () async => true,
      );

      expect(backgroundRequestCount, 1);
      expect(service.gpsStatus, GpsStatus.searching);
    },
  );

  test(
    'does not cancel mobile tracking on inactive or paused lifecycle',
    () async {
      var cancellations = 0;
      final positions = StreamController<Position>.broadcast(
        onCancel: () => cancellations++,
      );
      final service = makeService(positions: positions);

      await service.start('Brisk walk');
      service.didChangeAppLifecycleState(AppLifecycleState.inactive);
      service.didChangeAppLifecycleState(AppLifecycleState.paused);

      expect(cancellations, 0);
      service.stop();
      await Future<void>.delayed(Duration.zero);
      expect(cancellations, 1);
    },
  );

  test('start and restore never create duplicate subscriptions', () async {
    final positions = StreamController<Position>.broadcast();
    var subscriptions = 0;
    final service = makeService(
      positions: positions,
      onSettings: (_) => subscriptions++,
    );

    await Future.wait([
      service.start('Brisk walk'),
      service.start('Brisk walk'),
    ]);
    await service.restore();

    expect(subscriptions, 1);
  });

  test('restoring an active session restarts GPS tracking', () async {
    final positions = StreamController<Position>.broadcast();
    var settingsUsed = false;
    final service = makeService(
      positions: positions,
      onSettings: (settings) {
        settingsUsed =
            settings is AndroidSettings &&
            settings.foregroundNotificationConfig != null;
      },
    );
    store.d['activeActivity'] = {
      'name': 'Brisk walk',
      'status': 'tracking',
      'startedAtMs': DateTime.now().millisecondsSinceEpoch,
      'segmentStartedAtMs': DateTime.now().millisecondsSinceEpoch,
      'elapsedMs': 0,
      'distanceMeters': 25.0,
    };

    await service.restore();

    expect(settingsUsed, isTrue);
    expect(service.gpsStatus, GpsStatus.searching);
  });
}
