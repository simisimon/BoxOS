import 'package:app/core/network/dio_client.dart';
import 'package:app/features/auth/data/session/secure_token_storage.dart';
import 'package:app/features/auth/data/session/token_storage.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A movement as Settings › Movements lists it.
class GymMovement {
  const GymMovement({
    required this.id,
    required this.name,
    this.builtIn = false,
    this.archived = false,
    this.blockCount = 0,
    this.resultCount = 0,
  });

  factory GymMovement.fromJson(Map<String, dynamic> json) => GymMovement(
    id: (json['id'] as num).toInt(),
    name: json['name'] as String? ?? '',
    builtIn: json['built_in'] as bool? ?? false,
    archived: json['archived'] as bool? ?? false,
    blockCount: (json['block_count'] as num?)?.toInt() ?? 0,
    resultCount: (json['result_count'] as num?)?.toInt() ?? 0,
  );

  final int id;
  final String name;
  final bool builtIn;
  final bool archived;
  final int blockCount;
  final int resultCount;
}

/// The gym's own movements (archived included) for Settings › Movements.
final gymMovementsProvider = FutureProvider.autoDispose<List<GymMovement>>(
  (ref) => ref.watch(movementsAdminProvider).fetchGymMovements(),
);

final movementsAdminProvider = Provider<MovementsAdmin>((ref) {
  return ApiMovementsAdmin(
    dio: ref.read(dioProvider),
    tokenStorage: ref.read(tokenStorageProvider),
  );
});

/// Owners tidy the gym's movements: rename, archive, merge duplicates.
abstract class MovementsAdmin {
  Future<List<GymMovement>> fetchGymMovements();

  /// Movements in the picker (the gym's and the built-in ones).
  Future<List<GymMovement>> search(String query);

  Future<GymMovement> update(int id, {String? name, bool? archived});

  /// Moves [id]'s blocks and results to [intoId].
  Future<GymMovement> merge(int id, {required int intoId});
}

class ApiMovementsAdmin implements MovementsAdmin {
  ApiMovementsAdmin({required Dio dio, required TokenStorage tokenStorage})
    : _dio = dio,
      _tokenStorage = tokenStorage;

  final Dio _dio;
  final TokenStorage _tokenStorage;

  @override
  Future<List<GymMovement>> fetchGymMovements() async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/gym-movements',
      options: await _options(),
    );
    return _list(response.data);
  }

  @override
  Future<List<GymMovement>> search(String query) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/movements',
      queryParameters: {'query': query, 'limit': 20},
      options: await _options(),
    );
    return _list(response.data);
  }

  @override
  Future<GymMovement> update(int id, {String? name, bool? archived}) async {
    final response = await _dio.patch<Map<String, dynamic>>(
      '/movements/$id',
      data: {'name': ?name, 'archived': ?archived},
      options: await _options(),
    );
    return GymMovement.fromJson(
      response.data!['movement'] as Map<String, dynamic>,
    );
  }

  @override
  Future<GymMovement> merge(int id, {required int intoId}) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/movements/$id/merge',
      data: {'into_id': intoId},
      options: await _options(),
    );
    return GymMovement.fromJson(
      response.data!['movement'] as Map<String, dynamic>,
    );
  }

  List<GymMovement> _list(Map<String, dynamic>? data) => [
    for (final item in data?['movements'] as List? ?? const [])
      GymMovement.fromJson(item as Map<String, dynamic>),
  ];

  Future<Options> _options() async {
    final tokens = await _tokenStorage.readTokens();
    if (tokens == null) throw Exception('No active session found.');
    return Options(headers: {'Authorization': 'Bearer ${tokens.accessToken}'});
  }
}
