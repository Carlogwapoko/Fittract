import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fittract/store/store.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    pbkdf2IterationsOverride = 1000;
  });

  tearDown(() {
    pbkdf2IterationsOverride = 0;
  });

  Future<Store> freshStore() async {
    final result = Store();
    await result.init();
    return result;
  }

  test(
    'registration stores a hashed local account without signing in',
    () async {
      final store = await freshStore();

      expect(
        await store.register(
          name: 'Ada Lovelace',
          email: '  Ada@Example.COM ',
          password: 'correct horse',
        ),
        AuthResult.success,
      );
      expect(store.hasActiveSession, isFalse);

      final account =
          (await store.readStoredAccount(
            emailStorageKey(normalizeEmail('ada@example.com')),
          ))!;
      expect(jsonEncode(account), isNot(contains('correct horse')));
      expect(account['user'], 'ada@example.com');
      expect(account['name'], 'Ada Lovelace');
      expect(account['cred']['alg'], 'pbkdf2-hmac-sha256');
    },
  );

  test(
    'local login persists records and reloads them on the same device',
    () async {
      final store = await freshStore();
      await store.register(
        name: 'Ada',
        email: 'ada@example.com',
        password: 'pass1234',
      );

      expect(
        await store.login(email: 'ada@example.com', password: 'wrong-password'),
        AuthResult.wrongPassword,
      );
      expect(
        await store.login(email: 'ada@example.com', password: 'pass1234'),
        AuthResult.success,
      );

      store.meals.add({'n': 'Oatmeal', 'k': 320});
      store.save();
      expect(
        store.sp.getKeys().where((key) => key.startsWith('ft_sync_state_')),
        isEmpty,
      );
      store.signOut();

      final restarted = await freshStore();
      expect(
        await restarted.login(email: 'ada@example.com', password: 'pass1234'),
        AuthResult.success,
      );
      expect(restarted.meals.single['n'], 'Oatmeal');
    },
  );

  test('logout and restart preserve current weight and weight goals', () async {
    final store = await freshStore();
    await store.register(
      name: 'Ada',
      email: 'ada@example.com',
      password: 'pass1234',
    );
    expect(
      await store.login(email: 'ada@example.com', password: 'pass1234'),
      AuthResult.success,
    );

    store.ensureGoal()
      ..['w'] = 64.0
      ..['sw'] = 72.5
      ..['d'] = '2027-01-15';
    store.d['weightAnchorDate'] = '2026-11-18';
    store.d['weights'] = [
      ['2026-11-18', 72.5],
      ['2026-11-19', 71.8],
    ];
    store.save();
    await store.signOutAsync();

    final restarted = await freshStore();
    expect(
      await restarted.login(email: 'ada@example.com', password: 'pass1234'),
      AuthResult.success,
    );
    expect(restarted.goal['w'], 64.0);
    expect(restarted.goal['sw'], 72.5);
    expect(restarted.goal['d'], '2027-01-15');
    expect(restarted.d['weightAnchorDate'], '2026-11-18');
    expect(restarted.d['weights'], [
      ['2026-11-18', 72.5],
      ['2026-11-19', 71.8],
    ]);
  });

  test('email accounts keep separate local fitness records', () async {
    final store = await freshStore();
    await store.register(
      name: 'Ada',
      email: 'ada@example.com',
      password: 'pass1234',
    );
    await store.register(
      name: 'Grace',
      email: 'grace@example.com',
      password: 'pass5678',
    );

    await store.login(email: 'ada@example.com', password: 'pass1234');
    store.meals.add({'n': 'Lunch'});
    store.save();
    store.signOut();

    await store.login(email: 'grace@example.com', password: 'pass5678');
    expect(store.meals, isEmpty);
    store.meals.add({'n': 'Dinner'});
    store.save();
    store.signOut();

    await store.login(email: 'ada@example.com', password: 'pass1234');
    expect(store.meals.single['n'], 'Lunch');
  });

  test('password change is local and requires the current password', () async {
    final store = await freshStore();
    await store.register(
      name: 'Ada',
      email: 'ada@example.com',
      password: 'pass1234',
    );
    await store.login(email: 'ada@example.com', password: 'pass1234');

    expect(
      await store.changePassword(
        currentPassword: 'wrong-password',
        newPassword: 'newpass123',
      ),
      PasswordChangeResult.wrongCurrentPassword,
    );
    expect(
      await store.changePassword(
        currentPassword: 'pass1234',
        newPassword: 'newpass123',
      ),
      PasswordChangeResult.success,
    );
    store.signOut();
    expect(
      await store.login(email: 'ada@example.com', password: 'newpass123'),
      AuthResult.success,
    );
  });
}
