import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'cloud_api.dart';

class CloudSession {
  final String origin;
  final String userId;
  final String name;
  final String token;
  CloudSession({required this.origin, required this.userId,
    required this.name, required this.token});
  String get namespace => jsonEncode([origin, userId]);

  static const _storage = FlutterSecureStorage();
  static const _key = 'smartnotes_cloud_session_v1';

  Future<void> save() => _storage.write(key: _key, value: jsonEncode({
    'origin': origin, 'userId': userId, 'name': name, 'token': token,
  }));

  static Future<CloudSession?> restore() async {
    final raw = await _storage.read(key: _key);
    if (raw == null) return null;
    final data = jsonDecode(raw) as Map<String, dynamic>;
    return CloudSession(origin: data['origin'] as String,
      userId: data['userId'] as String, name: data['name'] as String,
      token: data['token'] as String);
  }

  static Future<void> forget() => _storage.delete(key: _key);

  static Future<CloudSession> signIn(String address, String email,
      String password, {String? name}) async {
    final api = CloudApi(address);
    try {
      final data = await api.request('POST', name == null ? '/auth/login' : '/auth/register',
        body: {'email': email.trim(), 'password': password, if (name != null) 'name': name.trim()});
      final session = CloudSession(origin: api.origin.toString(),
        userId: data['user']['id'] as String, name: data['user']['name'] as String,
        token: data['access_token'] as String);
      await session.save();
      return session;
    } finally {
      api.close();
    }
  }
}
