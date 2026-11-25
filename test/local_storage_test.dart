import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fittract/store/local_database.dart';
import 'package:fittract/store/store.dart';

void main() {
  setUp(() {
    LocalDatabase.useSqliteForTesting = true;
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(() => LocalDatabase.useSqliteForTesting = false);

  test(
    'Google account retains a local copy when cloud sync is unavailable',
    () async {
      final store = Store();
      await store.init();

      store.activateGoogleAccount(
        uid: 'google-user',
        email: 'user@example.com',
        displayName: 'FitTrack User',
      );
      store.meals.add({'n': 'Local meal', 'k': 420});
      store.save();

      final saved = await store.readStoredAccount('ft_account_google-user');
      expect((saved?['meals'] as List).single['n'], 'Local meal');
      expect(store.sp.getString('ft_sync_state_google-user'), isNull);

      final reopened = Store();
      await reopened.init();
      expect(reopened.hasActiveSession, isTrue);
      expect(reopened.meals.single['n'], 'Local meal');
    },
  );

  test('migrates existing SharedPreferences records to SQLite', () async {
    const key = 'ft_account_migrate-user';
    final legacy = Store().seed()
      ..['user'] = 'migrate@example.com'
      ..['accountId'] = 'migrate-user'
      ..['authProvider'] = 'google'
      ..['weights'] = [
        ['2026-11-18', 72.5],
      ]
      ..['water'] = [
        {'d': '2026-11-18', 'ml': 350},
      ]
      ..['meals'] = [
        {'n': 'Legacy meal', 'k': 420},
      ];
    SharedPreferences.setMockInitialValues({
      key: jsonEncode(legacy),
      'ft_session_meta': jsonEncode({
        'provider': 'google',
        'key': key,
        'email': 'migrate@example.com',
        'displayName': 'Migrated User',
        'uid': 'migrate-user',
      }),
    });

    final migrated = Store();
    await migrated.init(rollDay: false);

    expect(migrated.d['weights'], legacy['weights']);
    expect(migrated.d['water'], legacy['water']);
    expect(migrated.meals.single['n'], 'Legacy meal');
    expect(migrated.sp.getString(key), isNull);
    expect((await migrated.readStoredAccount(key))?['nutritionGoals'], {
      'calories': 2100,
      'protein': 140,
      'carbs': 220,
      'fat': 65,
    });

    final restarted = Store();
    await restarted.init(rollDay: false);
    expect(restarted.d['weights'], legacy['weights']);
    expect(restarted.d['water'], legacy['water']);
    expect(restarted.meals.single['n'], 'Legacy meal');
  });

  test('record CRUD operations persist through an app restart', () async {
    final store = Store();
    await store.init(rollDay: false);
    store.activateGoogleAccount(
      uid: 'crud-user',
      email: 'crud@example.com',
      displayName: 'CRUD User',
    );

    await store.createRecord('water', {'d': '2026-11-19', 'ml': 250});
    await store.createRecord('water', {'d': '2026-11-19', 'ml': 500});
    await store.updateRecord('water', 0, {'d': '2026-11-19', 'ml': 300});
    expect((await store.readRecords('water')).first['ml'], 300);
    await store.deleteRecord('water', 1);
    expect(await store.readRecords('water'), [
      {'d': '2026-11-19', 'ml': 300},
    ]);

    final restarted = Store();
    await restarted.init(rollDay: false);
    expect(restarted.d['water'], [
      {'d': '2026-11-19', 'ml': 300},
    ]);
  });
}
