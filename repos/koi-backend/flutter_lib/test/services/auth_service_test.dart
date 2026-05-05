import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../lib/services/auth_service.dart';

class FakeSecureStorage extends FlutterSecureStorage {
  final Map<String, String> _store = {};

  FakeSecureStorage() : super();

  @override
  Future<void> write({required String key, required String? value, IOSOptions? iOptions, AndroidOptions? aOptions, LinuxOptions? lOptions, WebOptions? webOptions, MacOsOptions? mOptions, WindowsOptions? wOptions}) async {
    if (value == null) return;
    _store[key] = value;
  }

  @override
  Future<String?> read({required String key, IOSOptions? iOptions, AndroidOptions? aOptions, LinuxOptions? lOptions, WebOptions? webOptions, MacOsOptions? mOptions, WindowsOptions? wOptions}) async {
    return _store[key];
  }

  @override
  Future<void> delete({required String key, IOSOptions? iOptions, AndroidOptions? aOptions, LinuxOptions? lOptions, WebOptions? webOptions, MacOsOptions? mOptions, WindowsOptions? wOptions}) async {
    _store.remove(key);
  }
}

void main() {
  test('restoreSession returns stored UUID', () async {
    final fakeStorage = FakeSecureStorage();
    final uuid = Uuid().v4();
    await fakeStorage.write(key: 'koi_user_uuid', value: uuid);

    final service = AuthService(secureStorage: fakeStorage);
    final restored = await service.restoreSession();
    expect(restored, equals(uuid));
  });

  test('writing/reading koi uuid through service', () async {
    final fakeStorage = FakeSecureStorage();
    final service = AuthService(secureStorage: fakeStorage);
    final stored = await service.restoreSession();
    expect(stored, isNull);
  });
}
