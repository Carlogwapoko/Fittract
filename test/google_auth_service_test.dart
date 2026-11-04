import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:fittract/services/google_auth_service.dart';

void main() {
  tearDown(GoogleAuthService.resetGoogleSignInInitializationForTesting);

  test('concurrent requests share one Google Sign-In initialization', () async {
    final initialization = Completer<void>();
    var initializeCalls = 0;
    GoogleAuthService.debugGoogleSignInInitializeOverride = () {
      initializeCalls++;
      return initialization.future;
    };

    final first = GoogleAuthService.initializeGoogleSignInForTesting();
    final second = GoogleAuthService.initializeGoogleSignInForTesting();

    expect(initializeCalls, 1);
    initialization.complete();
    await Future.wait([first, second]);
    expect(initializeCalls, 1);
  });

  test('a failed initialization can be retried', () async {
    var initializeCalls = 0;
    final initializationError = StateError('initialization failed');
    GoogleAuthService.debugGoogleSignInInitializeOverride = () {
      initializeCalls++;
      if (initializeCalls == 1) {
        return Future<void>.error(initializationError);
      }
      return Future<void>.value();
    };

    await expectLater(
      GoogleAuthService.initializeGoogleSignInForTesting(),
      throwsA(same(initializationError)),
    );
    await GoogleAuthService.initializeGoogleSignInForTesting();

    expect(initializeCalls, 2);
  });
}
