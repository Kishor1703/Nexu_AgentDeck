import 'package:shared_preferences/shared_preferences.dart';

abstract class Storage {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
}

class MemoryStorage implements Storage {
  final Map<String, String> _m = {};
  @override
  Future<String?> read(String key) async => _m[key];
  @override
  Future<void> write(String key, String value) async => _m[key] = value;
}

class PrefsStorage implements Storage {
  PrefsStorage(this._p);
  final SharedPreferences _p;
  @override
  Future<String?> read(String key) async => _p.getString(key);
  @override
  Future<void> write(String key, String value) async => _p.setString(key, value);
}
