import 'dart:convert';
import 'dart:math';

import 'package:app/core/network/dio_client.dart';
import 'package:app/features/auth/data/session/secure_token_storage.dart';
import 'package:app/features/auth/data/session/token_storage.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

final deviceRegistrationServiceProvider = Provider<DeviceRegistrationService>((
  ref,
) {
  final dio = ref.read(dioProvider);
  final tokenStorage = ref.read(tokenStorageProvider);
  return DeviceRegistrationService(
    dio: dio,
    tokenStorage: tokenStorage,
    secureStorage: const FlutterSecureStorage(),
  );
});

class DeviceRegistrationService {
  DeviceRegistrationService({
    required Dio dio,
    required TokenStorage tokenStorage,
    required FlutterSecureStorage secureStorage,
  }) : _dio = dio,
       _tokenStorage = tokenStorage,
       _secureStorage = secureStorage;

  static const _deviceTokenKey = 'device_registration_token';

  final Dio _dio;
  final TokenStorage _tokenStorage;
  final FlutterSecureStorage _secureStorage;

  Future<void> registerCurrentDevice() async {
    final accessToken = await _readAccessToken();
    if (accessToken == null) {
      return;
    }

    final deviceToken = await _readOrCreateDeviceToken();
    await _dio.post<void>(
      '/devices/register',
      data: {'device_token': deviceToken, 'platform': _platformName()},
      options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
    );
  }

  Future<void> unregisterCurrentDevice() async {
    final accessToken = await _readAccessToken();
    if (accessToken == null) {
      return;
    }

    final deviceToken = await _secureStorage.read(key: _deviceTokenKey);
    if (deviceToken == null || deviceToken.isEmpty) {
      return;
    }

    await _dio.delete<void>(
      '/devices/current',
      data: {'device_token': deviceToken},
      options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
    );
  }

  Future<String?> _readAccessToken() async {
    final tokens = await _tokenStorage.readTokens();
    return tokens?.accessToken;
  }

  Future<String> _readOrCreateDeviceToken() async {
    final existingToken = await _secureStorage.read(key: _deviceTokenKey);
    if (existingToken != null && existingToken.isNotEmpty) {
      return existingToken;
    }

    final token = _generateDeviceToken();
    await _secureStorage.write(key: _deviceTokenKey, value: token);
    return token;
  }

  String _generateDeviceToken() {
    final bytes = List<int>.generate(18, (_) => Random.secure().nextInt(256));
    return base64UrlEncode(bytes);
  }

  String _platformName() {
    if (kIsWeb) {
      return 'web';
    }
    return defaultTargetPlatform.name;
  }
}
