import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fittract/main.dart';
import 'package:fittract/services/google_auth_service.dart';
import 'package:fittract/store/store.dart';

void main() {
  /// Hashing runs in a real isolate. Yield one frame first — that is what
  /// lets the submit handler pass its end-of-frame barrier and start hashing
  /// with the spinner painted — then give the isolate real time before
  /// resuming the fake-async pump loop.
  Future<void> settleHashing(WidgetTester tester) async {
    await tester.pump();
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 500));
    });
    await tester.pumpAndSettle();
  }

  /// Creates an account through the registration form and waits for the
  /// flow to finish (it ends back on the Login screen).
  Future<void> registerThroughForm(
    WidgetTester tester, {
    String email = 'reg@example.com',
  }) async {
    await tester.ensureVisible(find.text('New here? Create an account'));
    await tester.tap(find.text('New here? Create an account'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).at(0), 'Test User');
    await tester.enterText(find.byType(TextField).at(1), email);
    await tester.enterText(find.byType(TextField).at(2), 'password123');
    await tester.tap(find.byKey(const ValueKey('terms-checkbox')));
    await tester.pump();

    await tester.tap(find.text('Create account'));
    await settleHashing(tester);
  }

  testWidgets(
    'Registration paints the busy spinner before hashing, then returns to Login',
    (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});
      pbkdf2IterationsOverride = 1000;
      await store.init();
      addTearDown(() => pbkdf2IterationsOverride = 0);

      await tester.pumpWidget(const App());
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('New here? Create an account'));
      await tester.tap(find.text('New here? Create an account'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).at(0), 'Test User');
      await tester.enterText(find.byType(TextField).at(1), 'reg@example.com');
      await tester.enterText(find.byType(TextField).at(2), 'password123');
      await tester.tap(find.byKey(const ValueKey('terms-checkbox')));
      await tester.pump();

      await tester.tap(find.text('Create account'));
      // One frame after the tap, the busy spinner must already be on screen —
      // it paints before the (potentially blocking) password hashing starts.
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Create account'), findsNothing);

      // Hashing runs in a real isolate, so give it real time to finish before
      // resuming the fake-async test pump loop.
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 500));
      });
      await tester.pumpAndSettle();

      // Registration must never authenticate the app: the flow ends back on
      // the Login form, with a success note, and never on the dashboard.
      expect(store.hasActiveSession, isFalse);
      expect(find.text('Welcome back'), findsOneWidget);
      expect(find.text('Create your account'), findsNothing);
      expect(
        find.text('Account created successfully. Please log in.'),
        findsOneWidget,
      );
      expect(find.byType(NavigationBar), findsNothing);
    },
  );

  testWidgets('Duplicate-email failure resets the Create account button', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      // Account already exists: register short-circuits before hashing.
      emailStorageKey('taken@b.com'): jsonEncode({
        'user': 'taken@b.com',
        'name': 'Taken',
        'cred': <String, dynamic>{
          'alg': 'pbkdf2-hmac-sha256',
          'salt': 'AA==',
          'hash': 'AA==',
          'iters': 1000,
        },
      }),
    });
    await store.init();

    await tester.pumpWidget(const App());
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('New here? Create an account'));
    await tester.tap(find.text('New here? Create an account'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).at(0), 'Test User');
    await tester.enterText(find.byType(TextField).at(1), 'taken@b.com');
    await tester.enterText(find.byType(TextField).at(2), 'password123');
    await tester.tap(find.byKey(const ValueKey('terms-checkbox')));
    await tester.pump();

    await tester.tap(find.text('Create account'));
    await tester.pumpAndSettle();

    // Busy state cleared and the failure surfaced instead of a stuck spinner.
    expect(find.text('Create account'), findsOneWidget);
    expect(
      find.text('An account with that email already exists.'),
      findsOneWidget,
    );
    // A failed registration never shows the success note.
    expect(
      find.text('Account created successfully. Please log in.'),
      findsNothing,
    );
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(store.hasActiveSession, isFalse);
    expect(find.byType(NavigationBar), findsNothing);
  });

  testWidgets('Forgot password opens a dedicated email lookup screen', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await store.init();

    await tester.pumpWidget(const App());
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'forgot@example.com');
    await tester.tap(find.text('Forgot password?'));
    await tester.pumpAndSettle();

    expect(find.text('Find your account'), findsOneWidget);
    expect(find.text('Reset your password'), findsOneWidget);
    expect(find.text('Send reset link'), findsOneWidget);
    expect(
      (tester.widget<TextField>(find.byType(TextField).first).controller!.text),
      'forgot@example.com',
    );
  });

  testWidgets('Hashing exception resets the Log in button with a message', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      // Valid JSON but a salt that is not base64: verification throws,
      // which is the path the busy-state catch is there for.
      emailStorageKey('bad@b.com'): jsonEncode({
        'user': 'bad@b.com',
        'cred': <String, dynamic>{
          'alg': 'pbkdf2-hmac-sha256',
          'salt': '@@@not-base64@@@',
          'hash': 'AA==',
          'iters': 1000,
        },
      }),
    });
    await store.init();

    await tester.pumpWidget(const App());
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).at(0), 'bad@b.com');
    await tester.enterText(find.byType(TextField).at(1), 'password123');
    await tester.tap(find.text('Log in'));
    await tester.pumpAndSettle();

    expect(find.text('Log in'), findsOneWidget);
    expect(
      find.text('Something went wrong. Please try again.'),
      findsOneWidget,
    );
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(store.hasActiveSession, isFalse);
  });

  testWidgets(
    'A cloud sign-in that never answers clears the busy state and reports it',
    (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});
      pbkdf2IterationsOverride = 1000;
      await store.init();
      addTearDown(() {
        pbkdf2IterationsOverride = 0;
        store.cloudLinkOverride = null;
        store.cloudLinkTimeout = const Duration(seconds: 15);
      });

      await tester.pumpWidget(const App());
      await tester.pumpAndSettle();
      // Create the account first, so the login below reaches the cloud step
      // with a correct local password.
      await registerThroughForm(tester);

      store.cloudLinkTimeout = const Duration(milliseconds: 500);
      store.cloudLinkOverride = ({
        required String email,
        required String password,
      }) => Completer<String?>().future;

      await tester.enterText(find.byType(TextField).at(1), 'password123');
      await tester.tap(find.text('Log in'));
      await settleHashing(tester);

      // The bounded wait ends: no spinner left behind, the button is usable
      // again, and the reason is on screen in the store's own words.
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Log in'), findsOneWidget);
      expect(
        find.text(
          'Could not reach the account service. Check your connection and try again.',
        ),
        findsOneWidget,
      );
      expect(store.hasActiveSession, isFalse);
      expect(store.sessionUid, isNull);
      expect(find.byType(NavigationBar), findsNothing);
    },
  );

  testWidgets('Login password field toggles visibility without losing text', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await store.init();

    await tester.pumpWidget(const App());
    await tester.pumpAndSettle();

    final pwField = find.byType(TextField).at(1); // email, password
    await tester.enterText(pwField, 'secret123');
    expect(tester.widget<TextField>(pwField).obscureText, isTrue);

    await tester.tap(find.byTooltip('Show password'));
    await tester.pump();
    expect(tester.widget<TextField>(pwField).obscureText, isFalse);
    expect(tester.widget<TextField>(pwField).controller!.text, 'secret123');
    expect(find.byTooltip('Hide password'), findsOneWidget);

    await tester.tap(find.byTooltip('Hide password'));
    await tester.pump();
    expect(tester.widget<TextField>(pwField).obscureText, isTrue);
    expect(tester.widget<TextField>(pwField).controller!.text, 'secret123');
  });

  testWidgets(
    'Registration has one password field and a changing strength meter',
    (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});
      await store.init();

      await tester.pumpWidget(const App());
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('New here? Create an account'));
      await tester.tap(find.text('New here? Create an account'));
      await tester.pumpAndSettle();

      final pwField = find.byType(TextField).at(2); // name, email, password
      await tester.enterText(pwField, 'pass');

      expect(tester.widget<TextField>(pwField).obscureText, isTrue);
      expect(find.text('Confirm password'), findsNothing);
      expect(
        find.text('Use 8+ characters with at least one number.'),
        findsOneWidget,
      );
      expect(find.byTooltip('Show password'), findsOneWidget);
      expect(find.byTooltip('Hide password'), findsNothing);
      await tester.enterText(pwField, 'password123');
      await tester.pump();
      await tester.tap(find.byTooltip('Show password'));
      await tester.pump();
      expect(tester.widget<TextField>(pwField).obscureText, isFalse);
      expect(tester.widget<TextField>(pwField).controller!.text, 'password123');
      expect(find.byTooltip('Hide password'), findsOneWidget);
    },
  );

  testWidgets('Auth controls respect app theme and meet signup states', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await store.init();
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

    await tester.pumpWidget(const App());
    await tester.pumpAndSettle();

    final emailField = find.byType(TextField).first;
    expect(tester.getSize(emailField).height, 56);
    final emailDecoration = tester.widget<TextField>(emailField).decoration!;
    expect(
      (emailDecoration.enabledBorder! as OutlineInputBorder).borderSide.width,
      1.5,
    );
    expect(
      (emailDecoration.focusedBorder! as OutlineInputBorder).borderSide.width,
      3,
    );
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
      ThemeMode.light,
    );
    expect(
      Theme.of(tester.element(find.byType(Scaffold).first)).brightness,
      Brightness.light,
    );
    expect(find.text('Continue with Google'), findsOneWidget);
    expect(find.text('or'), findsOneWidget);
    expect(find.text('Terms of Service'), findsOneWidget);
    expect(find.text('Privacy Policy'), findsOneWidget);

    final forgot = tester.widget<TextButton>(
      find.ancestor(
        of: find.text('Forgot password?'),
        matching: find.byType(TextButton),
      ),
    );
    expect(forgot.style!.textStyle!.resolve({})!.fontSize, 15);
    expect(
      forgot.style!.textStyle!.resolve({})!.decoration,
      TextDecoration.underline,
    );

    await tester.ensureVisible(find.text('New here? Create an account'));
    await tester.tap(find.text('New here? Create an account'));
    await tester.pumpAndSettle();

    final createButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Create account'),
    );
    expect(createButton.onPressed, isNull);
    expect(find.text('Sign up with Google'), findsOneWidget);
    expect(find.text('Terms of Service'), findsWidgets);
    expect(find.text('Privacy Policy'), findsWidgets);
    for (final key in [
      const ValueKey('terms-agreement-link'),
      const ValueKey('privacy-agreement-link'),
    ]) {
      final agreementLink = tester.widget<TextButton>(find.byKey(key));
      expect(
        agreementLink.style!.textStyle!.resolve({})!.decoration,
        TextDecoration.none,
      );
    }
    for (var i = 0; i < 4; i++) {
      expect(find.byKey(ValueKey('password-strength-$i')), findsOneWidget);
    }

    await tester.tap(find.text('I agree to the '));
    await tester.pump();
    expect(
      tester
          .widget<Checkbox>(find.byKey(const ValueKey('terms-checkbox')))
          .value,
      isTrue,
    );
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Create account'),
          )
          .onPressed,
      isNotNull,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'A registered account signs in manually and reaches the dashboard',
    (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});
      pbkdf2IterationsOverride = 1000;
      await store.init();
      addTearDown(() => pbkdf2IterationsOverride = 0);

      await tester.pumpWidget(const App());
      await tester.pumpAndSettle();
      await registerThroughForm(tester);

      // The flow ended back on Login: still signed out, dashboard not shown.
      expect(store.hasActiveSession, isFalse);
      expect(find.byType(NavigationBar), findsNothing);

      // The email stays filled in; only the password has to be typed again.
      await tester.enterText(find.byType(TextField).at(1), 'password123');
      await tester.tap(find.text('Log in'));
      await settleHashing(tester);

      // A separate, successful login is what authenticates and opens the app.
      expect(store.hasActiveSession, isTrue);
      expect(store.d['user'], 'reg@example.com');
      expect(store.d['name'], 'Test User');
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(
        find.text('Account created successfully. Please log in.'),
        findsNothing,
      );
    },
  );

  testWidgets(
    'Session cleanup after registration keeps the account and its profile',
    (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});
      pbkdf2IterationsOverride = 1000;
      await store.init();
      addTearDown(() => pbkdf2IterationsOverride = 0);

      await tester.pumpWidget(const App());
      await tester.pumpAndSettle();
      await registerThroughForm(tester);

      // Nothing that a restart (or an auth-state listener) could treat as a
      // signed-in state survives the registration cleanup...
      expect(store.hasActiveSession, isFalse);
      expect(store.sp.getString('ft_session_meta'), isNull);
      expect(store.d['user'], isNull);

      // ...while the account itself and everything registration initialized
      // are kept in its own bucket.
      final raw = store.sp.getString(emailStorageKey('reg@example.com'));
      expect(raw, isNotNull);
      final decoded = jsonDecode(raw!) as Map<String, dynamic>;
      expect(decoded['user'], 'reg@example.com');
      expect(decoded['name'], 'Test User');
      expect(decoded['cred'], isA<Map>());

      // A restart stays signed out and the account is still there.
      await store.init();
      expect(store.hasActiveSession, isFalse);
      expect(store.sp.getString(emailStorageKey('reg@example.com')), raw);

      // Signing in manually restores that same profile.
      await tester.enterText(find.byType(TextField).at(1), 'password123');
      await tester.tap(find.text('Log in'));
      await settleHashing(tester);

      expect(store.hasActiveSession, isTrue);
      expect(store.d['user'], 'reg@example.com');
      expect(store.d['name'], 'Test User');
    },
  );

  testWidgets(
    'Returning from cancelled Google auth clears busy for login and sign up',
    (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});
      await store.init();

      final pendingSignIns = <Completer<UserCredential>>[];
      GoogleAuthService.debugSignInOverride = () {
        final pending = Completer<UserCredential>();
        pendingSignIns.add(pending);
        return pending.future;
      };
      addTearDown(GoogleAuthService.resetGoogleSignInInitializationForTesting);

      Future<void> cancelExternalAuth() async {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pump();
      }

      await tester.pumpWidget(const App());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Continue with Google'));
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await cancelExternalAuth();
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Continue with Google'), findsOneWidget);
      pendingSignIns.last.completeError(
        const GoogleSignInException(code: GoogleSignInExceptionCode.canceled),
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('New here? Create an account'));
      await tester.tap(find.text('New here? Create an account'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('terms-checkbox')));
      await tester.pump();
      await tester.ensureVisible(find.text('Sign up with Google'));
      await tester.tap(find.text('Sign up with Google'));
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await cancelExternalAuth();
      pendingSignIns.last.completeError(
        const GoogleSignInException(code: GoogleSignInExceptionCode.canceled),
      );
      await tester.pumpAndSettle();

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Sign up with Google'), findsOneWidget);
      expect(pendingSignIns, hasLength(2));
      expect(store.hasActiveSession, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'An unexpected Google sign-in failure shows a safe message and clears busy',
    (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});
      await store.init();

      await tester.pumpWidget(const App());
      await tester.pumpAndSettle();

      // Under test no Firebase/Google SDK answers the plugin channel, so the
      // attempt fails with an unexpected PlatformException — the class of
      // error the catch-all fallback exists to absorb.
      await tester.tap(find.text('Continue with Google'));
      // One frame after the tap the busy spinner must already paint, before
      // the async failure arrives.
      await tester.pump();

      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 500));
      });
      await tester.pumpAndSettle();

      // Busy state always clears: no spinner left behind and the button works.
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Continue with Google'), findsOneWidget);

      // A short, mapped message is shown instead of silence...
      expect(
        find.text('Google sign-in failed. Please try again.'),
        findsOneWidget,
      );
      // ...and no raw error details, channel names or config text leak out.
      final visible = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data ?? '')
          .join('\n');
      expect(visible.contains('PlatformException'), isFalse);
      expect(visible.contains('channel-error'), isFalse);
      expect(visible.toLowerCase().contains('pigeon'), isFalse);

      // The failure never authenticates or syncs anything.
      expect(store.hasActiveSession, isFalse);
      expect(store.sessionUid, isNull);
      expect(find.byType(NavigationBar), findsNothing);
    },
  );
}
