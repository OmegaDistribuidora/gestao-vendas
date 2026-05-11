import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/remembered_login.dart';

abstract class RememberedLoginStore {
  Future<void> save(RememberedLogin rememberedLogin);
  Future<RememberedLogin?> load();
  Future<void> clear();
}

class SecureRememberedLoginStore implements RememberedLoginStore {
  const SecureRememberedLoginStore();

  static const FlutterSecureStorage _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  static const String _rememberedLoginKey = 'remembered_login_secure';

  @override
  Future<void> save(RememberedLogin rememberedLogin) async {
    await _storage.write(
      key: _rememberedLoginKey,
      value: jsonEncode(rememberedLogin.toJson()),
    );
  }

  @override
  Future<RememberedLogin?> load() async {
    final raw = await _storage.read(key: _rememberedLoginKey);
    if (raw == null || raw.isEmpty) {
      return null;
    }

    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      return null;
    }

    return RememberedLogin.fromJson(decoded);
  }

  @override
  Future<void> clear() async {
    await _storage.delete(key: _rememberedLoginKey);
  }
}

class MemoryRememberedLoginStore implements RememberedLoginStore {
  MemoryRememberedLoginStore({RememberedLogin? initialValue})
    : _rememberedLogin = initialValue;

  RememberedLogin? _rememberedLogin;

  @override
  Future<void> save(RememberedLogin rememberedLogin) async {
    _rememberedLogin = rememberedLogin;
  }

  @override
  Future<RememberedLogin?> load() async {
    return _rememberedLogin;
  }

  @override
  Future<void> clear() async {
    _rememberedLogin = null;
  }
}
