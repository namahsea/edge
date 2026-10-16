import '../data/db.dart';
import 'health_age_inputs.dart';

class HealthAgeRawInputs {
  HealthAgeRawInputs({
    Map<String, dynamic>? profile,
    this.days = const [],
    this.sessions = const [],
    this.strengthSets = const [],
  }) : profile = profile == null ? null : Map.unmodifiable(profile);
  final Map<String, dynamic>? profile;
  final List<Map<String, dynamic>> days;
  final List<Map<String, dynamic>> sessions;
  final List<Map<String, dynamic>> strengthSets;
}

abstract class HealthAgeInputRepository {
  Future<HealthAgeRawInputs> read(HealthAgeWindow window);
}

/// No permission requests, sensor reads, writes, derivation or network access.
class LocalHealthAgeInputRepository implements HealthAgeInputRepository {
  LocalHealthAgeInputRepository({required this.getProfileMap});
  final Map<String, dynamic>? Function() getProfileMap;

  @override
  Future<HealthAgeRawInputs> read(HealthAgeWindow window) async {
    final currentProfile = getProfileMap();
    final profile = currentProfile == null ? null :
        Map<String, dynamic>.from(currentProfile);
    final rows = await LocalDb.healthAgeDayInputs(
      window.fromDay, window.toDayExclusive);
    return HealthAgeRawInputs(
      profile: profile,
      days: rows,
      sessions: await LocalDb.healthAgeSessions(window.fromTs, window.toTs),
      strengthSets: await LocalDb.healthAgeStrengthSets(
        window.fromTs, window.toTs),
    );
  }
}
