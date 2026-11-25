import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
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

  test(
    'Android signs in with a Google ID token through Firebase Auth',
    () async {
      GoogleAuthService.debugTargetPlatformOverride = TargetPlatform.android;
      GoogleAuthService.debugFirebaseInitializeOverride = () async {};
      GoogleAuthService.debugGoogleSignInInitializeOverride = () async {};
      GoogleAuthService.debugGoogleIdTokenOverride = () async =>
          'google-id-token';

      GoogleAuthService.debugFirebaseCredentialSignInOverride =
          (credential) async {
            expect(credential, isA<OAuthCredential>());
            expect(credential.providerId, GoogleAuthProvider.PROVIDER_ID);
            expect((credential as OAuthCredential).idToken, 'google-id-token');
            return const GoogleAuthAccount(
              uid: 'android-user',
              email: 'android@example.com',
              displayName: 'Android User',
            );
          };

      final account = await GoogleAuthService().signIn();

      expect(account.uid, 'android-user');
      expect(account.email, 'android@example.com');
    },
  );

  test(
    'Android reports a missing Google ID token before Firebase sign-in',
    () async {
      GoogleAuthService.debugTargetPlatformOverride = TargetPlatform.android;
      GoogleAuthService.debugFirebaseInitializeOverride = () async {};
      GoogleAuthService.debugGoogleSignInInitializeOverride = () async {};
      GoogleAuthService.debugGoogleIdTokenOverride = () async => null;
      var credentialSignInCalls = 0;
      GoogleAuthService.debugFirebaseCredentialSignInOverride = (_) async {
        credentialSignInCalls++;
        throw StateError(
          'Firebase sign-in should not run without an ID token.',
        );
      };

      await expectLater(
        GoogleAuthService().signIn(),
        throwsA(
          isA<FirebaseAuthException>().having(
            (error) => error.code,
            'code',
            'missing-google-id-token',
          ),
        ),
      );

      expect(credentialSignInCalls, 0);
    },
  );
}
