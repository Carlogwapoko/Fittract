import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fittract/store/store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('rollover and restart preserve every dated record', () async {
    SharedPreferences.setMockInitialValues({});
    await store.init();
    store.activateGoogleAccount(
      uid: 'history-account',
      email: 'history@example.com',
      displayName: 'History User',
    );

    final oldWater = {'d': daysAgo(500), 'ml': 500};
    final oldWorkout = {'d': daysAgo(800), 'n': 'Old workout'};
    final oldDays = <dynamic>[
      for (var i = 0; i < 400; i++) {'d': 'archive-$i'},
    ];
    store.d['water'] = [oldWater];
    store.d['hist'] = [oldWorkout];
    store.d['log'] = [...oldDays];
    store.d['day'] = daysAgo(1);
    store.d['steps'] = 250;

    store.roll();

    expect(store.d['water'], [oldWater]);
    expect(store.d['hist'], [oldWorkout]);
    expect(store.d['log'], hasLength(401));
    expect((store.d['log'] as List).first, oldDays.first);
    expect((store.d['log'] as List).last['steps'], 250);

    final restartedStore = Store();
    await restartedStore.init();
    addTearDown(restartedStore.dispose);

    expect(restartedStore.d['water'], [oldWater]);
    expect(restartedStore.d['hist'], [oldWorkout]);
    expect(restartedStore.d['log'], store.d['log']);
  });

  test(
    'reset clears the daily distance along with other activity data',
    () async {
      SharedPreferences.setMockInitialValues({});
      final resetStore = Store();
      await resetStore.init();
      resetStore.d['distanceMeters'] = 4200.0;
      resetStore.resetCurrentAccountData();

      expect(resetStore.d['distanceMeters'], 0.0);
      resetStore.dispose();
    },
  );
}
