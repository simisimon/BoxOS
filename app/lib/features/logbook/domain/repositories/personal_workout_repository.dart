import 'package:app/features/logbook/domain/models/personal_workout.dart';

abstract class PersonalWorkoutRepository {
  Future<List<PersonalWorkout>> fetchWorkouts();

  Future<PersonalWorkout> createWorkout({
    required String title,
    required WorkoutType type,
    required Map<String, dynamic> structure,
  });

  Future<void> deleteWorkout({required int id});
}
