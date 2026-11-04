import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fittract/store/store.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    // Keep hashing fast in tests; production uses 210k iterations.
    pbkdf2IterationsOverride = 1000;
  });

  tearDown(() {
    pbkdf2IterationsOverride = 0;
  });

  Future<Store> freshStore() async {
    final s = Store();
    await s.init();
    return s;
  }

  String rawAccount(Store s, String email) =>
      s.sp.getString(emailStorageKey(normalizeEmail(email)))!;

  test(
    'register creates a hashed per-account snapshot but no session',
    () async {
      final s = await freshStore();

      final result = await s.register(
        name: 'Ada Lovelace',
        email: '  Ada@Example.COM ',
        password: 'correct horse',
      );

      expect(result, AuthResult.success);
      // Registration must not authenticate the app: the user is sent back to
      // the Login screen and signs in separately.
      expect(s.hasActiveSession, isFalse);
      expect(s.isEmailAccount, isFalse);
      expect(s.d['user'], isNull);

      final raw = rawAccount(s, 'ada@example.com');
      expect(raw, isNot(contains('correct horse')));
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      expect(decoded['user'], 'ada@example.com');
      expect(decoded['name'], 'Ada Lovelace');
      expect(decoded['cred']['alg'], 'pbkdf2-hmac-sha256');
      expect(decoded['cred']['iters'], 1000);
      expect(decoded.containsKey('pw'), isFalse);

      // A separate, successful login is what authenticates the session, and it
      // brings the freshly created profile back with it.
      expect(
        await s.login(email: 'ada@example.com', password: 'correct horse'),
        AuthResult.success,
      );
      expect(s.hasActiveSession, isTrue);
      expect(s.isEmailAccount, isTrue);
      expect(s.d['user'], 'ada@example.com');
      expect(s.d['name'], 'Ada Lovelace');
    },
  );

  test(
    'registration cleanup keeps the account and leaves nothing signed in',
    () async {
      final s = await freshStore();
      await s.register(name: 'Ada', email: 'ada@b.com', password: 'password1');

      // Session teardown: no active session, no cloud identity, no pending
      // sync work, and no session pointer a restart could resume from.
      expect(s.hasActiveSession, isFalse);
      expect(s.sessionUid, isNull);
      expect(s.syncRunning, isFalse);
      expect(s.syncPending, isFalse);
      expect(s.sp.getString('ft_session_meta'), isNull);

      // The cleanup never deletes the account or its initialized profile.
      final next = await freshStore();
      expect(next.hasActiveSession, isFalse);
      final decoded =
          jsonDecode(rawAccount(next, 'ada@b.com')) as Map<String, dynamic>;
      expect(decoded['user'], 'ada@b.com');
      expect(decoded['name'], 'Ada');
      expect(decoded['cred'], isA<Map>());

      // ...and that account still signs in with everything it started with.
      expect(
        await next.login(email: 'ada@b.com', password: 'password1'),
        AuthResult.success,
      );
      expect(next.hasActiveSession, isTrue);
      expect(next.d['name'], 'Ada');
      expect(next.d['user'], 'ada@b.com');
    },
  );

  test('register validates input and rejects duplicates', () async {
    final s = await freshStore();

    expect(
      await s.register(name: '', email: 'a@b.com', password: 'password1'),
      AuthResult.invalidInput,
    );
    expect(
      await s.register(name: 'A', email: 'not-an-email', password: 'password1'),
      AuthResult.invalidInput,
    );
    expect(
      await s.register(name: 'A', email: 'a@b.com', password: 'short'),
      AuthResult.invalidInput,
    );

    expect(
      await s.register(name: 'A', email: 'a@b.com', password: 'password1'),
      AuthResult.success,
    );
    expect(
      await s.register(name: 'B', email: 'A@B.COM', password: 'password2'),
      AuthResult.duplicateEmail,
    );
  });

  group('registration against a cloud link that misbehaves', () {
    /// The button spinner lasts exactly as long as `register` does, so a
    /// cloud call that never answers must not be able to pin it open.
    test('a link that never answers still completes registration', () async {
      final s = await freshStore();
      s.cloudLinkTimeout = const Duration(seconds: 15);
      final hung = <Completer<String?>>[];
      s.cloudLinkOverride =
          ({required String email, required String password}) {
            final c = Completer<String?>();
            hung.add(c);
            return c.future;
          };

      final result = await s
          .register(name: 'Ada', email: 'ada@b.com', password: 'password1')
          .timeout(const Duration(seconds: 1));

      expect(result, AuthResult.success);
      // Local outcome is the whole contract: account written, nothing signed
      // in, and the account usable by the login that follows.
      expect(s.hasActiveSession, isFalse);
      expect(s.sp.getString(emailStorageKey('ada@b.com')), isNotNull);
      hung.single.complete(null);
      await pumpEventQueue();
      s.cloudLinkOverride = ({
        required String email,
        required String password,
      }) async => 'uid';
      expect(
        await s.login(email: 'ada@b.com', password: 'password1'),
        AuthResult.success,
      );
      expect(s.d['user'], 'ada@b.com');
    });

    test('a link that throws still creates the local account', () async {
      final s = await freshStore();
      s.cloudLinkOverride = ({
        required String email,
        required String password,
      }) => throw StateError('cloud is down');

      expect(
        await s.register(
          name: 'Ada',
          email: 'ada@b.com',
          password: 'password1',
        ),
        AuthResult.success,
      );
      expect(s.hasActiveSession, isFalse);
      expect(s.sp.getString(emailStorageKey('ada@b.com')), isNotNull);
    });

    test('the abandoned link answering later changes nothing local', () async {
      final s = await freshStore();
      s.cloudLinkTimeout = const Duration(milliseconds: 50);
      final arrived = <Completer<String?>>[];
      s.cloudLinkOverride =
          ({required String email, required String password}) {
            final c = Completer<String?>();
            arrived.add(c);
            return c.future;
          };

      await s.register(name: 'Ada', email: 'ada@b.com', password: 'password1');
      await s.register(name: 'Bob', email: 'bob@b.com', password: 'password2');
      expect(arrived, hasLength(2));

      // Both stalled calls finally answer — one successfully, one with an
      // error. Registration already gave up on them, so neither may reach
      // the local session or escape as an unhandled error.
      arrived[0].complete('uid-late');
      arrived[1].completeError(StateError('late failure'));
      await pumpEventQueue();

      expect(s.hasActiveSession, isFalse);
      expect(s.sessionUid, isNull);
      expect(s.sp.getString(emailStorageKey('ada@b.com')), isNotNull);
      expect(s.sp.getString(emailStorageKey('bob@b.com')), isNotNull);
      s.cloudLinkOverride = ({
        required String email,
        required String password,
      }) async => 'uid';
      expect(
        await s.login(email: 'ada@b.com', password: 'password1'),
        AuthResult.success,
      );
      expect(s.d['user'], 'ada@b.com');
    });
  });

  group('login against a cloud link that misbehaves', () {
    Future<Store> signedInAccount() async {
      final s = await freshStore();
      await s.register(name: 'Ada', email: 'ada@b.com', password: 'password1');
      return s;
    }

    test('a sign-in that never answers fails with a service error', () async {
      final s = await signedInAccount();
      // Production ships this cap; the test tightens it so the wait is short.
      expect(s.cloudLinkTimeout, const Duration(seconds: 15));
      s.cloudLinkTimeout = const Duration(milliseconds: 50);
      s.cloudLinkOverride = ({
        required String email,
        required String password,
      }) => Completer<String?>().future;

      var cloudPrompted = 0;
      var offlinePrompted = 0;
      final result = await s
          .login(
            email: 'ada@b.com',
            password: 'password1',
            requestCloudAccountCreation: (_) async {
              cloudPrompted++;
              return true;
            },
            requestOfflineFallback: (_) async {
              offlinePrompted++;
              return true;
            },
          )
          .timeout(const Duration(seconds: 5));

      // The wait ends and the user is told what happened; a timeout is
      // reported, not negotiated away behind a dialog nobody has time to
      // read after fifteen seconds of spinner.
      expect(result, AuthResult.serviceError);
      expect(cloudPrompted, 0);
      expect(offlinePrompted, 0);
      // No session field was written: nothing signed in, no pointer a
      // restart could resume from.
      expect(s.hasActiveSession, isFalse);
      expect(s.sessionUid, isNull);
      expect(s.sp.getString('ft_session_meta'), isNull);
      // The account survives untouched, and a cloud that answers lets the
      // very same credentials in.
      expect(s.sp.getString(emailStorageKey('ada@b.com')), isNotNull);
      s.cloudLinkOverride = ({
        required String email,
        required String password,
      }) async => 'uid-retry';
      expect(
        await s.login(email: 'ada@b.com', password: 'password1'),
        AuthResult.success,
      );
      expect(s.sessionUid, 'uid-retry');
    });

    test('a sign-in that throws is reported as a service error', () async {
      final s = await signedInAccount();
      s.cloudLinkOverride = ({
        required String email,
        required String password,
      }) => throw StateError('cloud is down');

      expect(
        await s.login(email: 'ada@b.com', password: 'password1'),
        AuthResult.serviceError,
      );
      expect(s.hasActiveSession, isFalse);
      expect(s.sessionUid, isNull);
      expect(s.sp.getString('ft_session_meta'), isNull);
      expect(s.sp.getString(emailStorageKey('ada@b.com')), isNotNull);
    });

    test(
      'a successful cloud sign-in carries its uid onto the session',
      () async {
        final s = await signedInAccount();
        s.cloudLinkOverride = ({
          required String email,
          required String password,
        }) async => 'uid-cloud';

        expect(
          await s.login(email: 'ada@b.com', password: 'password1'),
          AuthResult.success,
        );
        expect(s.hasActiveSession, isTrue);
        expect(s.sessionUid, 'uid-cloud');
        expect(s.isCloudLinked, isTrue);
        expect(s.d['user'], 'ada@b.com');

        // The uid is part of the session pointer, not of this store instance.
        final next = await freshStore();
        expect(next.sessionUid, 'uid-cloud');
        next.signOut();
      },
    );

    test(
      'the abandoned sign-in answering later does not sign the device in',
      () async {
        final s = await signedInAccount();
        s.cloudLinkTimeout = const Duration(milliseconds: 50);
        final late = Completer<String?>();
        s.cloudLinkOverride = ({
          required String email,
          required String password,
        }) => late.future;

        expect(
          await s.login(email: 'ada@b.com', password: 'password1'),
          AuthResult.serviceError,
        );
        expect(s.hasActiveSession, isFalse);

        // Firebase finally answers — the user has already been told login
        // failed, so this must not quietly produce a signed-in state.
        late.complete('uid-late');
        await pumpEventQueue();

        expect(s.hasActiveSession, isFalse);
        expect(s.sessionUid, isNull);
        expect(s.sp.getString('ft_session_meta'), isNull);
        expect(s.sp.getString(emailStorageKey('ada@b.com')), isNotNull);

        // An explicit, successful login is still the only way in, and it
        // claims that same uid for the live session.
        s.cloudLinkOverride = ({
          required String email,
          required String password,
        }) async => 'uid-late';
        expect(
          await s.login(email: 'ada@b.com', password: 'password1'),
          AuthResult.success,
        );
        expect(s.sessionUid, 'uid-late');
      },
    );

    test('the abandoned sign-in failing later surfaces nothing', () async {
      final s = await signedInAccount();
      s.cloudLinkTimeout = const Duration(milliseconds: 50);
      final late = Completer<String?>();
      s.cloudLinkOverride = ({
        required String email,
        required String password,
      }) => late.future;

      expect(
        await s.login(email: 'ada@b.com', password: 'password1'),
        AuthResult.serviceError,
      );

      // A late failure would escape as an unhandled error (and fail this
      // test) if the abandoned call were simply dropped.
      late.completeError(StateError('late failure'));
      await pumpEventQueue();

      expect(s.hasActiveSession, isFalse);
      expect(s.sessionUid, isNull);
      expect(s.sp.getString(emailStorageKey('ada@b.com')), isNotNull);
    });

    test(
      'a timeout never disturbs the session the app is already signed into',
      () async {
        final s = await signedInAccount();
        expect(
          await s.login(email: 'ada@b.com', password: 'password1'),
          AuthResult.success,
        );
        s.d['steps'] = 4321;
        s.save();
        s.d['steps'] = 9999; // live edit, deliberately not flushed yet

        s.cloudLinkTimeout = const Duration(milliseconds: 50);
        s.cloudLinkOverride = ({
          required String email,
          required String password,
        }) => Completer<String?>().future;

        expect(
          await s.login(email: 'ada@b.com', password: 'password1'),
          AuthResult.serviceError,
        );

        // The timeout returned before the session-writing tail ran: the live
        // session and its unflushed data are exactly as they were.
        expect(s.hasActiveSession, isTrue);
        expect(s.sessionUid, isNull);
        expect(s.d['user'], 'ada@b.com');
        expect(s.steps, 9999);
        expect(s.sp.getString('ft_session_meta'), isNotNull);
      },
    );
  });

  test('login verifies the password and rejects wrong ones', () async {
    final s = await freshStore();
    await s.register(name: 'A', email: 'a@b.com', password: 'password1');
    s.signOut();

    expect(s.hasActiveSession, isFalse);
    expect(
      await s.login(email: 'a@b.com', password: 'wrong-pass'),
      AuthResult.wrongPassword,
    );
    expect(
      await s.login(email: 'missing@b.com', password: 'password1'),
      AuthResult.unknownEmail,
    );
    expect(
      await s.login(email: 'a@b.com', password: 'password1'),
      AuthResult.success,
    );
    expect(s.hasActiveSession, isTrue);
    expect(s.d['user'], 'a@b.com');
    expect(s.d['name'], 'A');
  });

  test('sign out preserves account data for the next login', () async {
    final s = await freshStore();
    await s.register(name: 'A', email: 'a@b.com', password: 'password1');
    await s.login(email: 'a@b.com', password: 'password1');
    s.d['steps'] = 5000;
    s.save();
    s.signOut();

    expect(s.hasActiveSession, isFalse);
    expect(s.d['user'], isNull);
    expect(s.sp.getString(emailStorageKey('a@b.com')), isNotNull);

    final next = await freshStore();
    expect(
      await next.login(email: 'a@b.com', password: 'password1'),
      AuthResult.success,
    );
    expect(next.steps, 5000);
    expect(next.d['name'], 'A');
  });

  test('email accounts keep separate fitness data', () async {
    final s = await freshStore();
    await s.register(
      name: 'First',
      email: 'first@b.com',
      password: 'password1',
    );
    await s.login(email: 'first@b.com', password: 'password1');
    s.d['steps'] = 1200;
    s.save();

    await s.register(
      name: 'Second',
      email: 'second@b.com',
      password: 'password2',
    );
    expect(s.steps, 0);

    s.signOut();
    await s.login(email: 'first@b.com', password: 'password1');
    expect(s.steps, 1200);
    expect(s.d['name'], 'First');
  });

  test('changePassword requires the current password and re-hashes', () async {
    final s = await freshStore();
    await s.register(name: 'A', email: 'a@b.com', password: 'password1');
    await s.login(email: 'a@b.com', password: 'password1');

    // Wrong current password must fail and leave the credential intact.
    expect(
      await s.changePassword(
        currentPassword: 'not-my-password',
        newPassword: 'newpassword',
      ),
      PasswordChangeResult.wrongCurrentPassword,
    );
    s.signOut();
    expect(
      await s.login(email: 'a@b.com', password: 'password1'),
      AuthResult.success,
    );

    // Short new passwords are rejected without verifying anything.
    expect(
      await s.changePassword(
        currentPassword: 'password1',
        newPassword: 'short',
      ),
      PasswordChangeResult.invalidInput,
    );

    // A correct current password allows the change.
    expect(
      await s.changePassword(
        currentPassword: 'password1',
        newPassword: 'newpassword',
      ),
      PasswordChangeResult.success,
    );
    s.signOut();
    expect(
      await s.login(email: 'a@b.com', password: 'password1'),
      AuthResult.wrongPassword,
    );
    expect(
      await s.login(email: 'a@b.com', password: 'newpassword'),
      AuthResult.success,
    );

    // Google-managed accounts are never subject to local password changes.
    s.signOut();
    s.activateGoogleAccount(uid: 'g-1', email: 'g@b.com', displayName: 'G');
    expect(
      await s.changePassword(
        currentPassword: 'whatever',
        newPassword: 'newpassword',
      ),
      PasswordChangeResult.notEmailAccount,
    );
  });

  test(
    'a Firebase-reset password refreshes the local credential on login',
    () async {
      final s = await freshStore();
      await s.register(name: 'A', email: 'a@b.com', password: 'password1');
      s.cloudLinkOverride =
          ({required String email, required String password}) async {
            if (password == 'resetpass') return 'cloud-uid';
            throw FirebaseAuthException(code: 'wrong-password');
          };

      expect(
        await s.login(email: 'a@b.com', password: 'resetpass'),
        AuthResult.success,
      );
      s.signOut();

      // The Firebase-verified password is now also usable as the local
      // credential, including when cloud authentication is unavailable.
      s.cloudLinkOverride = null;
      expect(
        await s.login(email: 'a@b.com', password: 'resetpass'),
        AuthResult.success,
      );
      s.signOut();
      expect(
        await s.login(email: 'a@b.com', password: 'password1'),
        AuthResult.wrongPassword,
      );
    },
  );

  test('resetCurrentAccountData keeps identity, profile and goals', () async {
    final s = await freshStore();
    await s.register(name: 'A', email: 'a@b.com', password: 'password1');
    await s.login(email: 'a@b.com', password: 'password1');
    s.d['steps'] = 900;
    s.d['name'] = 'Keep Me';
    s.d['age'] = 34;
    s.d['h'] = 176;
    s.d['goal'] = {'w': 72.0, 'd': 'cut', 'wk': 4, 'sw': 80.0};
    s.d['nutritionGoals'] = {
      'calories': 1800,
      'protein': 150,
      'carbs': 180,
      'fat': 55,
    };
    s.save();

    s.resetCurrentAccountData();

    // Fitness records are gone.
    expect(s.steps, 0);
    expect(s.meals, isEmpty);
    expect(s.hist, isEmpty);
    expect(s.routines, isEmpty);
    expect(s.d['log'], isEmpty);
    expect(s.d.containsKey('activeW'), isFalse);

    // Identity, profile details and goals survive the reset.
    expect(s.d['user'], 'a@b.com');
    expect(s.d['name'], 'Keep Me');
    expect(s.d['age'], 34);
    expect(s.d['h'], 176);
    expect(s.goal['w'], 72.0);
    expect(s.goal['sw'], 80.0);
    expect(s.nutritionGoals['calories'], 1800);
    expect(s.d['cred'], isA<Map>());
    expect(s.hasActiveSession, isTrue);

    s.signOut();
    expect(
      await s.login(email: 'a@b.com', password: 'password1'),
      AuthResult.success,
    );
    expect(s.d['name'], 'Keep Me');
    expect(s.goal['w'], 72.0);
    expect(s.steps, 0);
  });

  test(
    'legacy plaintext email account migrates to a hashed snapshot',
    () async {
      final legacy = <String, dynamic>{
        'user': 'old@b.com',
        'lastUser': 'old@b.com',
        'pw': 'legacy-pass',
        'name': 'Old User',
        'steps': 42,
        'routines': <Map<String, dynamic>>[],
        'sch': <Map<String, dynamic>>[],
        'water': <Map<String, dynamic>>[],
        'act': <Map<String, dynamic>>[],
        'weights': <List<dynamic>>[],
        'meals': <Map<String, dynamic>>[],
        'hist': <Map<String, dynamic>>[],
        'log': <dynamic>[],
        'day': today(),
        'goal': {'w': 0.0, 'd': '', 'wk': 3, 'sw': 0.0},
      };
      SharedPreferences.setMockInitialValues({'ft': jsonEncode(legacy)});

      final s = await freshStore();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('ft'), isNull);
      expect(prefs.getString('ft_legacy_backup'), jsonEncode(legacy));
      expect(prefs.getString(emailStorageKey('old@b.com')), isNotNull);
      expect(
        prefs.getString(emailStorageKey('old@b.com')),
        isNot(contains('legacy-pass')),
      );

      expect(s.hasActiveSession, isFalse);
      expect(
        await s.login(email: 'old@b.com', password: 'legacy-pass'),
        AuthResult.success,
      );
      expect(s.steps, 42);
      expect(s.d['name'], 'Old User');
    },
  );

  test(
    'legacy Google bucket keeps its uid key and drops plaintext pw',
    () async {
      final legacy = <String, dynamic>{
        'user': 'g@b.com',
        'accountId': 'uid-9',
        'authProvider': 'google',
        'name': 'G User',
        'pw': 'should-not-survive',
        'steps': 7,
        'routines': <Map<String, dynamic>>[],
        'sch': <Map<String, dynamic>>[],
        'water': <Map<String, dynamic>>[],
        'act': <Map<String, dynamic>>[],
        'weights': <List<dynamic>>[],
        'meals': <Map<String, dynamic>>[],
        'hist': <Map<String, dynamic>>[],
        'log': <dynamic>[],
        'day': today(),
        'goal': {'w': 0.0, 'd': '', 'wk': 3, 'sw': 0.0},
      };
      SharedPreferences.setMockInitialValues({'ft': jsonEncode(legacy)});

      final s = await freshStore();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('ft'), isNull);
      final bucket = prefs.getString('ft_account_uid-9');
      expect(bucket, isNotNull);
      expect(bucket, isNot(contains('should-not-survive')));

      s.activateGoogleAccount(
        uid: 'uid-9',
        email: 'g@b.com',
        displayName: 'G User',
      );
      expect(s.steps, 7);
      expect(s.hasActiveSession, isTrue);
      expect(s.isEmailAccount, isFalse);
      expect(s.d['accountId'], 'uid-9');
      expect(s.d['authProvider'], 'google');
    },
  );

  test(
    'Google profile reuses its UID bucket and persists its photo URL',
    () async {
      final s = await freshStore();

      s.activateGoogleAccount(
        uid: 'google-uid',
        email: 'google@example.com',
        displayName: 'Google User',
        photoUrl: 'https://example.com/avatar.png',
      );
      s.activateGoogleAccount(
        uid: 'google-uid',
        email: 'google@example.com',
        displayName: 'Google User Updated',
        photoUrl: 'https://example.com/avatar-updated.png',
      );

      expect(s.d['name'], 'Google User Updated');
      expect(s.d['user'], 'google@example.com');
      expect(s.d['photoUrl'], 'https://example.com/avatar-updated.png');
      expect(s.sp.getKeys().where((key) => key.startsWith('ft_account_')), [
        'ft_account_google-uid',
      ]);

      final restored = await freshStore();
      expect(restored.d['accountId'], 'google-uid');
      expect(restored.d['photoUrl'], 'https://example.com/avatar-updated.png');
    },
  );

  test('legacy data without a verifiable owner is not claimed', () async {
    SharedPreferences.setMockInitialValues({
      'ft': jsonEncode({'user': 'anon@b.com', 'steps': 99}),
    });

    final s = await freshStore();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('ft'), isNull);
    expect(prefs.getString('ft_legacy_backup'), isNotNull);
    expect(s.hasActiveSession, isFalse);
    expect(s.d['user'], isNull);
    expect(s.steps, 0);
  });

  test(
    'undecodable legacy bucket is backed up and startup stays safe',
    () async {
      SharedPreferences.setMockInitialValues({'ft': '{not json'});

      final s = await freshStore();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('ft'), isNull);
      expect(prefs.getString('ft_legacy_backup'), '{not json');
      expect(s.hasActiveSession, isFalse);
      expect(s.d['user'], isNull);
    },
  );

  test('corrupt account snapshot signs out instead of crashing', () async {
    final s = await freshStore();
    await s.register(name: 'A', email: 'a@b.com', password: 'password1');
    await s.login(email: 'a@b.com', password: 'password1');
    final key = emailStorageKey('a@b.com');
    s.sp.setString(key, '%%broken%%');

    final next = await freshStore();
    expect(next.hasActiveSession, isFalse);
    expect(next.d['user'], isNull);
    // The corrupt bucket is left on disk for manual recovery.
    expect(next.sp.getString(key), '%%broken%%');
  });

  test(
    'web (chunked) hashing matches the isolate task byte-for-byte',
    () async {
      // Existing credentials were hashed by the sync/compute path; the web
      // driver must derive the exact same bytes or old logins would break.
      final cases = <(int, int)>[
        (1, 32),
        (2, 32),
        (1000, 32),
        (1000, 48), // spans two SHA-256 blocks
      ];
      for (final (iterations, keyLength) in cases) {
        final args = <String, dynamic>{
          'password': 'correct horse',
          'salt': List<int>.generate(16, (i) => (i * 7) % 251),
          'iterations': iterations,
          'keyLength': keyLength,
        };
        expect(
          await pbkdf2ChunkedForTest(args),
          pbkdf2SyncForTest(args),
          reason: 'iterations=$iterations keyLength=$keyLength',
        );
        expect(
          await pbkdf2WebForTest(args),
          pbkdf2SyncForTest(args),
          reason: 'Web Crypto iterations=$iterations keyLength=$keyLength',
        );
      }
    },
  );

  test(
    'corrupt stored salt throws out of login instead of being swallowed',
    () async {
      final s = await freshStore();
      s.sp.setString(
        emailStorageKey('bad@b.com'),
        jsonEncode({
          'user': 'bad@b.com',
          'cred': <String, dynamic>{
            'alg': 'pbkdf2-hmac-sha256',
            'salt': '@@@not-base64@@@',
            'hash': 'AA==',
            'iters': 1000,
          },
        }),
      );

      // The auth screen relies on this throwing so it can reset the busy
      // button and show a message; login must not swallow it silently.
      await expectLater(
        s.login(email: 'bad@b.com', password: 'password1'),
        throwsA(isA<FormatException>()),
      );
      expect(s.hasActiveSession, isFalse);
    },
  );

  test(
    'local email sessions have no cloud uid; Google sessions persist theirs',
    () async {
      final s = await freshStore();
      await s.register(name: 'A', email: 'a@b.com', password: 'password1');
      await s.login(email: 'a@b.com', password: 'password1');
      expect(s.sessionUid, isNull);
      expect(s.isCloudLinked, isFalse);
      s.signOut();

      s.activateGoogleAccount(
        uid: 'uid-42',
        email: 'g@b.com',
        displayName: 'G',
      );
      expect(s.sessionUid, 'uid-42');
      expect(s.isCloudLinked, isTrue);

      // The uid survives an app restart via the session pointer.
      final next = await freshStore();
      expect(next.hasActiveSession, isTrue);
      expect(next.sessionUid, 'uid-42');
      next.signOut();
      expect(next.sessionUid, isNull);
    },
  );

  test('signOutAsync clears the session exactly like signOut', () async {
    final s = await freshStore();
    await s.register(name: 'A', email: 'a@b.com', password: 'password1');
    await s.login(email: 'a@b.com', password: 'password1');
    s.d['steps'] = 3000;
    s.save();

    await s.signOutAsync();

    expect(s.hasActiveSession, isFalse);
    expect(s.sessionUid, isNull);
    expect(s.sp.getString(emailStorageKey('a@b.com')), isNotNull);
    expect(
      await s.login(email: 'a@b.com', password: 'password1'),
      AuthResult.success,
    );
    expect(s.steps, 3000);
  });

  test(
    'sendPasswordReset rejects bad input and reports offline service',
    () async {
      final s = await freshStore();

      expect(await s.sendPasswordReset(''), AuthResult.invalidInput);
      expect(
        await s.sendPasswordReset('not-an-email'),
        AuthResult.invalidInput,
      );
      // No Firebase app in tests: the cloud path is unavailable and must be
      // reported as a service error, never as success or unknownEmail.
      expect(
        await s.sendPasswordReset('someone@b.com'),
        AuthResult.serviceError,
      );
    },
  );

  test(
    'login keeps working fully offline when no Firebase app exists',
    () async {
      final s = await freshStore();
      await s.register(name: 'A', email: 'a@b.com', password: 'password1');
      s.signOut();

      // Confirm callbacks are supplied but must never be invoked without a
      // Firebase app: there is nothing to confirm against.
      var cloudPrompted = 0;
      var offlinePrompted = 0;
      final result = await s.login(
        email: 'a@b.com',
        password: 'password1',
        requestCloudAccountCreation: (_) async {
          cloudPrompted++;
          return true;
        },
        requestOfflineFallback: (_) async {
          offlinePrompted++;
          return true;
        },
      );

      expect(result, AuthResult.success);
      expect(cloudPrompted, 0);
      expect(offlinePrompted, 0);
      expect(s.sessionUid, isNull);
    },
  );

  test('cloud payload never contains password material', () async {
    final s = await freshStore();
    await s.register(name: 'A', email: 'a@b.com', password: 'password1');
    await s.login(email: 'a@b.com', password: 'password1');

    final payload = sanitizedAccountForCloud(Map<String, dynamic>.from(s.d));

    expect(payload.containsKey('cred'), isFalse);
    expect(payload.containsKey('cloudOptOut'), isFalse);
    expect(payload['user'], 'a@b.com');
    expect(payload['name'], 'A');
    // No secret material leaks through nested keys either.
    expect(jsonEncode(payload), isNot(contains('pbkdf2')));
    expect(jsonEncode(payload), isNot(contains('salt')));
  });

  test(
    'canonicalAccountHash is stable across key order and content-sensitive',
    () async {
      final a = <String, dynamic>{
        'user': 'a@b.com',
        'steps': 10,
        'goal': {'w': 1.0, 'd': '', 'wk': 3},
      };
      final b = <String, dynamic>{
        'goal': {'wk': 3, 'd': '', 'w': 1.0},
        'steps': 10,
        'user': 'a@b.com',
      };
      expect(canonicalAccountHash(a), canonicalAccountHash(b));

      final c = Map<String, dynamic>.from(a)..['steps'] = 11;
      expect(canonicalAccountHash(a), isNot(canonicalAccountHash(c)));
    },
  );
}
