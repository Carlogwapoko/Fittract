import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'package:fittract/services/google_auth_service.dart';

void main() {
  group('googleAuthErrorMessage — Google sign-in errors', () {
    test('cancellation maps to an empty message (silent outcome)', () {
      expect(
        googleAuthErrorMessage(
          const GoogleSignInException(
            code: GoogleSignInExceptionCode.canceled,
          ),
        ),
        '',
      );
    });

    test('client configuration errors point at OAuth setup', () {
      expect(
        googleAuthErrorMessage(
          const GoogleSignInException(
            code: GoogleSignInExceptionCode.clientConfigurationError,
            description: 'serverClientId must be provided on Android',
          ),
        ),
        'Google sign-in is not configured. Check your Firebase Android app '
        'and OAuth client settings.',
      );
    });

    test('provider configuration errors point at the Google provider', () {
      expect(
        googleAuthErrorMessage(
          const GoogleSignInException(
            code: GoogleSignInExceptionCode.providerConfigurationError,
          ),
        ),
        'Google sign-in is unavailable. Check your Firebase Android app and '
        'Google provider settings.',
      );
    });

    test('other codes surface their description when present', () {
      for (final code in [
        GoogleSignInExceptionCode.unknownError,
        GoogleSignInExceptionCode.interrupted,
        GoogleSignInExceptionCode.uiUnavailable,
        GoogleSignInExceptionCode.userMismatch,
      ]) {
        expect(
          googleAuthErrorMessage(
            GoogleSignInException(
              code: code,
              description: 'details for $code',
            ),
          ),
          'details for $code',
          reason: 'code $code should surface its description',
        );
      }
    });

    test('other codes fall back when no description is present', () {
      expect(
        googleAuthErrorMessage(
          const GoogleSignInException(
            code: GoogleSignInExceptionCode.unknownError,
          ),
        ),
        'Could not sign in with Google. Check your connection and try again.',
      );
    });
  });

  group('googleAuthErrorMessage — Firebase auth errors', () {
    test('each explicitly mapped code returns its message', () {
      const expected = {
        'account-exists-with-different-credential':
            'This email is already linked to a different sign-in method.',
        'invalid-credential':
            'Google sign-in could not verify your account. Please try again.',
        'operation-not-allowed':
            'Google sign-in is not enabled in your Firebase Authentication '
            'settings.',
        'network-request-failed':
            'Could not connect. Check your internet connection and try again.',
      };
      for (final entry in expected.entries) {
        expect(
          googleAuthErrorMessage(FirebaseAuthException(code: entry.key)),
          entry.value,
          reason: 'code ${entry.key}',
        );
      }
    });

    test('missing-google-id-token surfaces its message when present', () {
      expect(
        googleAuthErrorMessage(
          FirebaseAuthException(
            code: 'missing-google-id-token',
            message: 'Google did not return an ID token. Check the Firebase '
                'Android app and Web client configuration.',
          ),
        ),
        'Google did not return an ID token. Check the Firebase Android app '
        'and Web client configuration.',
      );
    });

    test('missing-google-id-token without a message has a default', () {
      expect(
        googleAuthErrorMessage(
          FirebaseAuthException(code: 'missing-google-id-token'),
        ),
        'Google did not return a sign-in token.',
      );
    });

    test('unmapped codes surface their message, else the generic fallback', () {
      expect(
        googleAuthErrorMessage(
          FirebaseAuthException(
            code: 'internal-error',
            message: 'raw upstream detail',
          ),
        ),
        'raw upstream detail',
      );
      expect(
        googleAuthErrorMessage(
          FirebaseAuthException(code: 'internal-error'),
        ),
        'Google sign-in failed. Please try again.',
      );
    });
  });

  group('googleAuthErrorMessage — Firebase core errors', () {
    test('every explicitly mapped core code returns the setup hint', () {
      const setupHint =
          'Firebase is not configured yet. Add your Firebase Android app '
          'configuration and enable Google sign-in.';
      for (final code in [
        'core/no-app',
        'core/no-options',
        'core/invalid-app-argument',
        'core/initialization-error',
      ]) {
        expect(
          googleAuthErrorMessage(
            FirebaseException(plugin: 'firebase_core', code: code),
          ),
          setupHint,
          reason: 'code $code',
        );
      }
    });

    test('unmapped core codes surface their message, else a generic fallback', () {
      expect(
        googleAuthErrorMessage(
          FirebaseException(
            plugin: 'firebase_core',
            code: 'network-request-failed',
            message: 'upstream is down',
          ),
        ),
        'upstream is down',
      );
      expect(
        googleAuthErrorMessage(
          FirebaseException(plugin: 'firebase_core', code: 'unknown-code'),
        ),
        'Could not connect to Firebase. Please try again.',
      );
    });
  });

  group('googleAuthErrorMessage — fallbacks', () {
    test('StateError passes its message through', () {
      expect(
        googleAuthErrorMessage(StateError('no account returned')),
        'no account returned',
      );
    });

    test('unknown objects get the safe generic message', () {
      for (final error in <Object>[
        Exception('boom with secret detail'),
        ArgumentError('bad argument'),
        'a raw string',
        42,
      ]) {
        expect(
          googleAuthErrorMessage(error),
          'Google sign-in failed. Please try again.',
          reason: 'unexpected type $error',
        );
      }
    });
  });
}
