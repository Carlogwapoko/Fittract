import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fittract/store/store.dart';

/// In-memory stand-in for `users/{uid}` so revision conflicts, stale data,
/// transport failures and account isolation can be driven deterministically
/// without a live Firebase project.
class FakeCloudUserDoc implements CloudUserDoc {
  final docs = <String, Map<String, dynamic>>{};
  bool failRead = false;
  bool failWrite = false;
  Completer<void>? readGate;
  int guardedWrites = 0;
  int forceWrites = 0;

  int _lastRevision = 0;

  int _nextRevision() {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now <= _lastRevision) {
      _lastRevision++;
      return _lastRevision;
    }
    _lastRevision = now;
    return now;
  }

  static Map<String, dynamic> deep(Map<String, dynamic> value) =>
      jsonDecode(jsonEncode(value)) as Map<String, dynamic>;

  /// Seed a document as another device would have left it.
  void put(String uid, Map<String, dynamic> data, int updatedAt) {
    docs[uid] = {'data': deep(data), 'updatedAt': updatedAt};
  }

  Map<String, dynamic>? doc(String uid) => docs[uid];

  Map<String, dynamic>? data(String uid) =>
      docs[uid]?['data'] as Map<String, dynamic>?;

  @override
  Future<CloudDocSnapshot> read(String uid) async {
    final gate = readGate;
    if (gate != null) await gate.future;
    if (failRead) throw StateError('cloud read failed');
    final doc = docs[uid];
    if (doc == null) return const CloudDocSnapshot(exists: false);
    return CloudDocSnapshot(exists: true, data: deep(doc));
  }

  @override
  Future<Object?> guardedWrite(
    String uid,
    Map<String, dynamic> payload,
    Object? baseUpdatedAt,
  ) async {
    guardedWrites++;
    if (failWrite) throw StateError('cloud write failed');
    final doc = docs[uid];
    if (doc != null && doc['updatedAt'] != baseUpdatedAt) return null;
    if (doc == null && baseUpdatedAt != null) return null;
    final revision = _nextRevision();
    docs[uid] = {'data': deep(payload), 'updatedAt': revision};
    return revision;
  }

  @override
  Future<Object> forceWrite(String uid, Map<String, dynamic> payload) async {
    forceWrites++;
    if (failWrite) throw StateError('cloud write failed');
    final revision = _nextRevision();
    docs[uid] = {'data': deep(payload), 'updatedAt': revision};
    return revision;
  }
}

/// A realistic cloud document for a Google session: same identity fields the
/// local snapshot carries, so an in-sync round trip compares equal.
Map<String, dynamic> cloudDataFor(
  Store s, {
  required String uid,
  required String email,
  int steps = 0,
  String name = 'Cloud User',
}) {
  final data = s.seed();
  data['user'] = email;
  data['accountId'] = uid;
  data['authProvider'] = 'google';
  data['name'] = name;
  data['steps'] = steps;
  return data;
}

/// Mutable harness for the migration tests: keeps the instrumented store,
/// the fake cloud seam, the confirmation prompts it received and the number
/// of link attempts, all updated in place while the migration runs.
class MigrationHarness {
  MigrationHarness({required this.store, required this.fake});

  final Store store;
  final FakeCloudUserDoc fake;
  final List<String> prompted = <String>[];
  int links = 0;
}

void main() {
  late List<Store> created;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    pbkdf2IterationsOverride = 1000;
    created = [];
  });

  tearDown(() {
    pbkdf2IterationsOverride = 0;
    for (final s in created) {
      s.dispose();
    }
  });

  /// Builds an initialised store. [cloud] injects the document seam; [link]
  /// makes an email account resolve its Firebase uid through the seam (what
  /// a configured Firebase project does for registration and login).
  Future<Store> newStore({FakeCloudUserDoc? cloud, bool link = false}) async {
    final s = Store()
      // Long enough that no debounced timer ever fires inside a test; syncs
      // are triggered explicitly with syncNow().
      ..syncDebounceDelay = const Duration(minutes: 5);
    if (cloud != null) s.cloudUserDoc = cloud;
    if (link) {
      s.cloudLinkOverride = ({
        required String email,
        required String password,
      }) async => 'uid-linked';
    }
    created.add(s);
    await s.init();
    return s;
  }

  /// Registers Ada and then signs her in, exactly like the app's flow:
  /// registration ends signed out and the session (cloud link included)
  /// only exists after the manual login that follows.
  Future<Store> registerAndSignIn(FakeCloudUserDoc cloud) async {
    final s = await newStore(cloud: cloud, link: true);
    await s.register(name: 'Ada', email: 'ada@b.com', password: 'password1');
    await s.login(email: 'ada@b.com', password: 'password1');
    return s;
  }

  Future<Store> newGoogleStore(FakeCloudUserDoc cloud, String uid) async {
    final s = await newStore();
    s.activateGoogleAccount(
      uid: uid,
      email: '$uid@example.com',
      displayName: 'User',
    );
    return s;
  }

  test(
    'cloud email account signs in on a fresh device and hydrates Firestore',
    () async {
      final cloud = FakeCloudUserDoc();
      final s = await newStore(cloud: cloud);
      s.cloudLinkOverride = ({
        required String email,
        required String password,
      }) async => 'cloud-uid';
      final remote = s.seed()
        ..['user'] = 'ada@example.com'
        ..['name'] = 'Cloud Ada'
        ..['steps'] = 4200;
      cloud.put('cloud-uid', remote, DateTime.now().millisecondsSinceEpoch);

      expect(
        await s.login(email: 'Ada@Example.com', password: 'cloud-password'),
        AuthResult.success,
      );
      expect(await s.syncNow(), isTrue);
      expect(s.hasActiveSession, isTrue);
      expect(s.sessionUid, 'cloud-uid');
      expect(s.d['name'], 'Cloud Ada');
      expect(s.d['steps'], 4200);
      expect(s.sp.getString(emailStorageKey('ada@example.com')), isNotNull);
    },
  );

  test(
    'fresh-device cloud login reports invalid credentials accurately',
    () async {
      final s = await newStore(cloud: FakeCloudUserDoc());
      s.cloudLinkOverride =
          ({required String email, required String password}) =>
              Future<String?>.error(
                FirebaseAuthException(code: 'invalid-credential'),
              );

      expect(
        await s.login(email: 'ada@example.com', password: 'wrong-password'),
        AuthResult.wrongPassword,
      );
      expect(s.hasActiveSession, isFalse);
      expect(s.sp.getString(emailStorageKey('ada@example.com')), isNull);
    },
  );

  Map<String, dynamic> accountJson(Store s, String key) =>
      jsonDecode(s.sp.getString(key)!) as Map<String, dynamic>;

  group('cloud payload sanitization', () {
    test('every credential and device-local field is stripped', () {
      final payload = sanitizedAccountForCloud(<String, dynamic>{
        'user': 'a@b.com',
        'name': 'A',
        'steps': 10,
        'cred': {
          'alg': 'pbkdf2-hmac-sha256',
          'salt': 'AAAA',
          'hash': 'BBBB',
          'iters': 1000,
        },
        'pw': 'plain-old-password',
        'password': 'plain-old-password',
        'hash': 'stale',
        'salt': 'stale',
        'cloudOptOut': true,
      });

      expect(payload.containsKey('cred'), isFalse);
      expect(payload.containsKey('pw'), isFalse);
      expect(payload.containsKey('password'), isFalse);
      expect(payload.containsKey('hash'), isFalse);
      expect(payload.containsKey('salt'), isFalse);
      expect(payload.containsKey('cloudOptOut'), isFalse);
      expect(payload['user'], 'a@b.com');
      expect(payload['name'], 'A');
      expect(payload['steps'], 10);
      expect(jsonEncode(payload), isNot(contains('plain-old-password')));
      expect(jsonEncode(payload), isNot(contains('AAAA')));
    });

    test('temporary auth errors are only transport/outage codes', () {
      for (final code in [
        'network-request-failed',
        'request-timeout',
        'internal-error',
        'unavailable',
        'too-many-requests',
      ]) {
        expect(isTemporaryAuthError(code), isTrue, reason: code);
      }
      // Permanent failures must never be papered over with an offline
      // fallback or an account-creation prompt.
      for (final code in [
        'wrong-password',
        'invalid-credential',
        'user-not-found',
        'email-already-in-use',
        'operation-not-allowed',
        'user-disabled',
      ]) {
        expect(isTemporaryAuthError(code), isFalse, reason: code);
      }
    });
  });

  group('sync direction policy', () {
    SyncDirection resolve({
      bool hasSyncState = false,
      bool localDirty = true,
      bool localHasFitness = false,
      Object? remoteUpdatedAt,
      int lastLocalEdit = 0,
    }) => resolveSyncDirection(
      hasSyncState: hasSyncState,
      localDirty: localDirty,
      localHasFitness: localHasFitness,
      remoteUpdatedAt: remoteUpdatedAt,
      lastLocalEdit: lastLocalEdit,
    );

    test('local matching the last synced hash hydrates', () {
      expect(
        resolve(
          hasSyncState: true,
          localDirty: false,
          localHasFitness: true,
          remoteUpdatedAt: 5,
          lastLocalEdit: 9,
        ),
        SyncDirection.hydrate,
      );
    });

    test('stale local data never overwrites a fresher cloud document', () {
      expect(
        resolve(
          hasSyncState: true,
          localDirty: true,
          localHasFitness: true,
          remoteUpdatedAt: 100,
          lastLocalEdit: 50,
        ),
        SyncDirection.hydrate,
      );
      expect(
        resolve(
          hasSyncState: false,
          localDirty: true,
          localHasFitness: true,
          remoteUpdatedAt: 100,
          lastLocalEdit: 50,
        ),
        SyncDirection.hydrate,
      );
    });

    test('local edits newer than the cloud revision push', () {
      expect(
        resolve(
          hasSyncState: true,
          localDirty: true,
          localHasFitness: true,
          remoteUpdatedAt: 50,
          lastLocalEdit: 100,
        ),
        SyncDirection.pushLocal,
      );
      // Unknown local edit time (0) never lets a cloud revision win silently.
      expect(
        resolve(
          hasSyncState: true,
          localDirty: true,
          localHasFitness: true,
          remoteUpdatedAt: 50,
          lastLocalEdit: 0,
        ),
        SyncDirection.pushLocal,
      );
    });

    test('a never-synced empty snapshot yields to existing cloud data', () {
      expect(
        resolve(hasSyncState: false, remoteUpdatedAt: 10, lastLocalEdit: 99),
        SyncDirection.hydrate,
      );
      expect(
        resolve(
          hasSyncState: false,
          localHasFitness: true,
          remoteUpdatedAt: 10,
          lastLocalEdit: 99,
        ),
        SyncDirection.pushLocal,
      );
    });

    test('fitness data detection covers every record bucket', () {
      final empty = Store().seed();
      expect(hasLocalFitnessData(empty), isFalse);

      for (final key in [
        'routines',
        'sch',
        'water',
        'act',
        'weights',
        'meals',
        'hist',
        'log',
      ]) {
        final snapshot = Store().seed();
        snapshot[key] = [
          key == 'weights'
              ? <dynamic>[today(), 80]
              : <String, dynamic>{'d': today()},
        ];
        expect(hasLocalFitnessData(snapshot), isTrue, reason: key);
      }

      final counted = Store().seed()..['steps'] = 5;
      expect(hasLocalFitnessData(counted), isTrue);
      final workout = Store().seed()..['activeW'] = {'rid': 'r1'};
      expect(hasLocalFitnessData(workout), isTrue);
    });
  });

  group('sync cycles', () {
    test('first sync with no document uploads a sanitized payload', () async {
      final fake = FakeCloudUserDoc();
      final s = await registerAndSignIn(fake);

      expect(await s.syncNow(), isTrue);

      final doc = fake.doc('uid-linked');
      expect(doc, isNotNull);
      final data = fake.data('uid-linked')!;
      expect(data['name'], 'Ada');
      expect(data['user'], 'ada@b.com');
      expect(data.containsKey('cred'), isFalse);
      expect(jsonEncode(data), isNot(contains('pbkdf2')));
      expect(jsonEncode(data), isNot(contains('password1')));
      expect(s.syncFailed, isFalse);

      final state = jsonDecode(
        s.sp.getString('ft_sync_state_uid-linked')!,
      ) as Map<String, dynamic>;
      expect(state['updatedAt'], doc!['updatedAt']);
      expect(state['hash'], canonicalAccountHash(data));
    });

    test('empty local data yields to an existing cloud document', () async {
      final fake = FakeCloudUserDoc();
      final s = await newGoogleStore(fake, 'u1');
      fake.put(
        'u1',
        cloudDataFor(s, uid: 'u1', email: 'u1@example.com', steps: 700),
        DateTime.now().millisecondsSinceEpoch - 1000,
      );
      s.cloudUserDoc = fake;

      expect(await s.syncNow(), isTrue);

      expect(s.steps, 700);
      expect(fake.data('u1')!['steps'], 700); // never blanked out
      expect(s.sp.getString(s.prehydrateBackupKey('u1')), isNotNull);
      expect(s.syncFailed, isFalse);
    });

    test(
      'an in-sync session leaves the document and backup untouched',
      () async {
        final fake = FakeCloudUserDoc();
        final s = await newGoogleStore(fake, 'u1');
        fake.put(
          'u1',
          cloudDataFor(s, uid: 'u1', email: 'u1@example.com', steps: 700),
          DateTime.now().millisecondsSinceEpoch - 1000,
        );
        s.cloudUserDoc = fake;
        expect(await s.syncNow(), isTrue);
        final backupAfterHydrate = s.sp.getString(s.prehydrateBackupKey('u1'));
        expect(backupAfterHydrate, isNotNull);

        // Nothing changed locally or remotely: no new hydration, no overwrite.
        expect(await s.syncNow(), isTrue);
        expect(s.sp.getString(s.prehydrateBackupKey('u1')), backupAfterHydrate);
        expect(fake.guardedWrites, 0);
        expect(s.syncFailed, isFalse);
      },
    );

    test(
      'a cloud snapshot cannot inject credentials or swap identity',
      () async {
        final fake = FakeCloudUserDoc();
        final s = await registerAndSignIn(fake);
        expect(await s.syncNow(), isTrue);
        final credBefore = jsonEncode(s.d['cred']);

        fake.put('uid-linked', <String, dynamic>{
          'user': 'evil@example.com',
          'name': 'Someone Else',
          'steps': 700,
          'cred': {
            'alg': 'pbkdf2-hmac-sha256',
            'salt': 'AAAA',
            'hash': 'BBBB',
            'iters': 1000,
          },
          'pw': 'injected',
          'password': 'injected',
        }, DateTime.now().millisecondsSinceEpoch + 60000);

        expect(await s.syncNow(), isTrue);

        expect(s.d['user'], 'ada@b.com');
        expect(s.d['steps'], 700);
        expect(jsonEncode(s.d['cred']), credBefore);
        expect(s.d.containsKey('pw'), isFalse);
        expect(s.d.containsKey('password'), isFalse);
        expect(jsonEncode(s.d), isNot(contains('injected')));
        // The local copy of the hostile document is recoverable, and the next
        // push still carries no credential material.
        expect(s.sp.getString(s.prehydrateBackupKey('uid-linked')), isNotNull);
        expect(sanitizedAccountForCloud(s.d).containsKey('cred'), isFalse);
      },
    );

    test(
      'unsynced local edits push and preserve the replaced cloud copy',
      () async {
        final fake = FakeCloudUserDoc();
        final s = await registerAndSignIn(fake);
        expect(await s.syncNow(), isTrue);

        s.d['steps'] = 42;
        s.d['hist'] = [
          {'d': today(), 'n': 'Push day', 'min': 30, 'ex': 3},
        ];
        s.save();
        expect(await s.syncNow(), isTrue);

        expect(fake.data('uid-linked')!['steps'], 42);
        final conflictBackup = jsonDecode(
          s.sp.getString(s.cloudConflictBackupKey('uid-linked'))!,
        ) as Map<String, dynamic>;
        expect(conflictBackup['steps'], 0);
        expect(s.syncFailed, isFalse);
      },
    );

    test(
      'stale local data does not overwrite a fresher cloud document',
      () async {
        final fake = FakeCloudUserDoc();
        final s = await newGoogleStore(fake, 'u1');
        s.cloudUserDoc = fake;
        s.d['steps'] = 10;
        s.save();
        expect(await s.syncNow(), isTrue); // local is now synced

        // Another device wrote more recently than this device last edited.
        final now = DateTime.now().millisecondsSinceEpoch;
        s.d['steps'] = 11;
        s.save();
        s.sp.setInt('ft_last_edit_ft_account_u1', now - 60000);
        fake.put(
          'u1',
          cloudDataFor(s, uid: 'u1', email: 'u1@example.com', steps: 999),
          now - 10000,
        );

        expect(await s.syncNow(), isTrue);

        expect(s.steps, 999); // newer cloud wins…
        expect(fake.data('u1')!['steps'], 999); // …and is not clobbered
        final backup = jsonDecode(
          s.sp.getString(s.prehydrateBackupKey('u1'))!,
        ) as Map<String, dynamic>;
        expect(backup['steps'], 11); // the stale local copy is recoverable
        expect(s.syncFailed, isFalse);
      },
    );

    test(
      'never-synced local fitness records win and keep the cloud copy',
      () async {
        final fake = FakeCloudUserDoc();
        final s = await newGoogleStore(fake, 'u1');
        s.d['steps'] = 1234;
        s.d['hist'] = [
          {'d': today(), 'n': 'Leg day', 'min': 45, 'ex': 4},
        ];
        s.save();
        fake.put(
          'u1',
          cloudDataFor(s, uid: 'u1', email: 'u1@example.com', steps: 500),
          DateTime.now().millisecondsSinceEpoch - 60000,
        );
        s.cloudUserDoc = fake;

        expect(await s.syncNow(), isTrue);

        expect(s.steps, 1234);
        expect(fake.data('u1')!['steps'], 1234);
        final conflictBackup = jsonDecode(
          s.sp.getString(s.cloudConflictBackupKey('u1'))!,
        ) as Map<String, dynamic>;
        expect(conflictBackup['steps'], 500);
        expect(s.syncFailed, isFalse);
      },
    );

    test(
      'a read failure keeps local data and surfaces the sync failure',
      () async {
        final fake = FakeCloudUserDoc()..failRead = true;
        final s = await newGoogleStore(fake, 'u1');
        s.d['steps'] = 42;
        s.save();
        s.cloudUserDoc = fake;

        expect(await s.syncNow(), isFalse);

        expect(s.syncFailed, isTrue);
        expect(s.syncError, contains('Cloud backup failed'));
        expect(s.syncStatusMessage, contains('Cloud backup failed'));
        expect(accountJson(s, 'ft_account_u1')['steps'], 42);
        expect(fake.docs, isEmpty);
      },
    );

    test(
      'a write failure keeps local data and a later cycle clears it',
      () async {
        final fake = FakeCloudUserDoc()..failWrite = true;
        final s = await newGoogleStore(fake, 'u1');
        s.d['steps'] = 42;
        s.save();
        s.cloudUserDoc = fake;

        expect(await s.syncNow(), isFalse);
        expect(s.syncFailed, isTrue);
        expect(accountJson(s, 'ft_account_u1')['steps'], 42);
        expect(fake.docs, isEmpty);

        fake.failWrite = false;
        expect(await s.syncNow(), isTrue);
        expect(s.syncFailed, isFalse);
        expect(s.syncError, isNull);
        expect(s.syncStatusMessage, 'Up to date with the cloud.');
        expect(fake.data('u1')!['steps'], 42);
      },
    );

    test('without a cloud seam the store stays fully local', () async {
      final s = await newStore();
      s.activateGoogleAccount(
        uid: 'u1',
        email: 'u1@example.com',
        displayName: 'U',
      );
      s.d['steps'] = 5;
      s.save();

      expect(s.syncEnabled, isFalse);
      expect(await s.syncNow(), isFalse);
      expect(s.syncFailed, isFalse); // nothing was attempted
      expect(s.syncStatusMessage, contains('Cloud backup unavailable'));
      expect(accountJson(s, 'ft_account_u1')['steps'], 5);
    });
  });

  group('account isolation', () {
    test(
      'sign-out during an in-flight pull never leaks into the next session',
      () async {
        final fake = FakeCloudUserDoc();
        fake.put('u1', <String, dynamic>{
          'user': 'u1@example.com',
          'steps': 4242,
          'routines': <dynamic>[],
          'sch': <dynamic>[],
          'water': <dynamic>[],
          'act': <dynamic>[],
          'weights': <dynamic>[],
          'meals': <dynamic>[],
          'hist': <dynamic>[],
          'log': <dynamic>[],
          'day': today(),
        }, DateTime.now().millisecondsSinceEpoch);

        final s = await newGoogleStore(fake, 'u1');
        s.d['steps'] = 100;
        s.save();
        s.cloudUserDoc = fake;
        fake.readGate = Completer<void>();

        final pending = s.syncNow(); // blocked inside the cloud read
        s.signOut();
        fake.readGate!.complete();

        expect(await pending, isFalse); // aborted at the epoch checkpoint
        expect(s.hasActiveSession, isFalse);
        expect(s.sessionUid, isNull);
        expect(s.syncRunning, isFalse);

        // The next session sees a clean seed — never the signed-out user's
        // cloud data (4242) or their local data (100).
        expect(s.d['user'], isNull);
        expect(s.steps, 0);
        expect(accountJson(s, 'ft')['steps'], 0);
        expect(accountJson(s, 'ft')['user'], isNull);

        // Nothing was written under the old identity: its own snapshot, sync
        // state and backups are exactly as sign-out left them.
        expect(accountJson(s, 'ft_account_u1')['steps'], 100);
        expect(s.sp.getString('ft_sync_state_u1'), isNull);
        expect(s.sp.getString(s.prehydrateBackupKey('u1')), isNull);
        expect(s.sp.getString(s.cloudConflictBackupKey('u1')), isNull);
        expect(fake.data('u1')!['steps'], 4242); // cloud doc untouched
      },
    );

    test(
      'switching accounts mid-pull keeps the new session isolated',
      () async {
        final fake = FakeCloudUserDoc();
        for (final uid in ['u1', 'u2']) {
          fake.put(uid, <String, dynamic>{
            'user': '$uid@example.com',
            'steps': uid == 'u1' ? 4242 : 7,
            'routines': <dynamic>[],
            'sch': <dynamic>[],
            'water': <dynamic>[],
            'act': <dynamic>[],
            'weights': <dynamic>[],
            'meals': <dynamic>[],
            'hist': <dynamic>[],
            'log': <dynamic>[],
            'day': today(),
          }, DateTime.now().millisecondsSinceEpoch - 60000);
        }

        final s = await newGoogleStore(fake, 'u1');
        s.d['steps'] = 100;
        s.save();
        s.cloudUserDoc = fake;
        fake.readGate = Completer<void>();

        final firstSession = s.syncNow(); // u1's cycle, blocked at the read
        s.activateGoogleAccount(
          uid: 'u2',
          email: 'u2@example.com',
          displayName: 'Second',
        );
        final secondSession = s.syncNow(); // joins u2's own cycle
        fake.readGate!.complete();

        expect(await secondSession, isTrue);
        expect(await firstSession, isFalse); // u1's cycle aborted at its check

        expect(s.sessionUid, 'u2');
        expect(s.d['user'], 'u2@example.com');
        expect(s.steps, 7); // never u1's 4242 or its local 100
        expect(accountJson(s, 'ft_account_u1')['steps'], 100); // untouched
        expect(accountJson(s, 'ft_account_u2')['steps'], 7); // hydrated for u2
        expect(s.syncRunning, isFalse);
      },
    );
  });

  group('local → cloud migration', () {
    /// Registers a local-only email account, then stands up the cloud seams
    /// (as if Firebase had become available) and instruments the link step.
    /// The link counter lives on the harness object: a record field would
    /// capture the value at construction time and miss every increment.
    Future<MigrationHarness> localAccount() async {
      final fake = FakeCloudUserDoc();
      final s = await newStore();
      await s.register(name: 'Ada', email: 'ada@b.com', password: 'password1');
      // Registration ends signed out; migration uploads from the signed-in
      // local account, so sign in first — before the cloud seams exist, so
      // this login stays local-only like the account being migrated.
      await s.login(email: 'ada@b.com', password: 'password1');
      s.d['steps'] = 42;
      s.d['goal'] = {'w': 72.0, 'd': 'cut', 'wk': 4, 'sw': 80.0};
      s.save();
      final ctx = MigrationHarness(store: s, fake: fake);
      s.cloudUserDoc = fake;
      s.cloudLinkOverride =
          ({required String email, required String password}) async {
            ctx.links++;
            return 'uid-migrated';
          };
      return ctx;
    }

    test(
      'a wrong password is refused before any prompt, link or backup',
      () async {
        final ctx = await localAccount();
        final s = ctx.store;

        final result = await s.migrateLocalAccountToCloud(
          password: 'not-my-password',
          requestConfirmation: (message) async {
            ctx.prompted.add(message);
            return true;
          },
        );

        expect(result, CloudMigrationResult.invalidPassword);
        expect(ctx.prompted, isEmpty);
        expect(ctx.links, 0);
        expect(s.sessionUid, isNull);
        expect(s.hasActiveSession, isTrue);
        expect(ctx.fake.docs, isEmpty);
        expect(
          s.sp.getString(s.migrationBackupKey(emailStorageKey('ada@b.com'))),
          isNull,
        );
        expect(accountJson(s, emailStorageKey('ada@b.com'))['steps'], 42);
      },
    );

    test('declining the confirmation uploads nothing', () async {
      final ctx = await localAccount();
      final s = ctx.store;

      final result = await s.migrateLocalAccountToCloud(
        password: 'password1',
        requestConfirmation: (message) async {
          ctx.prompted.add(message);
          return false;
        },
      );

      expect(result, CloudMigrationResult.declined);
      expect(ctx.prompted, hasLength(1));
      expect(ctx.links, 0);
      expect(s.sessionUid, isNull);
      expect(ctx.fake.docs, isEmpty);
      expect(
        s.sp.getString(s.migrationBackupKey(emailStorageKey('ada@b.com'))),
        isNull,
      );
      expect(accountJson(s, emailStorageKey('ada@b.com'))['steps'], 42);
    });

    test(
      'an unavailable cloud service is reported before confirmation',
      () async {
        final fake = FakeCloudUserDoc();
        final s = await newStore(cloud: fake);
        await s.register(
          name: 'Ada',
          email: 'ada@b.com',
          password: 'password1',
        );
        await s.login(email: 'ada@b.com', password: 'password1');
        var prompted = 0;

        final result = await s.migrateLocalAccountToCloud(
          password: 'password1',
          requestConfirmation: (_) async {
            prompted++;
            return true;
          },
        );

        expect(result, CloudMigrationResult.unavailable);
        expect(prompted, 0);
        expect(s.sessionUid, isNull);
        expect(s.hasActiveSession, isTrue);
      },
    );

    test(
      'a failed link keeps local data and the pre-migration backup',
      () async {
        final ctx = await localAccount();
        final s = ctx.store;
        s.cloudLinkOverride = ({
          required String email,
          required String password,
        }) async => null;

        final result = await s.migrateLocalAccountToCloud(
          password: 'password1',
          requestConfirmation: (_) async => true,
        );

        expect(result, CloudMigrationResult.failed);
        expect(s.sessionUid, isNull);
        expect(s.hasActiveSession, isTrue);
        expect(ctx.fake.docs, isEmpty);

        final backup = jsonDecode(
          s.sp.getString(s.migrationBackupKey(emailStorageKey('ada@b.com')))!,
        ) as Map<String, dynamic>;
        expect(backup['steps'], 42);
        expect(backup['goal']['w'], 72.0);

        // The live account is untouched and still signs in with the same hash.
        expect(accountJson(s, emailStorageKey('ada@b.com'))['steps'], 42);
        s.signOut();
        expect(
          await s.login(email: 'ada@b.com', password: 'password1'),
          AuthResult.success,
        );
        expect(s.steps, 42);
      },
    );

    test(
      'a successful migration uploads without credentials and backs up',
      () async {
        final ctx = await localAccount();
        final s = ctx.store;
        var prompted = 0;

        final result = await s.migrateLocalAccountToCloud(
          password: 'password1',
          requestConfirmation: (_) async {
            prompted++;
            return true;
          },
        );

        expect(result, CloudMigrationResult.success);
        expect(prompted, 1);
        expect(ctx.links, 1);
        expect(s.sessionUid, 'uid-migrated');
        expect(s.isCloudLinked, isTrue);

        final backup = jsonDecode(
          s.sp.getString(s.migrationBackupKey(emailStorageKey('ada@b.com')))!,
        ) as Map<String, dynamic>;
        expect(backup['steps'], 42);
        expect(backup.containsKey('cred'), isTrue); // local backup keeps it

        final cloud = ctx.fake.data('uid-migrated');
        expect(cloud, isNotNull);
        expect(cloud!['steps'], 42);
        expect(cloud['user'], 'ada@b.com');
        expect(cloud['goal']['w'], 72.0);
        expect(cloud.containsKey('cred'), isFalse); // cloud never receives it
        expect(jsonEncode(cloud), isNot(contains('pbkdf2')));
        expect(s.syncFailed, isFalse);
        expect(s.sp.getString('ft_sync_state_uid-migrated'), isNotNull);

        // Already linked: a second attempt is a no-op.
        expect(
          await s.migrateLocalAccountToCloud(
            password: 'password1',
            requestConfirmation: (_) async => true,
          ),
          CloudMigrationResult.alreadyLinked,
        );
        expect(ctx.links, 1);
      },
    );
  });

  group('reset behaviour', () {
    test(
      'reset pushes the same preserved profile and goals to the cloud',
      () async {
        final fake = FakeCloudUserDoc();
        final s = await registerAndSignIn(fake);
        s.d['name'] = 'Ada Lovelace';
        s.d['age'] = 34;
        s.d['h'] = 176;
        s.d['goal'] = {'w': 72.0, 'd': 'cut', 'wk': 4, 'sw': 80.0};
        s.d['nutritionGoals'] = {
          'calories': 1800,
          'protein': 150,
          'carbs': 180,
          'fat': 55,
        };
        s.d['steps'] = 900;
        s.d['hist'] = [
          {'d': today(), 'n': 'Push day', 'min': 30, 'ex': 3},
        ];
        s.save();
        expect(await s.syncNow(), isTrue);

        s.resetCurrentAccountData();
        expect(await s.syncNow(), isTrue);

        // Local: fitness gone, person intact.
        expect(s.steps, 0);
        expect(s.hist, isEmpty);
        expect(s.routines, isEmpty);
        expect(s.d['name'], 'Ada Lovelace');
        expect(s.d['age'], 34);
        expect(s.goal['w'], 72.0);
        expect(s.nutritionGoals['calories'], 1800);

        // Cloud: identical shape, no credentials.
        final cloud = fake.data('uid-linked')!;
        expect(cloud['steps'], 0);
        expect(cloud['hist'], isEmpty);
        expect(cloud['routines'], isEmpty);
        expect(cloud['name'], 'Ada Lovelace');
        expect(cloud['age'], 34);
        expect(cloud['goal']['w'], 72.0);
        expect(cloud['nutritionGoals']['calories'], 1800);
        expect(cloud.containsKey('cred'), isFalse);
        expect(s.syncFailed, isFalse);
      },
    );
  });
}
