import 'package:app/core/network/dio_client.dart';
import 'package:app/features/auth/data/session/secure_token_storage.dart';
import 'package:app/features/auth/data/session/token_storage.dart';
import 'package:app/features/calendar/domain/models/class_type.dart';
import 'package:app/features/profile/application/profile_controller.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final classTypesRepositoryProvider = Provider<ClassTypesRepository>(
  (ref) => ClassTypesRepository(
    dio: ref.read(dioProvider),
    tokenStorage: ref.read(tokenStorageProvider),
  ),
);

/// The active gym's custom class types. Loading them also registers them in
/// [ClassType.values], so pickers and badges know them.
final classTypesProvider = FutureProvider<List<ClassType>>((ref) async {
  final gymId = ref.watch(
    currentProfileProvider.select((p) => p.value?.activeGym?.id),
  );
  final types = gymId == null
      ? const <ClassType>[]
      : await ref.watch(classTypesRepositoryProvider).fetch();
  ClassType.registerCustom(types);
  return types;
});

/// Owners add and remove custom types (`/class-types`).
class ClassTypesRepository {
  ClassTypesRepository({required Dio dio, required TokenStorage tokenStorage})
    : _dio = dio,
      _tokenStorage = tokenStorage;

  final Dio _dio;
  final TokenStorage _tokenStorage;

  Future<List<ClassType>> fetch() async => _parse(
    await _dio.get<Map<String, dynamic>>(
      '/class-types',
      options: await _options(),
    ),
  );

  Future<List<ClassType>> create({
    required String name,
    required String colorKey,
    required int defaultCapacity,
  }) async => _parse(
    await _dio.post<Map<String, dynamic>>(
      '/class-types',
      data: {
        'name': name,
        'color': colorKey,
        'default_capacity': defaultCapacity,
      },
      options: await _options(),
    ),
  );

  Future<List<ClassType>> delete(int id) async => _parse(
    await _dio.delete<Map<String, dynamic>>(
      '/class-types',
      data: {'id': id},
      options: await _options(),
    ),
  );

  List<ClassType> _parse(Response<Map<String, dynamic>> response) =>
      (response.data?['class_types'] as List<dynamic>? ?? const [])
          .map((item) => ClassType.fromJson(item as Map<String, dynamic>))
          .toList();

  Future<Options> _options() async {
    final tokens = await _tokenStorage.readTokens();
    if (tokens == null) {
      throw Exception('No active session found.');
    }
    return Options(headers: {'Authorization': 'Bearer ${tokens.accessToken}'});
  }
}
