import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fittract/store/store.dart';

/// Exact current retention policy, documented from `Store.applyRetention()`
/// (lib/store/store.dart:1827-1889) and tested here without changing it:
///
///  * `water` — date-based: an entry is removed only when its `d` value is a
///    non-empty string that compares strictly before `daysAgo(90)`
///    (lexicographic `yyyy-MM-dd` comparison). Exactly at the cutoff is kept.
///  * `log` — position-based, never date-based: only when longer than
///    `kLogRetentionDays` (365) it keeps the LAST 365 entries; a list of 365
///    or fewer is never touched regardless of entry dates.
///  * `hist` — date-based like `water`, cutoff `daysAgo(365)`.
///  * Entries with a missing, empty, or unparseable-looking `d` and non-map
///    items are always kept; non-list buckets are left untouched.
///  * Nothing else in the snapshot changes; `save()` runs only if something
///    was removed.
///
/// Dates are built with the store's own `daysAgo()`/`isoOf()` helpers, the
/// same clock the implementation uses, so expectations are deterministic:
/// no sleeps and no wall-clock waits (both sides share one `DateTime.now()`).
Future<void> freshStore() async {
  SharedPreferences.setMockInitialValues({});
  await store.init();
}

void main() {
  group('water — date-based 90-day window', () {
    test('keeps inside the window, the boundary day, and today', () async {
      await freshStore();
      store.d['water'] = [
        {'d': daysAgo(0), 'ml': 100},
        {'d': daysAgo(30), 'ml': 100},
        {'d': daysAgo(89), 'ml': 100},
        // Exactly at the cutoff: only strictly older entries go.
        {'d': daysAgo(90), 'ml': 100},
      ];

      store.applyRetention();

      expect(
        (store.d['water'] as List).map((w) => w['d']),
        [daysAgo(0), daysAgo(30), daysAgo(89), daysAgo(90)],
      );
    });

    test('removes entries strictly older than the window', () async {
      await freshStore();
      store.d['water'] = [
        {'d': daysAgo(91), 'ml': 100},
        {'d': daysAgo(200), 'ml': 100},
        {'d': daysAgo(400), 'ml': 100},
        {'d': daysAgo(90), 'ml': 100},
      ];

      store.applyRetention();

      expect(
        (store.d['water'] as List).map((w) => w['d']),
        [daysAgo(90)],
      );
    });

    test('keeps malformed and non-map entries that cannot be proven old', () async {
      await freshStore();
      final entries = <dynamic>[
        {'d': ''},
        {'d': null},
        {'ml': 500}, // no 'd' key at all
        {'d': 'not-a-date'},
        'not-a-map',
      ];
      store.d['water'] = [...entries];

      store.applyRetention();

      expect(store.d['water'], entries);
    });
  });

  group('hist — date-based 365-day window', () {
    test('keeps today through the cutoff and removes anything older', () async {
      await freshStore();
      store.d['hist'] = [
        {'d': daysAgo(0), 'n': 'newest'},
        {'d': daysAgo(364), 'n': 'inside'},
        {'d': daysAgo(365), 'n': 'boundary'},
        {'d': daysAgo(366), 'n': 'just-outside'},
        {'d': daysAgo(800), 'n': 'ancient'},
      ];

      store.applyRetention();

      expect(
        (store.d['hist'] as List).map((h) => h['n']),
        ['newest', 'inside', 'boundary'],
      );
    });
  });

  group('log — position-based 365-entry cap', () {
    test('a full-length list keeps its last 365 entries regardless of dates', () async {
      await freshStore();
      store.d['log'] = [
        for (var i = 0; i < 366; i++) {'d': 'entry-$i'},
      ];

      store.applyRetention();

      final log = store.d['log'] as List;
      expect(log.length, 365);
      // The oldest position is dropped; the newest 365 survive in order.
      expect(log.first['d'], 'entry-1');
      expect(log.last['d'], 'entry-365');
    });

    test('a list of 365 or fewer is never touched, even if ancient', () async {
      await freshStore();
      final ancient = [
        for (var i = 0; i < 365; i++) {'d': daysAgo(999)},
      ];
      store.d['log'] = [...ancient];

      store.applyRetention();

      expect(store.d['log'], ancient);
    });

    test('a non-list log bucket is left untouched', () async {
      await freshStore();
      store.d['log'] = {'unexpected': true};

      store.applyRetention();

      expect(store.d['log'], {'unexpected': true});
    });
  });

  group('no-op cases', () {
    test('empty buckets pass through unchanged', () async {
      await freshStore();
      store.d['water'] = [];
      store.d['hist'] = [];
      store.d['log'] = [];

      expect(() => store.applyRetention(), returnsNormally);
      expect(store.d['water'], isEmpty);
      expect(store.d['hist'], isEmpty);
      expect(store.d['log'], isEmpty);
    });

    test('non-list water and hist buckets are left untouched', () async {
      await freshStore();
      store.d['water'] = {'unexpected': true};
      store.d['hist'] = 'not-a-list';

      expect(() => store.applyRetention(), returnsNormally);
      expect(store.d['water'], {'unexpected': true});
      expect(store.d['hist'], 'not-a-list');
    });

    test('buckets with only in-window entries keep every record', () async {
      await freshStore();
      final water = [
        {'d': daysAgo(0), 'ml': 250},
        {'d': daysAgo(1), 'ml': 500},
      ];
      final hist = [
        {'d': daysAgo(10), 'n': 'recent'},
      ];
      final log = [
        {'d': daysAgo(5)},
      ];
      store.d['water'] = [...water];
      store.d['hist'] = [...hist];
      store.d['log'] = [...log];

      store.applyRetention();

      expect(store.d['water'], water);
      expect(store.d['hist'], hist);
      expect(store.d['log'], log);
    });
  });
}
