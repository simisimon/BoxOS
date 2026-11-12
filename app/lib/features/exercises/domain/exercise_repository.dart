import 'package:app/features/exercises/domain/exercise.dart';

abstract class ExerciseRepository {
  Future<List<Exercise>> fetchExercises({String query, int limit});
}
