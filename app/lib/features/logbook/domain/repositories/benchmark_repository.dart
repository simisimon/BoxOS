import 'package:app/features/logbook/domain/models/benchmark_workout.dart';

abstract class BenchmarkRepository {
  Future<List<BenchmarkWorkout>> fetchBenchmarks();
}
