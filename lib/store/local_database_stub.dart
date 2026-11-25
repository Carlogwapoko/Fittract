import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class LocalDatabase {
  static bool useSqliteForTesting = false;

  LocalDatabase(this._preferences);

  final SharedPreferences _preferences;

  String _accountKey(String key) => 'ft_sqlite_account_$key';

  bool get writesAreSynchronous => false;

  Future<void> open() async {}

  Future<bool> containsAccount(String key) async =>
      _preferences.containsKey(_accountKey(key));

  Future<Map<String, dynamic>?> readAccount(String key) async {
    final raw = _preferences.getString(_accountKey(key));
    if (raw == null) return null;
    final value = jsonDecode(raw);
    if (value is! Map) {
      throw const FormatException('Stored account snapshot is not an object.');
    }
    return Map<String, dynamic>.from(value);
  }

  Future<Map<String, Map<String, dynamic>>> readAllAccounts() async {
    final accounts = <String, Map<String, dynamic>>{};
    const prefix = 'ft_sqlite_account_';
    for (final key in _preferences.getKeys()) {
      if (!key.startsWith(prefix)) continue;
      final account = await readAccount(key.substring(prefix.length));
      if (account != null) accounts[key.substring(prefix.length)] = account;
    }
    return accounts;
  }

  Future<bool> importAccountIfAbsent(
    String key,
    Map<String, dynamic> account,
  ) async {
    if (await containsAccount(key)) return false;
    await writeAccount(key, account);
    return true;
  }

  Future<void> writeAccount(String key, Map<String, dynamic> account) async {
    await _preferences.setString(_accountKey(key), jsonEncode(account));
  }

  void writeAccountSynchronously(String key, Map<String, dynamic> account) {
    throw UnsupportedError('SharedPreferences writes are asynchronous.');
  }

  Future<void> deleteAccount(String key) async {
    await _preferences.remove(_accountKey(key));
  }

  Future<List<dynamic>> readRecords(String key, String collection) async {
    final account = await readAccount(key);
    final records = account?[collection];
    return records is List ? List<dynamic>.from(records) : <dynamic>[];
  }

  Future<int> createRecord(
    String key,
    String collection,
    dynamic record,
  ) async {
    final account = await readAccount(key) ?? <String, dynamic>{};
    final records = account[collection] is List
        ? List<dynamic>.from(account[collection] as List)
        : <dynamic>[];
    records.add(record);
    account[collection] = records;
    await writeAccount(key, account);
    return records.length - 1;
  }

  Future<void> updateRecord(
    String key,
    String collection,
    int index,
    dynamic record,
  ) async {
    final account = await readAccount(key) ?? <String, dynamic>{};
    final records = account[collection];
    if (records is! List || index < 0 || index >= records.length) {
      throw RangeError.index(index, records is List ? records : const []);
    }
    final updated = List<dynamic>.from(records)..[index] = record;
    account[collection] = updated;
    await writeAccount(key, account);
  }

  Future<void> deleteRecord(String key, String collection, int index) async {
    final account = await readAccount(key) ?? <String, dynamic>{};
    final records = account[collection];
    if (records is! List || index < 0 || index >= records.length) {
      throw RangeError.index(index, records is List ? records : const []);
    }
    final updated = List<dynamic>.from(records)..removeAt(index);
    account[collection] = updated;
    await writeAccount(key, account);
  }
}
