import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

import 'storage.dart';

/// Stores only a salted SHA-256 hash of the PIN, never the PIN itself.
class PinService {
  PinService(this._storage);
  final Storage _storage;
  String? _salt, _hash;

  Future<void> load() async {
    final raw = await _storage.read('pin');
    if (raw == null) return;
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      _salt = m['salt'];
      _hash = m['hash'];
    } catch (_) {}
  }

  bool get isSet => _hash != null;
  static bool isValidFormat(String p) => RegExp(r'^\d{4}$').hasMatch(p);

  Future<void> setPin(String pin) async {
    final r = Random.secure();
    _salt = base64Url.encode(List<int>.generate(16, (_) => r.nextInt(256)));
    _hash = _digest(_salt!, pin);
    await _storage.write('pin', jsonEncode({'salt': _salt, 'hash': _hash}));
  }

  bool verify(String pin) => isSet && isValidFormat(pin) && _digest(_salt!, pin) == _hash;

  String _digest(String salt, String pin) =>
      sha256.convert(utf8.encode('$salt:$pin')).toString();
}
