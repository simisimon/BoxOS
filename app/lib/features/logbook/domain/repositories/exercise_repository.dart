import 'package:app/features/logbook/domain/models/exercise.dart';

abstract class ExerciseRepository {
  Future<List<Exercise>> fetchExercises({String query, int limit});
}
