import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/weight_estimator.dart';
import 'password_hash_web_stub.dart'
    if (dart.library.js_interop) 'password_hash_web.dart'
    as web_hash;

// ───────────────────────── THEME ─────────────────────────
const kPri = Color(0xFF0A7F6F);
const kDk = Color(0xFF1A4640);
const kLt = Color(0xFFD3EFE5);
const kBg = Color(0xFFF0F4F4);
const kInk = Color(0xFF0F2D29);
const kMut = Color(0xFF6F8A86);
const kLn = Color(0xFFE4ECEC);
const kRed = Color(0xFFC0392B);
const kMint = Color(0xFFA6EAD5);
const kBgDark = Color(0xFF0E1A19);
const kSurfaceDark = Color(0xFF162826);
const kLineDark = Color(0xFF29413D);
const muted = TextStyle(color: kMut, fontSize: 12);

bool isDark(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark;

Color primaryOf(BuildContext context) => isDark(context) ? kMint : kPri;

Color tintOf(BuildContext context) =>
    isDark(context) ? const Color(0xFF1D3934) : kLt;

// ───────────────────────── DATE HELPERS ─────────────────────────
String isoOf(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
String today() => isoOf(DateTime.now());
String daysAgo(int n) => isoOf(DateTime.now().subtract(Duration(days: n)));
String niceDate() {
  const w = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];
  const m = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  final n = DateTime.now();
  return '${w[n.weekday - 1]}, ${m[n.month - 1]} ${n.day}';
}

Map<String, dynamic> ex(String n, String m, int s, int r, int rest) => {
  'n': n,
  'm': m,
  's': s,
  'r': r,
  'rest': rest,
};

List<Map<String, dynamic>> exploreList() => [
  {
    'name': 'Full body HIIT',
    'type': 'Cardio',
    'level': 'Intermediate',
    'equipment': 'No equipment',
    'ex': [
      ex('Burpees', 'Full', 4, 12, 30),
      ex('Mountain climbers', 'Core', 4, 30, 30),
      ex('Jump squats', 'Legs', 4, 15, 30),
    ],
  },
  {
    'name': 'Push day',
    'type': 'Strength',
    'level': 'Intermediate',
    'equipment': 'Dumbbells',
    'ex': [
      ex('Push-ups', 'Chest', 4, 15, 45),
      ex('Overhead press', 'Shoulders', 3, 10, 60),
      ex('Dips', 'Triceps', 3, 12, 60),
    ],
  },
  {
    'name': 'Core crusher',
    'type': 'Strength',
    'level': 'Beginner',
    'equipment': 'No equipment',
    'ex': [
      ex('Crunches', 'Abs', 3, 20, 30),
      ex('Leg raises', 'Abs', 3, 15, 30),
      ex('Plank', 'Core', 3, 45, 30),
    ],
  },
];

// ───────────────────────── PASSWORD HASHING ─────────────────────────
// Local-only credential storage. Passwords are never persisted in plaintext;
// each account stores a PBKDF2-HMAC-SHA256 hash with a unique random salt.
// The iteration count is recorded per credential so it can be raised for new
// hashes without breaking verification of existing ones. This is device-local
// authentication, not a remote identity provider.

enum AuthResult {
  success,
  invalidInput,
  unknownEmail,
  wrongPassword,
  duplicateEmail,
  storageError,

  /// Temporary failure talking to the account service (typically network).
  /// No session was created unless the caller opted into offline mode.
  serviceError,
}

/// Outcome of a local password change. [wrongCurrentPassword] means the
/// existing credential did not verify; nothing was modified in that case.
enum PasswordChangeResult {
  success,
  invalidInput,
  wrongCurrentPassword,
  notEmailAccount,
  storageError,

  /// The cloud password change failed temporarily (typically network).
  /// The stored local credential was left untouched.
  serviceError,
}

/// UI-supplied confirmation prompt. Returns whether the user agreed.
typedef CloudConfirm = Future<bool> Function(String message);

/// Outcome of migrating an existing *local* account to Firebase.
enum CloudMigrationResult {
  /// Linked and uploaded; local data intact and a backup was written first.
  success,

  /// The session is already cloud-linked; nothing to do.
  alreadyLinked,

  /// The local PBKDF2 credential did not verify: migration is never offered,
  /// nothing is read for upload and nothing touches the cloud.
  invalidPassword,

  /// The user declined the confirmation dialog; nothing changed.
  declined,

  /// No cloud service is reachable or configured; nothing changed.
  unavailable,

  /// The cloud link attempt failed. Local data, credential, session and the
  /// pre-migration backup are all left in place.
  failed,
}

/// Exception codes that describe a temporary condition rather than a
/// permanent credential/config problem. Only these may ever be offered an
/// offline fallback; permanent credential failures never are.
bool isTemporaryAuthError(String code) =>
    code == 'network-request-failed' ||
    code == 'request-timeout' ||
    code == 'internal-error' ||
    code == 'unavailable' ||
    code == 'too-many-requests';

// ───────────────────────── CLOUD SYNC HELPERS ─────────────────────────
// The cloud document mirrors the account snapshot minus anything secret.
// Password material (PBKDF2 salt/hash) never leaves the device; the local
// login path does not need the cloud copy to verify a password.

/// Top-level snapshot keys that must never leave the device. [cred] holds the
/// PBKDF2 salt+hash, [cloudOptOut] is a device-local preference, and the rest
/// are legacy/plain-text credential spellings. Firestore rules reject the same
/// keys, so stripping them client-side keeps writes from failing server-side.
const kCloudFieldDenylist = [
  'cred',
  'pw',
  'password',
  'hash',
  'salt',
  'cloudOptOut',
];

/// Strips fields that must never be uploaded, in both directions of sync: the
/// result is what is written to `users/{uid}` and also what is accepted back
/// from it, so a hostile or legacy cloud document can never inject credential
/// material into local state.
@visibleForTesting
Map<String, dynamic> sanitizedAccountForCloud(Map<String, dynamic> account) {
  final copy = Map<String, dynamic>.from(account);
  for (final key in kCloudFieldDenylist) {
    copy.remove(key);
  }
  return copy;
}

/// Deterministic JSON with recursively sorted object keys, so hash
/// comparison is independent of map insertion order.
String _canonicalJson(Object? value) {
  if (value is Map) {
    final keys = value.keys.map((k) => k.toString()).toList()..sort();
    return '{${keys.map((k) => '${jsonEncode(k)}:${_canonicalJson(value[k])}').join(',')}}';
  }
  if (value is List) return '[${value.map(_canonicalJson).join(',')}]';
  return jsonEncode(value);
}

/// Stable content hash used to detect unsynced local edits.
@visibleForTesting
String canonicalAccountHash(Map<String, dynamic> account) =>
    sha256.convert(utf8.encode(_canonicalJson(account))).toString();

// ───────────────────────── CLOUD DOCUMENT API ─────────────────────────
// Document-level view of `users/{uid}`. The production implementation wraps
// Firestore (including its transaction), while tests inject a fake so that
// revision conflicts, stale data and transport failures can be driven
// deterministically without a live Firebase project.

/// Contents of one `users/{uid}` document read.
class CloudDocSnapshot {
  const CloudDocSnapshot({required this.exists, this.data});

  final bool exists;

  /// Raw document map (`{'data': ..., 'updatedAt': ...}`) when present.
  final Map<String, dynamic>? data;
}

/// Revision-guarded access to a single user document.
abstract class CloudUserDoc {
  /// Reads the document. Throws on transport failure.
  Future<CloudDocSnapshot> read(String uid);

  /// Compare-and-set write: only writes when the stored `updatedAt` still
  /// equals [baseUpdatedAt] (null means "expect no document"). Returns the
  /// new `updatedAt`, or null when the revision guard tripped — i.e. another
  /// device wrote in the meantime.
  Future<Object?> guardedWrite(
    String uid,
    Map<String, dynamic> payload,
    Object? baseUpdatedAt,
  );

  /// Unguarded write, used only after the replaced remote snapshot has been
  /// preserved in a local backup. Returns the new `updatedAt`.
  Future<Object> forceWrite(String uid, Map<String, dynamic> payload);
}

/// Firestore-backed [CloudUserDoc]: one transaction for the guarded write so
/// read and write are atomic server-side.
class FirestoreUserDoc implements CloudUserDoc {
  FirestoreUserDoc(this._db);

  final FirebaseFirestore _db;

  DocumentReference<Map<String, dynamic>> _ref(String uid) =>
      _db.collection('users').doc(uid);

  @override
  Future<CloudDocSnapshot> read(String uid) async {
    final snap = await _ref(uid).get();
    return CloudDocSnapshot(exists: snap.exists, data: snap.data());
  }

  @override
  Future<Object?> guardedWrite(
    String uid,
    Map<String, dynamic> payload,
    Object? baseUpdatedAt,
  ) => _db.runTransaction((tx) async {
    final snap = await tx.get(_ref(uid));
    if (snap.exists) {
      if (snap.data()?['updatedAt'] != baseUpdatedAt) return null;
    } else if (baseUpdatedAt != null) {
      return null;
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    tx.set(_ref(uid), {'data': payload, 'updatedAt': now});
    return now;
  });

  @override
  Future<Object> forceWrite(String uid, Map<String, dynamic> payload) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _ref(uid).set({'data': payload, 'updatedAt': now});
    return now;
  }
}

/// Which side a sync cycle should take.
enum SyncDirection { hydrate, pushLocal }

/// Decides whether the local snapshot or the cloud document wins for one
/// sync cycle. Pure and exhaustive so the conflict policy is testable:
///
///  1. Local matches the last synced hash → hydrate (nothing local to lose).
///  2. Cloud revision newer than the last local edit → hydrate, so stale
///     local data can never overwrite a fresher document from another device.
///  3. Never synced and the local snapshot has no fitness records → hydrate,
///     so a fresh install cannot blank out an existing cloud document.
///  4. Otherwise → push local; the caller preserves the remote snapshot in a
///     recoverable backup first (last write wins, never silently).
@visibleForTesting
SyncDirection resolveSyncDirection({
  required bool hasSyncState,
  required bool localDirty,
  required bool localHasFitness,
  required Object? remoteUpdatedAt,
  required int lastLocalEdit,
}) {
  if (hasSyncState && !localDirty) return SyncDirection.hydrate;
  final remoteTime = remoteUpdatedAt is int ? remoteUpdatedAt : 0;
  if (lastLocalEdit > 0 && remoteTime > lastLocalEdit) {
    return SyncDirection.hydrate;
  }
  if (!hasSyncState && !localHasFitness) return SyncDirection.hydrate;
  return SyncDirection.pushLocal;
}

/// True when [snapshot] holds at least one fitness record. Used by the
/// never-synced rule above: only a snapshot with real data is allowed to
/// replace an existing cloud document.
@visibleForTesting
bool hasLocalFitnessData(Map<String, dynamic> snapshot) {
  const collections = [
    'routines',
    'sch',
    'water',
    'act',
    'weights',
    'meals',
    'hist',
    'log',
  ];
  for (final key in collections) {
    final value = snapshot[key];
    if (value is List && value.isNotEmpty) return true;
  }
  if (((snapshot['steps'] as num?) ?? 0) != 0) return true;
  if (snapshot['activeW'] is Map) return true;
  return false;
}

const _pbkdf2Iterations = 210000;
const _pbkdf2KeyLength = 32;
const _pbkdf2SaltLength = 16;
const _pbkdf2DigestLength = 32; // SHA-256 output size (hLen).

/// When > 0, replaces the production iteration count. Tests set this low so
/// hashing stays fast; production code must never assign it.
@visibleForTesting
int pbkdf2IterationsOverride = 0;

int _effectiveIterations() =>
    pbkdf2IterationsOverride > 0 ? pbkdf2IterationsOverride : _pbkdf2Iterations;

/// Top-level so it can be dispatched to a background isolate via [compute].
Uint8List _pbkdf2Task(Map<String, dynamic> args) {
  final password = args['password'] as String;
  final salt = args['salt'] as List<int>;
  final iterations = args['iterations'] as int;
  final keyLength = args['keyLength'] as int;

  final hmac = Hmac(sha256, utf8.encode(password));
  final blockCount = (keyLength / _pbkdf2DigestLength).ceil();
  final output = BytesBuilder(copy: false);
  for (var block = 1; block <= blockCount; block++) {
    // U_1 = PRF(P, S || INT_32_BE(block)); U_j = PRF(P, U_{j-1});
    // T_block = U_1 xor U_2 xor ... xor U_iterations.
    var u = hmac.convert([
      ...salt,
      (block >> 24) & 0xff,
      (block >> 16) & 0xff,
      (block >> 8) & 0xff,
      block & 0xff,
    ]).bytes;
    final t = List<int>.from(u);
    for (var i = 1; i < iterations; i++) {
      u = hmac.convert(u).bytes;
      for (var j = 0; j < t.length; j++) {
        t[j] ^= u[j];
      }
    }
    output.add(t);
  }
  final bytes = output.takeBytes();
  return Uint8List.fromList(
    bytes.length > keyLength ? bytes.sublist(0, keyLength) : bytes,
  );
}

/// CPU time handed to the web hasher before it yields to the event loop.
/// Small enough that frames and input slip through within ~a frame, large
/// enough that timer overhead does not meaningfully stretch the total hash.
const _kPbkdf2SliceMicros = 8000;

/// Web twin of [_pbkdf2Task]. On the web, [compute] has no isolates and runs
/// its callback synchronously on the UI thread, so a full 210k-iteration
/// PBKDF2 would freeze Chrome for about a minute. This runs the identical
/// math in short slices and yields between them so the browser keeps painting
/// and processing input. Salt, iteration count and password fully determine
/// the output, so the bytes are identical to [_pbkdf2Task] — existing stored
/// credentials keep verifying (locked in by the sync-vs-chunked test).
Future<Uint8List> _pbkdf2Chunked(Map<String, dynamic> args) async {
  final password = args['password'] as String;
  final salt = args['salt'] as List<int>;
  final iterations = args['iterations'] as int;
  final keyLength = args['keyLength'] as int;

  final hmac = Hmac(sha256, utf8.encode(password));
  final blockCount = (keyLength / _pbkdf2DigestLength).ceil();
  final output = BytesBuilder(copy: false);
  final slice = Stopwatch()..start();
  for (var block = 1; block <= blockCount; block++) {
    // U_1 = PRF(P, S || INT_32_BE(block)); U_j = PRF(P, U_{j-1});
    // T_block = U_1 xor U_2 xor ... xor U_iterations.
    var u = hmac.convert([
      ...salt,
      (block >> 24) & 0xff,
      (block >> 16) & 0xff,
      (block >> 8) & 0xff,
      block & 0xff,
    ]).bytes;
    final t = List<int>.from(u);
    for (var i = 1; i < iterations; i++) {
      u = hmac.convert(u).bytes;
      for (var j = 0; j < t.length; j++) {
        t[j] ^= u[j];
      }
      if ((i & 63) == 0 && slice.elapsedMicroseconds >= _kPbkdf2SliceMicros) {
        await Future<void>.delayed(Duration.zero);
        slice.reset();
      }
    }
    output.add(t);
  }
  final bytes = output.takeBytes();
  return Uint8List.fromList(
    bytes.length > keyLength ? bytes.sublist(0, keyLength) : bytes,
  );
}

/// Native targets derive in a background isolate. Web uses the browser's
/// native Web Crypto implementation, falling back to the yielding Dart
/// implementation when Web Crypto is unavailable.
Future<Uint8List> _deriveKey(Map<String, dynamic> args) =>
    kIsWeb ? _deriveWebKey(args) : compute(_pbkdf2Task, args);

Future<Uint8List> _deriveWebKey(Map<String, dynamic> args) async {
  final result = await web_hash.derivePbkdf2(
    password: args['password'] as String,
    salt: args['salt'] as List<int>,
    iterations: args['iterations'] as int,
    keyLength: args['keyLength'] as int,
  );
  return result ?? _pbkdf2Chunked(args);
}

@visibleForTesting
Uint8List pbkdf2SyncForTest(Map<String, dynamic> args) => _pbkdf2Task(args);

@visibleForTesting
Future<Uint8List> pbkdf2ChunkedForTest(Map<String, dynamic> args) =>
    _pbkdf2Chunked(args);

@visibleForTesting
Future<Uint8List> pbkdf2WebForTest(Map<String, dynamic> args) =>
    _deriveWebKey(args);

bool _constantTimeEquals(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a[i] ^ b[i];
  }
  return diff == 0;
}

String normalizeEmail(String email) => email.trim().toLowerCase();

/// Stable, collision-resistant storage key for an email account. The raw
/// email is never used in a storage-key name.
String emailStorageKey(String normalizedEmail) =>
    'ft_email_account_${sha256.convert(utf8.encode(normalizedEmail))}';

const _sessionMetaKey = 'ft_session_meta';
const _legacyBackupKey = 'ft_legacy_backup';

Future<Map<String, dynamic>> _hashPassword(String password) async {
  final iterations = _effectiveIterations();
  final salt = Uint8List(_pbkdf2SaltLength);
  final rng = Random.secure();
  for (var i = 0; i < salt.length; i++) {
    salt[i] = rng.nextInt(256);
  }
  final hash = await _deriveKey({
    'password': password,
    'salt': salt,
    'iterations': iterations,
    'keyLength': _pbkdf2KeyLength,
  });
  return {
    'v': 1,
    'alg': 'pbkdf2-hmac-sha256',
    'iters': iterations,
    'salt': base64Encode(salt),
    'hash': base64Encode(hash),
  };
}

Future<bool> _verifyPassword(String password, Map<String, dynamic> cred) async {
  if (cred['alg'] != 'pbkdf2-hmac-sha256') return false;
  final salt = base64Decode(cred['salt'] as String);
  final storedHash = base64Decode(cred['hash'] as String);
  final iterations = (cred['iters'] as num?)?.toInt() ?? _effectiveIterations();
  if (iterations < 1) return false;
  final derived = await _deriveKey({
    'password': password,
    'salt': salt,
    'iterations': iterations,
    'keyLength': storedHash.length,
  });
  return _constantTimeEquals(derived, storedHash);
}

// ───────────────────────── INPUT LIMITS ─────────────────────────
// Shared ranges for workout configuration and live set logging so every
// entry point enforces the same sensible bounds.
const kSetsMin = 1;
const kSetsMax = 20;
const kRepsMin = 1;
const kRepsMax = 300;
const kRestMin = 0;
const kRestMax = 600;
const kKgMin = 0.0;
const kKgMax = 500.0;

/// User-facing error when a routine's sets/reps/rest fall outside the
/// supported ranges, or null when the values are valid.
String? validateExerciseConfig(num sets, num reps, num rest) {
  if (sets < kSetsMin || sets > kSetsMax) {
    return 'Sets must be between $kSetsMin and $kSetsMax.';
  }
  if (reps < kRepsMin || reps > kRepsMax) {
    return 'Reps must be between $kRepsMin and $kRepsMax.';
  }
  if (rest < kRestMin || rest > kRestMax) {
    return 'Rest must be between $kRestMin and $kRestMax seconds.';
  }
  return null;
}

/// User-facing error when a logged set's weight/reps are out of range.
String? validateSetLoad(num kg, num reps) {
  if (kg < kKgMin || kg > kKgMax) {
    return 'Weight must be between 0 and ${kKgMax.toInt()} kg.';
  }
  if (reps < kRepsMin || reps > kRepsMax) {
    return 'Reps must be between $kRepsMin and $kRepsMax.';
  }
  return null;
}

/// Validates every set row of one exercise; returns the first error found.
String? validateSetRow(List<Map<String, dynamic>> row) {
  for (final s in row) {
    final err = validateSetLoad((s['kg'] as num?) ?? 0, (s['rp'] as num?) ?? 0);
    if (err != null) return err;
  }
  return null;
}

// ───────────────────────── STORE ─────────────────────────
class Store extends ChangeNotifier {
  late SharedPreferences sp;
  Map<String, dynamic> d = {};

  String? _sessionKey;
  String? _sessionProvider; // 'email' | 'google'
  String? _sessionEmail;
  String? _sessionUid; // Firebase uid when the account is cloud-linked

  bool get hasActiveSession => _sessionKey != null;
  bool get isEmailAccount => _sessionProvider == 'email';
  bool get hasLocalCredential => d['cred'] is Map;
  String? get sessionUid => _sessionUid;
  bool get isCloudLinked => _sessionUid != null;

  /// True once [Firebase.initializeApp] succeeded in main(). Tests and
  /// unconfigured platforms run fully local: every cloud call is skipped.
  static bool get _firebaseReady => Firebase.apps.isNotEmpty;

  FirebaseAuth get _auth => FirebaseAuth.instance;
  FirebaseFirestore get _firestore => FirebaseFirestore.instance;

  // Cloud-sync state for the active session. All of it is best-effort: any
  // failure leaves local storage authoritative and retryable.
  Timer? _syncDebounce;
  Future<bool>? _syncInFlight;
  int? _syncInFlightEpoch;
  bool _syncFailed = false;
  String? _syncError;
  bool _disposed = false;

  /// Bumped whenever the active identity changes (bind, switch, sign-out).
  /// Every in-flight cloud operation re-checks it after each await, so a slow
  /// response can never hydrate or overwrite a different account's session.
  int _sessionEpoch = 0;

  /// Debounce applied to [save]-triggered syncs. Shortened by tests.
  @visibleForTesting
  Duration syncDebounceDelay = const Duration(seconds: 2);

  /// Test seam replacing the Firestore document. Null in production, where
  /// [FirestoreUserDoc] is used.
  @visibleForTesting
  CloudUserDoc? cloudUserDoc;

  /// Test seam replacing the Firebase Auth email/password step (the link
  /// attempted by registration and migration, and the sign-in login performs
  /// after the local password verified). Null in production, where
  /// [FirebaseAuth] is used.
  @visibleForTesting
  Future<String?> Function({required String email, required String password})?
  cloudLinkOverride;

  /// Upper bound on the cloud sign-in [register] and [login] make after the
  /// local credential has been verified. Firebase's own network timeout is
  /// measured in minutes and a wedged response can take even longer or never
  /// arrive at all, so without this the auth button's spinner waits forever
  /// on a call both flows are built to survive the failure of. Generous for a
  /// slow mobile network, far below the point where a spinner looks frozen.
  @visibleForTesting
  Duration cloudLinkTimeout = const Duration(seconds: 15);

  /// Firestore is configured, or a test seam stands in for it: sync may run.
  bool get _cloudReady => _firebaseReady || cloudUserDoc != null;

  /// A cloud link can be attempted (Firebase configured or seam present).
  bool get _linkReady => _firebaseReady || cloudLinkOverride != null;

  // ── Sync status, surfaced by the Profile screen ──
  bool get syncEnabled => _cloudReady && _sessionUid != null;
  bool get syncRunning => _syncInFlight != null;
  bool get syncPending => _syncDebounce?.isActive ?? false;
  bool get syncFailed => _syncFailed;
  String? get syncError => _syncError;

  /// One-line status for the Profile screen. Failures are never silent: they
  /// stay visible until a later cycle succeeds.
  String get syncStatusMessage {
    if (!hasActiveSession) return 'Not signed in.';
    if (!isCloudLinked) {
      return _cloudReady
          ? 'Local only — this account is not backed up to the cloud yet.'
          : 'Local only — cloud backup is unavailable.';
    }
    if (syncRunning) return 'Backing up to the cloud…';
    if (_syncFailed) return _syncError ?? 'Backup failed.';
    if (syncPending) return 'Waiting to back up…';
    if (!_cloudReady) {
      return 'Cloud backup unavailable — saving on this device.';
    }
    return 'Up to date with the cloud.';
  }

  static double _safeDouble(Object? value, {double fallback = 0.0}) {
    if (value is num) {
      final numValue = value.toDouble();
      return numValue.isFinite ? numValue : fallback;
    }
    return fallback;
  }

  static int _safeInt(Object? value, {required int fallback}) {
    if (value is num) {
      final numValue = value.toDouble();
      if (numValue.isFinite) return numValue.toInt();
    }
    return fallback;
  }

  String _syncStateKey(String uid) => 'ft_sync_state_$uid';
  String _lastLocalEditKey(String sessionKey) => 'ft_last_edit_$sessionKey';

  /// Recoverable copy of the local snapshot taken right before a cloud
  /// document overwrites it.
  @visibleForTesting
  String prehydrateBackupKey(String uid) => 'ft_prehydrate_backup_$uid';

  /// Recoverable copy of the cloud snapshot taken right before a local
  /// snapshot overwrites it (guarded last-write-wins on conflict retry).
  @visibleForTesting
  String cloudConflictBackupKey(String uid) => 'ft_cloud_conflict_backup_$uid';

  /// Recoverable copy of the local snapshot taken immediately before an
  /// existing local account is first uploaded to the cloud.
  @visibleForTesting
  String migrationBackupKey(String sessionKey) =>
      'ft_migration_backup_$sessionKey';

  /// Notification helper that tolerates an in-flight sync finishing after the
  /// store has been disposed (tests tear stores down while cycles run).
  void _notify() {
    if (_disposed) return;
    notifyListeners();
  }

  void _markSyncSuccess() {
    if (!_syncFailed) return;
    _syncFailed = false;
    _syncError = null;
    _notify();
  }

  void _markSyncFailure(Object error) {
    _syncFailed = true;
    _syncError = _syncFailureMessage(error);
    _notify();
  }

  static String _syncFailureMessage(Object error) {
    if (error is FirebaseException) {
      return switch (error.code) {
        'permission-denied' =>
          'Cloud backup was denied. Sign in as this account and check the '
              'security rules.',
        'unauthenticated' => 'Sign in again to resume cloud backups.',
        'unavailable' =>
          'Cloud storage is unreachable. Your data is saved on this device.',
        'resource-exhausted' =>
          'Cloud backup is rate-limited right now. It will retry shortly.',
        _ => 'Cloud backup failed. Your data is saved on this device.',
      };
    }
    return 'Cloud backup failed. Your data is saved on this device.';
  }

  Future<void> init() async {
    sp = await SharedPreferences.getInstance();
    await _migrateLegacyData();
    _loadSession();
    roll();
    if (isCloudLinked) unawaited(_pullFromCloud());
  }

  Map<String, dynamic> seed() => {
    'user': null,
    'name': '',
    'age': null,
    'h': null,
    'sex': 'other',
    'activityLevel': 'light',
    'lb': false,
    'wr': true,
    'wtr': true,
    'mr': false,
    'dark': false,
    'goal': {'w': 0.0, 'd': '', 'wk': 3, 'sw': 0.0},
    'nutritionGoals': {
      'calories': 2100,
      'protein': 140,
      'carbs': 220,
      'fat': 65,
    },
    'activityGoals': {'waterMl': 2500, 'steps': 8000},
    'routines': <Map<String, dynamic>>[],
    'sch': <Map<String, dynamic>>[],
    'water': <Map<String, dynamic>>[],
    'steps': 0,
    'act': <Map<String, dynamic>>[],
    'weights': <List<dynamic>>[],
    'meals': <Map<String, dynamic>>[],
    'hist': <Map<String, dynamic>>[],
    'day': today(),
    'log': [],
  };

  // Encode once and reuse for both buckets: every save previously ran
  // jsonEncode over the whole snapshot twice, which is main-thread work
  // (felt on web/debug) and doubled localStorage writes.
  void save() {
    WeightEstimator.calculate(d);
    final payload = jsonEncode(d);
    sp.setString('ft', payload);
    final key = _sessionKey;
    if (key != null && key.isNotEmpty) {
      sp.setString(key, payload);
      _touchLocalEdit(key);
    }
    _scheduleSync();
    notifyListeners();
  }

  /// Like [save], but does not notify listeners. Used for frequent progress
  /// snapshots (e.g. active workout persistence) where a full app rebuild
  /// per update would be wasteful.
  void saveQuiet() {
    WeightEstimator.calculate(d);
    final payload = jsonEncode(d);
    sp.setString('ft', payload);
    final key = _sessionKey;
    if (key != null && key.isNotEmpty) {
      sp.setString(key, payload);
      _touchLocalEdit(key);
    }
    _scheduleSync();
  }

  /// Records when this account last changed on this device. Sync cycles
  /// compare it against the cloud `updatedAt` revision so a stale local copy
  /// never overwrites a document another device wrote more recently.
  void _touchLocalEdit(String sessionKey) {
    sp.setInt(
      _lastLocalEditKey(sessionKey),
      DateTime.now().millisecondsSinceEpoch,
    );
  }

  int _lastLocalEdit() {
    final key = _sessionKey;
    if (key == null || key.isEmpty) return 0;
    return sp.getInt(_lastLocalEditKey(key)) ?? 0;
  }

  // ─────────── Session pointer ───────────
  void _writeSessionMeta() {
    // A new identity invalidates anything an older session left in flight.
    _sessionEpoch++;
    sp.setString(
      _sessionMetaKey,
      jsonEncode({
        'provider': _sessionProvider,
        'key': _sessionKey,
        'email': _sessionEmail,
        'uid': _sessionUid,
      }),
    );
  }

  void _clearSessionState() {
    _sessionEpoch++;
    _sessionKey = null;
    _sessionProvider = null;
    _sessionEmail = null;
    _sessionUid = null;
  }

  void _loadSession() {
    final metaRaw = sp.getString(_sessionMetaKey);
    if (metaRaw == null) {
      _clearSessionState();
      d = seed();
      return;
    }

    Map<String, dynamic>? meta;
    try {
      final decoded = jsonDecode(metaRaw);
      if (decoded is Map) meta = Map<String, dynamic>.from(decoded);
    } catch (_) {
      meta = null;
    }

    final key = meta?['key'];
    if (meta == null || key is! String || key.isEmpty) {
      sp.remove(_sessionMetaKey);
      _clearSessionState();
      d = seed();
      return;
    }

    _sessionKey = key;
    final provider = meta['provider'];
    final email = meta['email'];
    final uid = meta['uid'];
    _sessionProvider = provider is String ? provider : null;
    _sessionEmail = email is String ? email : null;
    _sessionUid = uid is String && uid.isNotEmpty ? uid : null;

    final raw = sp.getString(key);
    if (raw == null) {
      sp.remove(_sessionMetaKey);
      _clearSessionState();
      d = seed();
      return;
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        d = decoded;
      } else if (decoded is Map) {
        d = Map<String, dynamic>.from(decoded);
      } else {
        throw const FormatException('Account snapshot is not a JSON object.');
      }
    } catch (_) {
      // Corrupt snapshot: keep it on disk for recovery, sign out, and fall
      // back to a safe seed. Never overwrite the corrupt bucket with seed.
      sp.remove(_sessionMetaKey);
      _clearSessionState();
      d = seed();
      return;
    }

    // Re-assert identity from the session pointer so a stale snapshot cannot
    // present a different user.
    if (_sessionEmail != null) d['user'] = _sessionEmail;
    if (_sessionProvider == 'google') {
      d['authProvider'] = 'google';
      const prefix = 'ft_account_';
      if (key.startsWith(prefix)) d['accountId'] = key.substring(prefix.length);
    } else {
      d.remove('accountId');
      d.remove('authProvider');
    }
  }

  // ─────────── Legacy migration ───────────
  // Converts the old single-bucket ('ft') layout into per-account snapshots.
  // Runs at most once: it is skipped whenever a session pointer already
  // exists, and it removes the live 'ft' key after handling so a second run
  // is a no-op. The original raw 'ft' value is preserved under
  // [ _legacyBackupKey ] before anything is modified.
  Future<void> _migrateLegacyData() async {
    if (sp.containsKey(_sessionMetaKey)) return;

    final rawFt = sp.getString('ft');
    if (rawFt == null || rawFt.isEmpty) return;

    if (!sp.containsKey(_legacyBackupKey)) {
      sp.setString(_legacyBackupKey, rawFt);
    }

    Map<String, dynamic>? legacy;
    try {
      final decoded = jsonDecode(rawFt);
      if (decoded is Map<String, dynamic>) {
        legacy = decoded;
      } else if (decoded is Map) {
        legacy = Map<String, dynamic>.from(decoded);
      }
    } catch (_) {
      legacy = null;
    }

    if (legacy == null) {
      // Undecodable: backup preserved, live bucket cleared so startup does
      // not crash. No account snapshot is created from garbage.
      sp.remove('ft');
      return;
    }

    // Google-account legacy bucket: preserve under the existing UID key so
    // Google UID storage behaviour is unchanged.
    final accountId = legacy['accountId'];
    if (accountId is String && accountId.isNotEmpty) {
      final googleKey = 'ft_account_$accountId';
      if (!sp.containsKey(googleKey)) {
        final cleaned = Map<String, dynamic>.from(legacy);
        cleaned.remove('pw'); // never persist plaintext credentials
        sp.setString(googleKey, jsonEncode(cleaned));
      }
      sp.remove('ft');
      return;
    }

    // Email-account legacy bucket: migrate only when ownership can be
    // attributed to a single last-user with a non-empty password. The
    // plaintext password is hashed exactly once here and then discarded.
    final lastUser = legacy['lastUser'];
    final legacyPw = legacy['pw'];
    if (lastUser is String &&
        lastUser.trim().isNotEmpty &&
        legacyPw is String &&
        legacyPw.isNotEmpty) {
      final normalized = normalizeEmail(lastUser);
      final emailKey = emailStorageKey(normalized);
      if (!sp.containsKey(emailKey)) {
        final migrated = Map<String, dynamic>.from(legacy);
        migrated.remove('pw');
        migrated.remove('user');
        migrated.remove('lastUser');
        migrated.remove('accountId');
        migrated.remove('authProvider');
        migrated['user'] = normalized;
        migrated['cred'] = await _hashPassword(legacyPw);
        sp.setString(emailKey, jsonEncode(migrated));
      }
      sp.remove('ft');
      return;
    }

    // Anonymous or passwordless legacy data: ownership cannot be verified
    // safely. Preserve the backup, clear the live bucket, start fresh.
    sp.remove('ft');
  }

  // ─────────── Email authentication ───────────
  // Local PBKDF2 credentials remain the source of truth and keep working
  // with no network. Firebase Auth is linked best-effort for local accounts;
  // cloud-only accounts authenticate with Firebase before a local verifier is
  // created. Login never creates a cloud account without explicit confirmation.
  //
  // Registration deliberately does *not* authenticate the app: it creates
  // the account, ends signed out, and the user signs in separately from the
  // Login screen. That keeps the root app (which rebuilds to the dashboard
  // whenever it sees a session) from treating account creation as a login.
  Future<AuthResult> register({
    required String name,
    required String email,
    required String password,
  }) async {
    final normalized = normalizeEmail(email);
    if (normalized.isEmpty ||
        !normalized.contains('@') ||
        name.trim().isEmpty ||
        password.length < 8) {
      return AuthResult.invalidInput;
    }
    final key = emailStorageKey(normalized);
    if (sp.containsKey(key)) return AuthResult.duplicateEmail;

    final cred = await _hashPassword(password);
    final fresh = seed();
    fresh['user'] = normalized;
    fresh['name'] = name.trim();
    fresh['cred'] = cred;

    // The account is built behind a quiet session pointer so the bucket
    // write reuses the normal save path, but nothing notifies while that
    // pointer is set and no pointer is ever persisted: listeners must only
    // ever observe the signed-out state this method ends in, and an app
    // killed mid-registration must never resume already signed in. The
    // epoch bump also aborts anything a previous identity left in flight.
    _sessionEpoch++;
    d = fresh;
    _sessionKey = key;
    _sessionProvider = 'email';
    _sessionEmail = normalized;
    _sessionUid = null;
    saveQuiet();

    // Registration ends exactly like a sign-out: the account (identity,
    // profile, credential) is flushed into its own bucket, the session
    // pointer and any queued sync are cleared, and the single notification
    // this triggers carries the signed-out state only.
    signOut();
    _linkCloudAccountInBackground(email: normalized, password: password);
    return AuthResult.success;
  }

  void _linkCloudAccountInBackground({
    required String email,
    required String password,
  }) {
    final link = _establishCloudLink(email: email, password: password);
    unawaited(() async {
      try {
        final uid = await link.timeout(cloudLinkTimeout);
        // Firebase account creation also signs in on this device. Keep the
        // registration flow signed out after the best-effort link completes.
        await _detachFirebaseAuth(uid);
      } on TimeoutException {
        _detachAbandonedLink(link);
      } on Object {
        // Cloud linking is optional; the saved local account remains usable.
      }
    }());
  }

  /// Signs out the cloud user behind a link attempt that [cloudLinkTimeout]
  /// made [register] or [login] stop waiting for. Firebase does not cancel
  /// its call when the wait is abandoned, so a response arriving minutes
  /// later would otherwise leave this device signed in to a session the user
  /// has already been told never happened. Runs detached and swallows its
  /// own failures: by then there is nobody left to report them to.
  void _detachAbandonedLink(Future<String?> abandoned) {
    unawaited(abandoned.then<void>(_detachFirebaseAuth, onError: (_) {}));
  }

  /// Signs out the Firebase session a cloud link just created or restored —
  /// by [register] before its local teardown, or by [_detachAbandonedLink]
  /// for a response that arrived after the wait was abandoned. Only that one
  /// user is signed out: any other (e.g. Google) session is left untouched,
  /// and so is a uid the app has since signed into — re-signing the very
  /// account being registered or logged in yields the same uid, and pulling
  /// it out from under a live session would silently sign that session's
  /// cloud side off. Best-effort — the local state is what gates the app.
  Future<void> _detachFirebaseAuth(String? uid) async {
    if (!_firebaseReady || uid == null) return;
    if (_sessionUid == uid) return;
    try {
      if (_auth.currentUser?.uid == uid) {
        await _auth.signOut();
      }
    } catch (_) {
      // Remote sign-in is best-effort; local state is already authoritative.
    }
  }

  Future<AuthResult> login({
    required String email,
    required String password,
    CloudConfirm? requestCloudAccountCreation,
    CloudConfirm? requestOfflineFallback,
  }) async {
    final normalized = normalizeEmail(email);
    if (normalized.isEmpty || password.isEmpty) return AuthResult.invalidInput;

    final key = emailStorageKey(normalized);
    final raw = sp.getString(key);
    Map<String, dynamic> account;
    String? cloudUid;
    Future<String?>? pending;

    if (raw == null) {
      // Cloud accounts must be usable on a fresh device. Firebase verifies
      // the password before we create a local verifier or load any profile.
      try {
        pending = _startCloudSignIn(email: normalized, password: password);
        if (pending == null) return AuthResult.unknownEmail;
        cloudUid = await pending.timeout(cloudLinkTimeout);
        if (cloudUid == null) return AuthResult.serviceError;
      } on TimeoutException {
        final abandoned = pending;
        if (abandoned != null) _detachAbandonedLink(abandoned);
        return AuthResult.serviceError;
      } on FirebaseAuthException catch (e) {
        return switch (e.code) {
          'user-not-found' => AuthResult.unknownEmail,
          'wrong-password' || 'invalid-credential' => AuthResult.wrongPassword,
          _ => AuthResult.serviceError,
        };
      } on Object {
        return AuthResult.serviceError;
      }

      account = seed()
        ..['user'] = normalized
        ..['cred'] = await _hashPassword(password);
    } else {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          account = decoded;
        } else if (decoded is Map) {
          account = Map<String, dynamic>.from(decoded);
        } else {
          return AuthResult.storageError;
        }
      } catch (_) {
        return AuthResult.storageError;
      }

      final cred = account['cred'];
      // Refuse when no verifiable credential exists (e.g. an unsafe legacy
      // record) rather than bypassing the password check.
      if (cred is! Map) return AuthResult.storageError;

      final localPasswordMatches = await _verifyPassword(
        password,
        Map<String, dynamic>.from(cred),
      );

      if (!localPasswordMatches) {
        // Password-reset emails update Firebase Auth, not this device's local
        // credential hash. A successful cloud sign-in proves the new password;
        // use it to refresh the local hash so future/offline logins work too.
        try {
          pending = _startCloudSignIn(email: normalized, password: password);
          if (pending == null) return AuthResult.wrongPassword;
          cloudUid = await pending.timeout(cloudLinkTimeout);
          if (cloudUid == null) return AuthResult.wrongPassword;
        } on TimeoutException {
          final abandoned = pending;
          if (abandoned != null) _detachAbandonedLink(abandoned);
          return AuthResult.serviceError;
        } on FirebaseAuthException catch (e) {
          return isTemporaryAuthError(e.code)
              ? AuthResult.serviceError
              : AuthResult.wrongPassword;
        } on Object {
          return AuthResult.serviceError;
        }

        account['cred'] = await _hashPassword(password);
        sp.setString(key, jsonEncode(account));
      } else {
        // The local password is valid. Cloud sign-in remains best-effort from
        // the local credential's point of view, with bounded network waits.
        try {
          pending = _startCloudSignIn(email: normalized, password: password);
          if (pending != null) {
            cloudUid = await pending.timeout(cloudLinkTimeout);
          }
        } on TimeoutException {
          final abandoned = pending;
          if (abandoned != null) _detachAbandonedLink(abandoned);
          return AuthResult.serviceError;
        } on FirebaseAuthException catch (e) {
          final outcome = await _resolveCloudLoginFailure(
            code: e.code,
            email: normalized,
            password: password,
            account: account,
            requestCloudAccountCreation: requestCloudAccountCreation,
            requestOfflineFallback: requestOfflineFallback,
          );
          if (outcome.error != null) return outcome.error!;
          cloudUid = outcome.uid;
        } on Object {
          return AuthResult.serviceError;
        }
      }
    }

    d = account;
    d['user'] = normalized;
    if (cloudUid != null) d.remove('cloudOptOut');
    _sessionKey = key;
    _sessionProvider = 'email';
    _sessionEmail = normalized;
    _sessionUid = cloudUid;
    _writeSessionMeta();
    save();
    if (cloudUid != null) unawaited(_pullFromCloud());
    return AuthResult.success;
  }

  /// The cloud half of [login]: the test seam when one is set, Firebase's
  /// email/password sign-in otherwise, and null when no cloud is configured —
  /// the verified local account then signs in on its own. Resolves to the uid
  /// login stores on the session; the credential itself is of no use here.
  Future<String?>? _startCloudSignIn({
    required String email,
    required String password,
  }) {
    final override = cloudLinkOverride;
    if (override != null) return override(email: email, password: password);
    if (!_firebaseReady) return null;
    return _auth
        .signInWithEmailAndPassword(email: email, password: password)
        .then<String?>((credential) => credential.user?.uid);
  }

  /// Decides how a post-verification cloud sign-in failure is handled.
  /// The caller has already verified the local password before resolving
  /// an ordinary cloud sign-in failure.
  Future<({String? uid, AuthResult? error})> _resolveCloudLoginFailure({
    required String code,
    required String email,
    required String password,
    required Map<String, dynamic> account,
    required CloudConfirm? requestCloudAccountCreation,
    required CloudConfirm? requestOfflineFallback,
  }) async {
    switch (code) {
      case 'user-not-found':
      case 'invalid-credential':
        // The local password is correct, but no cloud counterpart was
        // found. Creating one silently would upload data the user never
        // consented to sync — always ask first.
        if (account['cloudOptOut'] == true ||
            requestCloudAccountCreation == null) {
          return (uid: null, error: null);
        }
        final create = await requestCloudAccountCreation(
          'No cloud account exists for this email yet. '
          'Create one to back up your data across devices?',
        );
        if (!create) {
          // Declined: local-only session; do not ask again on later logins.
          account['cloudOptOut'] = true;
          sp.setString(emailStorageKey(email), jsonEncode(account));
          return (uid: null, error: null);
        }
        // Both calls below are bounded for the reason login's own sign-in
        // is: the user has already waited one spinner out, and a wedged
        // response must not pin this one open. A timeout is reported exactly
        // like any other cloud failure, and the abandoned call is detached
        // so a late response cannot sign this device in behind the scenes.
        Future<UserCredential>? creating;
        try {
          creating = _auth.createUserWithEmailAndPassword(
            email: email,
            password: password,
          );
          final credential = await creating.timeout(cloudLinkTimeout);
          return (uid: credential.user?.uid, error: null);
        } on TimeoutException {
          final abandoned = creating;
          if (abandoned != null) {
            _detachAbandonedLink(abandoned.then<String?>((c) => c.user?.uid));
          }
          return (uid: null, error: AuthResult.serviceError);
        } on FirebaseAuthException catch (e) {
          if (e.code == 'email-already-in-use') {
            // Raced with another device that created it (possibly with a
            // different password). Adopt it only if these credentials work.
            Future<UserCredential>? adopting;
            try {
              adopting = _auth.signInWithEmailAndPassword(
                email: email,
                password: password,
              );
              final credential = await adopting.timeout(cloudLinkTimeout);
              return (uid: credential.user?.uid, error: null);
            } on TimeoutException {
              final abandoned = adopting;
              if (abandoned != null) {
                _detachAbandonedLink(
                  abandoned.then<String?>((c) => c.user?.uid),
                );
              }
              return (uid: null, error: AuthResult.serviceError);
            } on FirebaseAuthException catch (adoptionError) {
              final error = switch (adoptionError.code) {
                'wrong-password' ||
                'invalid-credential' => AuthResult.wrongPassword,
                _ => AuthResult.serviceError,
              };
              return (uid: null, error: error);
            }
          }
          if (isTemporaryAuthError(e.code)) {
            return (uid: null, error: AuthResult.serviceError);
          }
          return (uid: null, error: AuthResult.serviceError);
        }
      default:
        if (isTemporaryAuthError(code)) {
          // Temporary outage only: the user may explicitly continue with
          // the verified local account. Permanent errors are never papered
          // over with a local fallback.
          if (requestOfflineFallback == null) {
            return (uid: null, error: AuthResult.serviceError);
          }
          final offline = await requestOfflineFallback(
            'Could not reach the sign-in service. '
            'Continue with local-only data on this device?',
          );
          if (!offline) return (uid: null, error: AuthResult.serviceError);
          return (uid: null, error: null);
        }
        return (uid: null, error: AuthResult.serviceError);
    }
  }

  /// Returns the Firebase uid when the email/password pair can be linked (or
  /// an existing cloud counterpart adopted), null otherwise. Never throws.
  Future<String?> _establishCloudLink({
    required String email,
    required String password,
  }) async {
    final override = cloudLinkOverride;
    if (override != null) return override(email: email, password: password);
    if (!_firebaseReady) return null;
    try {
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      return credential.user?.uid;
    } on FirebaseAuthException catch (e) {
      if (e.code != 'email-already-in-use') return null;
      // Cloud account already exists (e.g. created on another device).
      // Adopt it when these credentials also work there; a different cloud
      // password leaves the session local-only.
      try {
        final credential = await _auth.signInWithEmailAndPassword(
          email: email,
          password: password,
        );
        return credential.user?.uid;
      } on FirebaseAuthException {
        return null;
      }
    } catch (_) {
      return null;
    }
  }

  /// Uploads an existing *local* email account to Firebase — the one case
  /// where data leaves the device without the account having been created in
  /// the cloud first. Order is deliberate:
  ///
  ///  1. the local PBKDF2 password must verify (so a wrong password can never
  ///     trigger an upload or a cloud account lookup);
  ///  2. a cloud service must be reachable;
  ///  3. the user must explicitly confirm;
  ///  4. only then is the local snapshot copied to [migrationBackupKey] and
  ///     the link attempted.
  ///
  /// Any failure after step 1 leaves the local account — data, credential,
  /// session and preferences — exactly as it was.
  Future<CloudMigrationResult> migrateLocalAccountToCloud({
    required String password,
    CloudConfirm? requestConfirmation,
  }) async {
    if (!hasActiveSession || !isEmailAccount) {
      return CloudMigrationResult.failed;
    }
    if (_sessionUid != null) return CloudMigrationResult.alreadyLinked;

    final cred = d['cred'];
    if (cred is! Map) return CloudMigrationResult.failed;
    final verified = await _verifyPassword(
      password,
      Map<String, dynamic>.from(cred),
    );
    if (!verified) return CloudMigrationResult.invalidPassword;

    if (!_linkReady || !_cloudReady) return CloudMigrationResult.unavailable;

    if (requestConfirmation != null) {
      final agreed = await requestConfirmation(
        'Back this account up to the cloud? Your profile, goals and fitness '
        'records will sync across devices. Your password and its hash never '
        'leave this device.',
      );
      if (!agreed) return CloudMigrationResult.declined;
    }

    final sessionKey = _sessionKey!;
    // Recoverable copy taken before anything cloud-side is touched.
    sp.setString(migrationBackupKey(sessionKey), jsonEncode(d));

    final uid = await _establishCloudLink(
      email: _sessionEmail!,
      password: password,
    );
    if (uid == null) return CloudMigrationResult.failed;

    _sessionUid = uid;
    d.remove('cloudOptOut');
    _writeSessionMeta();
    save();
    // Uploads the local snapshot (or reconciles with an existing document);
    // any failure stays visible through the sync status and retries later.
    await _pullFromCloud();
    return CloudMigrationResult.success;
  }

  /// Sends a Firebase password-reset email. Only cloud-linked accounts can
  /// be reset remotely; local-only accounts report [AuthResult.unknownEmail].
  Future<AuthResult> sendPasswordReset(String email) async {
    final normalized = normalizeEmail(email);
    if (normalized.isEmpty || !normalized.contains('@')) {
      return AuthResult.invalidInput;
    }
    if (!_firebaseReady) return AuthResult.serviceError;
    try {
      await _auth.sendPasswordResetEmail(email: normalized);
      return AuthResult.success;
    } on FirebaseAuthException catch (e) {
      if (e.code == 'user-not-found') return AuthResult.unknownEmail;
      return AuthResult.serviceError;
    } catch (_) {
      return AuthResult.serviceError;
    }
  }

  /// Changes the email account password after re-verifying the current one.
  /// Cloud-linked accounts update Firebase Auth first (reauth + updatePassword)
  /// and then the local hash, so a cloud failure never leaves the two out of
  /// sync in the dangerous direction. Google-managed accounts are rejected:
  /// their passwords are owned by Google. On any failure the stored
  /// credential, account data and session are left untouched.
  Future<PasswordChangeResult> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    if (_sessionProvider != 'email') {
      return PasswordChangeResult.notEmailAccount;
    }
    if (newPassword.length < 8) return PasswordChangeResult.invalidInput;

    final cred = d['cred'];
    if (cred is! Map) return PasswordChangeResult.storageError;

    final verified = await _verifyPassword(
      currentPassword,
      Map<String, dynamic>.from(cred),
    );
    if (!verified) return PasswordChangeResult.wrongCurrentPassword;

    if (_firebaseReady && _sessionUid != null) {
      final user = _auth.currentUser;
      if (user != null) {
        try {
          final firebaseCredential = EmailAuthProvider.credential(
            email: _sessionEmail ?? user.email ?? '',
            password: currentPassword,
          );
          await user.reauthenticateWithCredential(firebaseCredential);
          await user.updatePassword(newPassword);
        } on FirebaseAuthException catch (e) {
          if (e.code == 'wrong-password' || e.code == 'invalid-credential') {
            return PasswordChangeResult.wrongCurrentPassword;
          }
          return PasswordChangeResult.serviceError;
        } catch (_) {
          return PasswordChangeResult.serviceError;
        }
      }
    }

    d['cred'] = await _hashPassword(newPassword);
    save();
    return PasswordChangeResult.success;
  }

  void signOut() {
    // Flush the active copy to its account snapshot before detaching so the
    // user's fitness records are preserved.
    final key = _sessionKey;
    if (key != null && key.isNotEmpty) {
      sp.setString(key, jsonEncode(d));
    }
    sp.remove(_sessionMetaKey);
    // Stop any queued sync for the old identity first: [save] wrote the
    // snapshot above, so nothing is lost, and the epoch bump makes an
    // already-running pull abort at its next checkpoint instead of dropping
    // this user's cloud data into the next session.
    _syncDebounce?.cancel();
    _syncDebounce = null;
    _clearSessionState();
    _syncFailed = false;
    _syncError = null;
    d = seed();
    sp.setString('ft', jsonEncode(d));
    notifyListeners();
  }

  /// Like [signOut], but also detaches the Firebase session. The local
  /// sign-out always completes even if the remote one fails, so a flaky
  /// network can never trap the user in a signed-in state.
  Future<void> signOutAsync() async {
    signOut();
    if (!_firebaseReady) return;
    try {
      await _auth.signOut();
    } catch (_) {
      // Local session is already cleared; ignore remote failures.
    }
  }

  /// Fitness-record keys dropped by a reset. Everything else — identity,
  /// credential, profile details, goals and preferences — survives.
  static const _resetDroppedKeys = [
    'routines',
    'sch',
    'water',
    'steps',
    'act',
    'weights',
    'meals',
    'hist',
    'log',
    'day',
    'activeW',
  ];

  /// Wipes the fitness records of the signed-in account while keeping the
  /// account itself: identity, credential, profile (name/age/height), goals
  /// and preferences are preserved, so a reset never deletes *who* the user
  /// is or what they are aiming for. [save] then pushes the sanitized result
  /// to `users/{uid}`, so the cloud copy keeps exactly the same fields —
  /// local and reset cloud behaviour are identical by construction.
  void resetCurrentAccountData() {
    final keep = Map<String, dynamic>.from(d);
    for (final key in _resetDroppedKeys) {
      keep.remove(key);
    }
    d = seed()..addAll(keep);
    save();
  }

  // ─────────── Google authentication ───────────
  void activateGoogleAccount({
    required String uid,
    required String email,
    required String displayName,
    String? photoUrl,
  }) {
    final key = 'ft_account_$uid';
    final raw = sp.getString(key);
    Map<String, dynamic> account;
    if (raw == null) {
      account = seed();
    } else {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          account = decoded;
        } else if (decoded is Map) {
          account = Map<String, dynamic>.from(decoded);
        } else {
          account = seed();
        }
      } catch (_) {
        account = seed();
      }
    }

    final normalized = normalizeEmail(email);
    account['accountId'] = uid;
    account['authProvider'] = 'google';
    account['user'] = normalized;
    if (displayName.trim().isNotEmpty) account['name'] = displayName.trim();
    final normalizedPhotoUrl = photoUrl?.trim();
    if (normalizedPhotoUrl != null && normalizedPhotoUrl.isNotEmpty) {
      account['photoUrl'] = normalizedPhotoUrl;
    } else {
      account.remove('photoUrl');
    }

    d = account;
    _sessionKey = key;
    _sessionProvider = 'google';
    _sessionEmail = normalized;
    _sessionUid = uid;
    _writeSessionMeta();
    save();
    if (isCloudLinked) unawaited(_pullFromCloud());
  }

  // ─────────── Cloud sync (Firestore users/{uid}) ───────────
  // Document shape: users/{uid} = {'data': <sanitized snapshot>,
  //                                'updatedAt': <revision int>}
  //
  // Local SharedPreferences writes always happen first (save/saveQuiet), so
  // the device copy survives any cloud failure; sync is strictly best-effort.
  // `updatedAt` is the document revision: every push is a compare-and-set
  // against the revision the local snapshot was based on, executed inside a
  // Firestore transaction, so a stale writer can never silently clobber a
  // newer document.
  //
  // The direction of a cycle is decided by [resolveSyncDirection]:
  //   • local matches the last synced hash      → hydrate from the cloud
  //   • cloud revision newer than last edit     → hydrate (local backed up)
  //   • never synced, local has no fitness data → hydrate (empty yields)
  //   • otherwise                               → push local
  // A recoverable local backup is written *before* every overwrite:
  // [prehydrateBackupKey] when the cloud wins, [cloudConflictBackupKey] when
  // the local snapshot replaces a document, and [migrationBackupKey] before a
  // local account is uploaded for the first time. Failures never throw: they
  // mark the sync as failed (surfaced on the Profile screen) and leave local
  // storage authoritative; the next save, login or retry runs the cycle again.

  Map<String, dynamic>? _readSyncState(String uid) {
    final raw = sp.getString(_syncStateKey(uid));
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {
      // Corrupt sync state: treat as never-synced (guarded push handles it).
    }
    return null;
  }

  void _writeSyncState(
    String uid, {
    required Object? updatedAt,
    required String hash,
  }) {
    sp.setString(
      _syncStateKey(uid),
      jsonEncode({'updatedAt': updatedAt, 'hash': hash}),
    );
  }

  /// Debounced sync after a local save. Cheap saves during a workout coalesce
  /// into one cloud cycle every [syncDebounceDelay]. A full cycle runs (not a
  /// bare push) so the revision comparison is always made against a freshly
  /// read document.
  void _scheduleSync() {
    if (!_cloudReady || _sessionUid == null) return;
    _syncDebounce?.cancel();
    _syncDebounce = Timer(syncDebounceDelay, () {
      _syncDebounce = null;
      if (_sessionUid == null || !_cloudReady) return;
      unawaited(_pullFromCloud());
    });
  }

  /// Guarded push of the sanitized local snapshot. [baseUpdatedAt] is the
  /// remote revision the caller just read (null = "expect no document"). When
  /// the guard trips the incoming document is preserved in
  /// [cloudConflictBackupKey] and only then is the local snapshot written on
  /// top — last write wins, but never silently and never without a
  /// recoverable copy. This is the narrow race fallback; the direction policy
  /// itself is applied by [_runSyncCycle] before it ever calls this.
  Future<bool> _pushToCloud({required Object? baseUpdatedAt}) async {
    if (!_cloudReady || _sessionUid == null) return false;
    final uid = _sessionUid!;
    final epoch = _sessionEpoch;
    final payload = sanitizedAccountForCloud(d);
    final localHash = canonicalAccountHash(payload);
    try {
      final stamped = await _cloud.guardedWrite(uid, payload, baseUpdatedAt);
      if (_sessionEpoch != epoch) return false;
      if (stamped != null) {
        _writeSyncState(uid, updatedAt: stamped, hash: localHash);
        _markSyncSuccess();
        return true;
      }

      // Guard tripped: preserve the remote snapshot, then write local on top.
      final remote = await _cloud.read(uid);
      if (_sessionEpoch != epoch) return false;
      final remoteData = remote.data?['data'];
      if (remoteData is Map) {
        sp.setString(cloudConflictBackupKey(uid), jsonEncode(remoteData));
      }
      final now = await _cloud.forceWrite(uid, payload);
      if (_sessionEpoch != epoch) return false;
      _writeSyncState(uid, updatedAt: now, hash: localHash);
      _markSyncSuccess();
      return true;
    } catch (e) {
      if (_sessionEpoch == epoch) _markSyncFailure(e);
      return false;
    }
  }

  CloudUserDoc get _cloud => cloudUserDoc ?? FirestoreUserDoc(_firestore);

  /// Runs (or joins) one sync cycle for the current session and reports
  /// whether it succeeded. A cycle already running for the *same* identity is
  /// awaited instead of duplicated; a cycle left over from a previous identity
  /// is left to abort at its epoch checkpoints while a fresh one starts for
  /// the new session — that is what keeps one account's cloud data from ever
  /// landing in another account's local snapshot.
  Future<bool> _pullFromCloud() {
    if (!_cloudReady || _sessionUid == null) return Future<bool>.value(false);
    final epoch = _sessionEpoch;
    final inFlight = _syncInFlight;
    if (inFlight != null && _syncInFlightEpoch == epoch) return inFlight;

    final run = _runSyncCycle(epoch);
    _syncInFlight = run;
    _syncInFlightEpoch = epoch;
    _notify();
    return run.whenComplete(() {
      if (identical(_syncInFlight, run)) {
        _syncInFlight = null;
        _syncInFlightEpoch = null;
        _notify();
      }
    });
  }

  /// Public sync entry point: cancels any pending debounce and runs one cycle
  /// now. Used by the Profile retry action and by tests.
  Future<bool> syncNow() {
    _syncDebounce?.cancel();
    _syncDebounce = null;
    return _pullFromCloud();
  }

  /// A single sync cycle: read the document, decide the direction, hydrate or
  /// push. Never throws; failures are recorded through [_markSyncFailure].
  Future<bool> _runSyncCycle(int epoch) async {
    final uid = _sessionUid!;
    try {
      final state = _readSyncState(uid);
      final localHash = canonicalAccountHash(sanitizedAccountForCloud(d));
      final localDirty = state == null || state['hash'] != localHash;

      final snap = await _cloud.read(uid);
      if (_sessionEpoch != epoch || _sessionUid != uid) return false;

      if (!snap.exists) {
        return await _pushToCloud(baseUpdatedAt: state?['updatedAt']);
      }
      final remote = snap.data;
      final remoteData = remote?['data'];
      if (remoteData is! Map) {
        // Document without usable content: nothing to reconcile.
        _markSyncSuccess();
        return true;
      }
      final remoteMap = Map<String, dynamic>.from(remoteData);

      final direction = resolveSyncDirection(
        hasSyncState: state != null,
        localDirty: localDirty,
        localHasFitness: hasLocalFitnessData(d),
        remoteUpdatedAt: remote?['updatedAt'],
        lastLocalEdit: _lastLocalEdit(),
      );

      if (direction == SyncDirection.hydrate) {
        _hydrateFromCloud(remoteMap, remote?['updatedAt'], uid);
        _markSyncSuccess();
        return true;
      }

      // Local wins: keep the document we are about to replace, then push.
      sp.setString(cloudConflictBackupKey(uid), jsonEncode(remoteMap));
      return await _pushToCloud(baseUpdatedAt: remote?['updatedAt']);
    } catch (e) {
      if (_sessionEpoch == epoch) _markSyncFailure(e);
      return false;
    }
  }

  /// Applies a cloud snapshot to the active session. Incoming content is run
  /// through [sanitizedAccountForCloud] (credential fields are dropped on the
  /// way in) and device-local identity plus the PBKDF2 credential are
  /// re-asserted, so a stale or hostile document can neither swap the
  /// signed-in user nor break local password verification. When the resulting
  /// snapshot is identical to the live one the call is a no-op: the local
  /// storage and the recoverable [prehydrateBackupKey] copy written by an
  /// earlier hydrate are left exactly as they are.
  void _hydrateFromCloud(
    Map<String, dynamic> remoteMap,
    Object? remoteUpdatedAt,
    String uid,
  ) {
    final cred = d['cred'];
    final accountId = d['accountId'];
    final authProvider = d['authProvider'];
    final cloudOptOut = d['cloudOptOut'];

    // Seed first so a snapshot written by an older build cannot leave the
    // session with missing keys, then layer the (already sanitized) cloud
    // content on top.
    final incoming = sanitizedAccountForCloud(remoteMap);
    final candidate = seed()..addAll(incoming);
    candidate['user'] = _sessionEmail;
    if (cred is Map) {
      candidate['cred'] = cred;
    } else {
      candidate.remove('cred');
    }
    if (accountId != null) {
      candidate['accountId'] = accountId;
    } else {
      candidate.remove('accountId');
    }
    if (authProvider != null) {
      candidate['authProvider'] = authProvider;
    } else {
      candidate.remove('authProvider');
    }
    if (cloudOptOut != null) candidate['cloudOptOut'] = cloudOptOut;

    _writeSyncState(
      uid,
      updatedAt: remoteUpdatedAt,
      hash: canonicalAccountHash(sanitizedAccountForCloud(candidate)),
    );

    // Content already matches: an in-sync cycle must not disturb the live
    // snapshot or clobber the backup of the data it replaced.
    if (_canonicalJson(candidate) == _canonicalJson(d)) return;

    sp.setString(prehydrateBackupKey(uid), jsonEncode(d));
    d = candidate;
    final payload = jsonEncode(d);
    sp.setString('ft', payload);
    final accountKey = _sessionKey;
    if (accountKey != null && accountKey.isNotEmpty) {
      sp.setString(accountKey, payload);
    }
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    _syncDebounce?.cancel();
    _syncDebounce = null;
    super.dispose();
  }

  // Daily reset: archive yesterday's food/steps/activity and start fresh.
  // History is preserved: archived days are appended to 'log' before the
  // counters reset, and 'hist' (workout history) is never touched here.
  // The `d['day'] != n` guard makes repeated calls for the same date no-ops,
  // so callers may poll this safely (see Shell's minute timer). Retention
  // runs inside that same guard: entries only become trimmable when the
  // date advances, so the poll does no list walks between rollovers.
  void roll() {
    final n = today();
    if (d['day'] != n) {
      if (meals.isNotEmpty || acts.isNotEmpty || steps > 0) {
        final log = d['log'];
        (log is List ? log : (d['log'] = <dynamic>[])).add({
          'd': d['day'],
          'meals': d['meals'],
          'act': d['act'],
          'steps': d['steps'],
        });
      }
      d['meals'] = [];
      d['act'] = [];
      d['steps'] = 0;
      d['day'] = n;
      save();
      applyRetention();
    }
  }

  // ─────────── Data retention (documented policy) ───────────
  // 'water', 'log' and 'hist' grow forever without bounds. This conservative
  // policy runs after every rollover and is the only place that trims them:
  //
  //   • water — keep the newest kWaterRetentionDays dated entries.
  //   • log   — keep the newest kLogRetentionDays archived day entries.
  //   • hist  — keep workouts from the last kHistRetentionDays days.
  //
  // Entries with a missing or unparseable date are always kept: data is only
  // removed when it is provably older than its bound. Nothing else in the
  // snapshot is modified, so account isolation and corrupt-snapshot
  // recovery are unaffected. The bounds are deliberately loose (≈1 year)
  // so streak/weekly/4-week aggregations are never impacted.
  static const kWaterRetentionDays = 90;
  static const kLogRetentionDays = 365;
  static const kHistRetentionDays = 365;

  static bool _olderThan(Object? day, int days) {
    if (day is! String || day.isEmpty) return false;
    return day.compareTo(daysAgo(days)) < 0;
  }

  /// Applies the retention policy above. Safe to call repeatedly; persists
  /// only when something was actually removed.
  void applyRetention() {
    var changed = false;

    final water = d['water'];
    if (water is List && water.isNotEmpty) {
      final kept = water
          .where(
            (w) => !_olderThan(w is Map ? w['d'] : null, kWaterRetentionDays),
          )
          .toList();
      if (kept.length != water.length) {
        d['water'] = kept;
        changed = true;
      }
    }

    final log = d['log'];
    if (log is List && log.length > kLogRetentionDays) {
      d['log'] = log.sublist(log.length - kLogRetentionDays);
      changed = true;
    }

    final hist = d['hist'];
    if (hist is List && hist.isNotEmpty) {
      final kept = hist
          .where(
            (h) => !_olderThan(h is Map ? h['d'] : null, kHistRetentionDays),
          )
          .toList();
      if (kept.length != hist.length) {
        d['hist'] = kept;
        changed = true;
      }
    }

    if (changed) save();
  }

  List get routines => d['routines'] is List ? d['routines'] as List : const [];
  List get sch => d['sch'] is List ? d['sch'] as List : const [];
  List get meals => d['meals'] is List ? d['meals'] as List : const [];
  List get acts => d['act'] is List ? d['act'] as List : const [];
  List get hist => d['hist'] is List ? d['hist'] as List : const [];
  int get steps => _safeInt(d['steps'], fallback: 0);
  Map get goal => d['goal'] is Map ? d['goal'] as Map : <String, dynamic>{};
  Map<String, dynamic> get nutritionGoals {
    const defaults = <String, dynamic>{
      'calories': 2100,
      'protein': 140,
      'carbs': 220,
      'fat': 65,
    };
    final saved = d['nutritionGoals'];
    final goals = saved is Map
        ? Map<String, dynamic>.from(saved)
        : <String, dynamic>{};
    for (final entry in defaults.entries) {
      final v = goals[entry.key];
      // Fill missing keys and replace zero, negative or non-numeric values
      // with the default, so a malformed snapshot can never feed a
      // division-by-zero into the UI. Valid stored goals are left untouched.
      if (v is! num || v <= 0) {
        goals[entry.key] = entry.value;
      }
    }
    d['nutritionGoals'] = goals;
    return goals;
  }

  /// Daily water/step targets. Missing keys (older snapshots) are filled
  /// with the previous hardcoded defaults, so no migration is required.
  Map<String, dynamic> get activityGoals {
    const defaults = <String, dynamic>{'waterMl': 2500, 'steps': 8000};
    final saved = d['activityGoals'];
    final goals = saved is Map
        ? Map<String, dynamic>.from(saved)
        : <String, dynamic>{};
    for (final entry in defaults.entries) {
      final v = goals[entry.key];
      final parsed = _safeDouble(v, fallback: entry.value.toDouble());
      if (!parsed.isFinite || parsed <= 0) {
        goals[entry.key] = entry.value;
      } else {
        goals[entry.key] = parsed;
      }
    }
    d['activityGoals'] = goals;
    return goals;
  }

  int get waterGoalMl =>
      _safeInt(activityGoals['waterMl'], fallback: 2500).clamp(500, 10000);
  int get stepGoal =>
      _safeInt(activityGoals['steps'], fallback: 8000).clamp(1000, 50000);

  bool on(String k) => d[k] == true;
  void toggle(String k) {
    d[k] = !on(k);
    save();
  }

  Map? routine(dynamic id) {
    for (final r in routines) {
      if (r['id'] == id) return r;
    }
    return null;
  }

  Map? next() {
    final l =
        sch.where((s) => (s['d'] as String).compareTo(today()) >= 0).toList()
          ..sort(
            (a, b) => ('${a['d']}${a['t']}').compareTo('${b['d']}${b['t']}'),
          );
    return l.isEmpty ? null : l.first;
  }

  int water() => (d['water'] is List ? d['water'] as List : const [])
      .where((w) => w is Map && w['d'] == today())
      .fold(0, (a, w) => a + _safeInt((w as Map)['ml'], fallback: 0));
  int kcal() => meals.fold(
    0,
    (a, m) => a + _safeInt((m is Map ? m['k'] : null), fallback: 0),
  );
  int macro(String k) => meals.fold(
    0,
    (a, m) => a + _safeInt((m is Map ? m[k] : null), fallback: 0),
  );
  int actMin() => acts.fold(
    0,
    (a, m) => a + _safeInt((m is Map ? m['min'] : null), fallback: 0),
  );
  int actKc() => acts.fold(
    0,
    (a, m) => a + _safeInt((m is Map ? m['kc'] : null), fallback: 0),
  );

  double lastW() {
    final w =
        (d['weights'] is List ? d['weights'] as List : const [])
            .whereType<List>()
            .toList()
          ..sort(
            (a, b) => (a.isNotEmpty && a[0] is String ? a[0] as String : '')
                .compareTo(
                  b.isNotEmpty && b[0] is String ? b[0] as String : '',
                ),
          );
    if (w.isEmpty) return 0;
    final last = w.last;
    if (last.length < 2) return 0;
    return _safeDouble(last[1], fallback: 0.0);
  }

  /// One field of the weight-goal map, decoded tolerantly. Legacy or corrupt
  /// snapshots may hold nulls, strings, or simply lack the key; anything
  /// non-numeric reads as 0 (unset) instead of throwing a cast error.
  double goalField(String key) => _safeDouble(goal[key], fallback: 0.0);

  /// Weekly workout target, decoded tolerantly and clamped to 1–7. Mirrors
  /// the pattern WeightScreen already used privately: a missing or
  /// non-numeric `wk` falls back to the default of 3, and a malformed zero
  /// clamps up to 1, so it can never feed a division or a cast error.
  int get weeklyWorkoutGoal {
    final v = goal['wk'];
    final parsed = _safeInt(v, fallback: 3);
    if (parsed <= 0) return 1;
    return parsed.clamp(1, 7);
  }

  double goalProgress() {
    final start = goalField('sw');
    final target = goalField('w');
    final current = WeightEstimator.calculate(d).currentWeightKg;
    if (start <= 0 || target <= 0 || start == target || current <= 0) return 0;
    return ((start - current) / (start - target)).clamp(0.0, 1.0);
  }

  int streak() {
    final ds = hist.map((h) => h['d']).toSet();
    int n = 0, i = ds.contains(today()) ? 0 : 1;
    while (ds.contains(daysAgo(i))) {
      n++;
      i++;
    }
    return n;
  }

  int wkCount(int o) {
    final a = daysAgo(o * 7 + 6), b = daysAgo(o * 7);
    return hist
        .where(
          (h) => '${h['d']}'.compareTo(a) >= 0 && '${h['d']}'.compareTo(b) <= 0,
        )
        .length;
  }

  String wt(double kg) => on('lb')
      ? '${(kg * 2.2046).toStringAsFixed(1)} lb'
      : '${kg.toStringAsFixed(1)} kg';

  /// Formats an integer with thousands separators (e.g. 8000 → '8,000').
  String withThousands(int n) => n.toString().replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (m) => ',',
  );

  List<List<String>> notes() {
    final l = <List<String>>[];
    if (on('wr')) {
      // One reminder per workout scheduled today, in time order. Derived
      // live from the schedule, so edited or deleted entries can never
      // leave a stale or duplicate reminder behind.
      final t = sch.where((s) => s['d'] == today()).toList()
        ..sort((a, b) => (a['t'] as String).compareTo(b['t'] as String));
      for (final s in t) {
        l.add([
          '🏋',
          'Workout at ${s['t']}',
          '${routine(s['r'])?['name'] ?? 'Workout'}',
        ]);
      }
    }
    if (on('wtr') && water() < waterGoalMl) {
      l.add([
        '💧',
        'Stay hydrated',
        '${(water() / 1000).toStringAsFixed(1)} of ${(waterGoalMl / 1000).toStringAsFixed(1)} L so far',
      ]);
    }
    if (on('mr') && meals.length < 3) {
      l.add(['🍴', 'Meal reminder', '${meals.length} of 3 meals logged today']);
    }
    if (steps < stepGoal) {
      l.add(['👣', 'Keep moving', '${stepGoal - steps} steps to your goal']);
    }
    if (streak() > 0) {
      l.add(['🔥', '${streak()}-day streak', 'Keep showing up.']);
    }
    return l;
  }
}

final store = Store();
