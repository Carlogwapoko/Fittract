import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

abstract class LocalDatabase {
  @visibleForTesting
  static bool useSqliteForTesting = false;

  factory LocalDatabase(SharedPreferences preferences) {
    if (Platform.environment['FLUTTER_TEST'] == 'true' &&
        !useSqliteForTesting) {
      return _MemoryLocalDatabase(preferences);
    }
    return _SqliteLocalDatabase(preferences);
  }

  bool get writesAreSynchronous;
  Future<void> open();
  Future<bool> containsAccount(String key);
  Future<Map<String, dynamic>?> readAccount(String key);
  Future<Map<String, Map<String, dynamic>>> readAllAccounts();
  Future<bool> importAccountIfAbsent(String key, Map<String, dynamic> account);
  Future<void> writeAccount(String key, Map<String, dynamic> account);
  void writeAccountSynchronously(String key, Map<String, dynamic> account);
  Future<void> deleteAccount(String key);
  Future<List<dynamic>> readRecords(String key, String collection);
  Future<int> createRecord(String key, String collection, dynamic record);
  Future<void> updateRecord(
    String key,
    String collection,
    int index,
    dynamic record,
  );
  Future<void> deleteRecord(String key, String collection, int index);
}

class _SqliteLocalDatabase implements LocalDatabase {
  _SqliteLocalDatabase(this._preferences);

  static const _databaseName = 'fittract.db';
  static const _databaseVersion = 1;

  final SharedPreferences _preferences;
  sqflite.Database? _database;
  sqflite.DatabaseFactory? _factory;
  String? _databasePath;

  @override
  bool get writesAreSynchronous => false;

  @override
  Future<void> open() async {
    if (_database != null) return;

    final useFfi =
        Platform.isWindows ||
        Platform.isLinux ||
        Platform.environment['FLUTTER_TEST'] == 'true';
    final sqflite.DatabaseFactory factory;
    if (useFfi) {
      sqfliteFfiInit();
      factory = Platform.environment['FLUTTER_TEST'] == 'true'
          ? databaseFactoryFfiNoIsolate
          : databaseFactoryFfi;
    } else {
      factory = sqflite.databaseFactory;
    }

    final databaseDirectory =
        useFfi && Platform.environment['FLUTTER_TEST'] == 'true'
        ? Directory.systemTemp.path
        : await factory.getDatabasesPath();
    final name = useFfi && Platform.environment['FLUTTER_TEST'] == 'true'
        ? 'fittract_test_${identityHashCode(_preferences)}.db'
        : _databaseName;
    _factory = factory;
    _databasePath = path.join(databaseDirectory, name);
    try {
      await _openDatabase();
    } catch (error, stackTrace) {
      debugPrint('SQLite open failed; retrying: $error\n$stackTrace');
      await _closeDatabase();
      try {
        await _openDatabase();
      } catch (retryError, retryStackTrace) {
        await _closeDatabase();
        if (!_isDatabaseCorruption(error) &&
            !_isDatabaseCorruption(retryError)) {
          Error.throwWithStackTrace(retryError, retryStackTrace);
        }

        debugPrint('Corrupted SQLite database detected; backing it up.');
        await _backupAndRemoveDatabase();
        await _openDatabase();
      }
    }
  }

  Future<void> _openDatabase() async {
    final factory = _factory;
    final databasePath = _databasePath;
    if (factory == null || databasePath == null) {
      throw StateError('SQLite has not been configured.');
    }

    final database = await factory.openDatabase(
      databasePath,
      options: sqflite.OpenDatabaseOptions(
        version: _databaseVersion,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE accounts (
              account_key TEXT PRIMARY KEY NOT NULL,
              updated_at INTEGER NOT NULL
            )
          ''');
          await db.execute('''
            CREATE TABLE account_fields (
              account_key TEXT NOT NULL,
              field_key TEXT NOT NULL,
              value_json TEXT NOT NULL,
              PRIMARY KEY (account_key, field_key),
              FOREIGN KEY (account_key) REFERENCES accounts(account_key)
            )
          ''');
          await db.execute('''
            CREATE TABLE account_collections (
              account_key TEXT NOT NULL,
              collection_key TEXT NOT NULL,
              PRIMARY KEY (account_key, collection_key),
              FOREIGN KEY (account_key) REFERENCES accounts(account_key)
            )
          ''');
          await db.execute('''
            CREATE TABLE account_records (
              account_key TEXT NOT NULL,
              collection_key TEXT NOT NULL,
              position INTEGER NOT NULL,
              value_json TEXT NOT NULL,
              PRIMARY KEY (account_key, collection_key, position),
              FOREIGN KEY (account_key, collection_key)
                REFERENCES account_collections(account_key, collection_key)
            )
          ''');
          await db.execute('''
            CREATE INDEX account_records_lookup
            ON account_records(account_key, collection_key, position)
          ''');
        },
      ),
    );
    _database = database;
    final result = await database.rawQuery('PRAGMA quick_check(1)');
    if (result.length != 1 || result.first.values.first != 'ok') {
      throw StateError('SQLite integrity check failed: $result');
    }
  }

  Future<void> _closeDatabase() async {
    final database = _database;
    _database = null;
    if (database != null) await database.close();
  }

  static bool _isDatabaseCorruption(Object error) {
    final message = error.toString().toLowerCase();
    return message.contains('corrupt') ||
        message.contains('malformed') ||
        message.contains('not a database') ||
        message.contains('disk image') ||
        message.contains('integrity check failed');
  }

  Future<void> _backupAndRemoveDatabase() async {
    await _closeDatabase();

    final databasePath = _databasePath;
    if (databasePath == null) {
      throw StateError('Cannot back up SQLite before its path is configured.');
    }

    final suffix = DateTime.now().toUtc().microsecondsSinceEpoch.toString();
    const sidecars = ['', '-wal', '-shm', '-journal'];
    final existingFiles = <File>[];
    for (final sidecar in sidecars) {
      final file = File('$databasePath$sidecar');
      if (await file.exists()) existingFiles.add(file);
    }

    for (final file in existingFiles) {
      final fileSuffix = file.path.substring(databasePath.length);
      await file.copy('$databasePath.corrupt-$suffix$fileSuffix');
    }
    for (final file in existingFiles) {
      await file.delete();
    }
  }

  sqflite.Database get _db {
    final db = _database;
    if (db == null) throw StateError('The local database has not been opened.');
    return db;
  }

  @override
  Future<bool> containsAccount(String key) async => (await _db.query(
    'accounts',
    columns: const ['account_key'],
    where: 'account_key = ?',
    whereArgs: [key],
    limit: 1,
  )).isNotEmpty;

  @override
  Future<Map<String, dynamic>?> readAccount(String key) async {
    final rows = await _db.query(
      'accounts',
      columns: const ['account_key'],
      where: 'account_key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (rows.isEmpty) return null;

    final result = <String, dynamic>{};
    final fields = await _db.query(
      'account_fields',
      columns: const ['field_key', 'value_json'],
      where: 'account_key = ?',
      whereArgs: [key],
    );
    for (final field in fields) {
      result[field['field_key']! as String] = jsonDecode(
        field['value_json']! as String,
      );
    }

    final collections = await _db.query(
      'account_collections',
      columns: const ['collection_key'],
      where: 'account_key = ?',
      whereArgs: [key],
    );
    for (final row in collections) {
      final collection = row['collection_key']! as String;
      result[collection] = await readRecords(key, collection);
    }
    return result;
  }

  @override
  Future<Map<String, Map<String, dynamic>>> readAllAccounts() async {
    try {
      return await _readAllAccounts();
    } catch (error, stackTrace) {
      if (!_isDatabaseCorruption(error)) {
        Error.throwWithStackTrace(error, stackTrace);
      }
      debugPrint('SQLite corruption detected while reading accounts: $error');
      await _backupAndRemoveDatabase();
      await _openDatabase();
      return _readAllAccounts();
    }
  }

  Future<Map<String, Map<String, dynamic>>> _readAllAccounts() async {
    final rows = await _db.query(
      'accounts',
      columns: const ['account_key'],
      orderBy: 'account_key',
    );
    final accounts = <String, Map<String, dynamic>>{};
    for (final row in rows) {
      final key = row['account_key']! as String;
      final account = await readAccount(key);
      if (account != null) accounts[key] = account;
    }
    return accounts;
  }

  @override
  Future<bool> importAccountIfAbsent(
    String key,
    Map<String, dynamic> account,
  ) async => _db.transaction((transaction) async {
    final existing = await transaction.query(
      'accounts',
      columns: const ['account_key'],
      where: 'account_key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (existing.isNotEmpty) return false;
    await _writeAccount(transaction, key, account);
    return true;
  });

  @override
  Future<void> writeAccount(String key, Map<String, dynamic> account) => _db
      .transaction((transaction) => _writeAccount(transaction, key, account));

  @override
  void writeAccountSynchronously(String key, Map<String, dynamic> account) {
    throw UnsupportedError('SQLite writes are asynchronous.');
  }

  Future<void> _writeAccount(
    sqflite.Transaction transaction,
    String key,
    Map<String, dynamic> account,
  ) async {
    await transaction.insert('accounts', {
      'account_key': key,
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: sqflite.ConflictAlgorithm.replace);
    await transaction.delete(
      'account_fields',
      where: 'account_key = ?',
      whereArgs: [key],
    );
    await transaction.delete(
      'account_records',
      where: 'account_key = ?',
      whereArgs: [key],
    );
    await transaction.delete(
      'account_collections',
      where: 'account_key = ?',
      whereArgs: [key],
    );

    for (final entry in account.entries) {
      if (entry.value is List) {
        await transaction.insert('account_collections', {
          'account_key': key,
          'collection_key': entry.key,
        });
        final values = entry.value as List;
        for (var position = 0; position < values.length; position++) {
          await transaction.insert('account_records', {
            'account_key': key,
            'collection_key': entry.key,
            'position': position,
            'value_json': jsonEncode(values[position]),
          });
        }
      } else {
        await transaction.insert('account_fields', {
          'account_key': key,
          'field_key': entry.key,
          'value_json': jsonEncode(entry.value),
        });
      }
    }
  }

  @override
  Future<void> deleteAccount(String key) async {
    await _db.transaction((transaction) async {
      await transaction.delete(
        'account_records',
        where: 'account_key = ?',
        whereArgs: [key],
      );
      await transaction.delete(
        'account_collections',
        where: 'account_key = ?',
        whereArgs: [key],
      );
      await transaction.delete(
        'account_fields',
        where: 'account_key = ?',
        whereArgs: [key],
      );
      await transaction.delete(
        'accounts',
        where: 'account_key = ?',
        whereArgs: [key],
      );
    });
  }

  @override
  Future<List<dynamic>> readRecords(String key, String collection) async {
    final rows = await _db.query(
      'account_records',
      columns: const ['value_json'],
      where: 'account_key = ? AND collection_key = ?',
      whereArgs: [key, collection],
      orderBy: 'position',
    );
    return rows.map((row) => jsonDecode(row['value_json']! as String)).toList();
  }

  @override
  Future<int> createRecord(
    String key,
    String collection,
    dynamic record,
  ) async => _db.transaction((transaction) async {
    await _ensureCollection(transaction, key, collection);
    final rows = await transaction.rawQuery(
      'SELECT COALESCE(MAX(position), -1) + 1 AS next_position '
      'FROM account_records WHERE account_key = ? AND collection_key = ?',
      [key, collection],
    );
    final position = rows.single['next_position']! as int;
    await transaction.insert('account_records', {
      'account_key': key,
      'collection_key': collection,
      'position': position,
      'value_json': jsonEncode(record),
    });
    return position;
  });

  @override
  Future<void> updateRecord(
    String key,
    String collection,
    int index,
    dynamic record,
  ) async => _db.transaction((transaction) async {
    final count = await transaction.update(
      'account_records',
      {'value_json': jsonEncode(record)},
      where: 'account_key = ? AND collection_key = ? AND position = ?',
      whereArgs: [key, collection, index],
    );
    if (count == 0) {
      final rows = await transaction.query(
        'account_records',
        columns: const ['position'],
        where: 'account_key = ? AND collection_key = ?',
        whereArgs: [key, collection],
      );
      throw RangeError.index(index, rows);
    }
  });

  @override
  Future<void> deleteRecord(String key, String collection, int index) async =>
      _db.transaction((transaction) async {
        final count = await transaction.delete(
          'account_records',
          where: 'account_key = ? AND collection_key = ? AND position = ?',
          whereArgs: [key, collection, index],
        );
        if (count == 0) {
          final current = await transaction.query(
            'account_records',
            columns: const ['position'],
            where: 'account_key = ? AND collection_key = ?',
            whereArgs: [key, collection],
          );
          throw RangeError.index(index, current);
        }
        final rows = await transaction.query(
          'account_records',
          columns: const ['position', 'value_json'],
          where: 'account_key = ? AND collection_key = ?',
          whereArgs: [key, collection],
          orderBy: 'position',
        );
        for (var position = 0; position < rows.length; position++) {
          final oldPosition = rows[position]['position']! as int;
          if (oldPosition != position) {
            await transaction.update(
              'account_records',
              {'position': position},
              where: 'account_key = ? AND collection_key = ? AND position = ?',
              whereArgs: [key, collection, oldPosition],
            );
          }
        }
      });

  Future<void> _ensureCollection(
    sqflite.Transaction transaction,
    String key,
    String collection,
  ) async {
    await transaction.insert('accounts', {
      'account_key': key,
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: sqflite.ConflictAlgorithm.ignore);
    await transaction.insert('account_collections', {
      'account_key': key,
      'collection_key': collection,
    }, conflictAlgorithm: sqflite.ConflictAlgorithm.ignore);
  }
}

class _MemoryLocalDatabase implements LocalDatabase {
  _MemoryLocalDatabase(SharedPreferences preferences)
    : _accounts = _testDatabases[preferences] ??=
          <String, Map<String, dynamic>>{};

  static final _testDatabases = Expando<Map<String, Map<String, dynamic>>>(
    'test local database',
  );
  final Map<String, Map<String, dynamic>> _accounts;

  @override
  bool get writesAreSynchronous => true;

  Map<String, dynamic> _copy(Map<String, dynamic> account) =>
      Map<String, dynamic>.from(jsonDecode(jsonEncode(account)) as Map);

  @override
  Future<void> open() async {}

  @override
  Future<bool> containsAccount(String key) async => _accounts.containsKey(key);

  @override
  Future<Map<String, dynamic>?> readAccount(String key) async {
    final account = _accounts[key];
    return account == null ? null : _copy(account);
  }

  @override
  Future<Map<String, Map<String, dynamic>>> readAllAccounts() async => {
    for (final entry in _accounts.entries) entry.key: _copy(entry.value),
  };

  @override
  Future<bool> importAccountIfAbsent(
    String key,
    Map<String, dynamic> account,
  ) async {
    if (_accounts.containsKey(key)) return false;
    _accounts[key] = _copy(account);
    return true;
  }

  @override
  Future<void> writeAccount(String key, Map<String, dynamic> account) {
    writeAccountSynchronously(key, account);
    return Future<void>.value();
  }

  @override
  void writeAccountSynchronously(String key, Map<String, dynamic> account) {
    _accounts[key] = _copy(account);
  }

  @override
  Future<void> deleteAccount(String key) async {
    _accounts.remove(key);
  }

  @override
  Future<List<dynamic>> readRecords(String key, String collection) async {
    final records = _accounts[key]?[collection];
    return records is List ? List<dynamic>.from(records) : <dynamic>[];
  }

  @override
  Future<int> createRecord(
    String key,
    String collection,
    dynamic record,
  ) async {
    final account = _accounts[key] ?? <String, dynamic>{};
    final records = account[collection] is List
        ? List<dynamic>.from(account[collection] as List)
        : <dynamic>[];
    records.add(record);
    account[collection] = records;
    _accounts[key] = account;
    return records.length - 1;
  }

  @override
  Future<void> updateRecord(
    String key,
    String collection,
    int index,
    dynamic record,
  ) async {
    final account = _accounts[key] ?? <String, dynamic>{};
    final records = account[collection];
    if (records is! List || index < 0 || index >= records.length) {
      throw RangeError.index(index, records is List ? records : const []);
    }
    account[collection] = List<dynamic>.from(records)..[index] = record;
    _accounts[key] = account;
  }

  @override
  Future<void> deleteRecord(String key, String collection, int index) async {
    final account = _accounts[key] ?? <String, dynamic>{};
    final records = account[collection];
    if (records is! List || index < 0 || index >= records.length) {
      throw RangeError.index(index, records is List ? records : const []);
    }
    account[collection] = List<dynamic>.from(records)..removeAt(index);
    _accounts[key] = account;
  }
}
