import 'dart:convert';

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
    final days = <Map<String, dynamic>>[];
    for (final row in rows) {
      // Malformed persisted JSON is one missing day, not a made-up zero or a
      // reason to fail every other date in the window.
      try {
        final payload = jsonDecode(row['payload_json'] as String);
        final methods = jsonDecode(row['methods_json'] as String);
        days.add({
          ...row,
          'payload': payload is Map
              ? payload.cast<String, dynamic>() : const <String, dynamic>{},
          'methods': methods is List ? methods : const [],
        });
      } catch (_) {
        days.add({...row, 'payload': const <String, dynamic>{},
          'methods': const [], 'invalid_payload': true});
      }
    }
    return HealthAgeRawInputs(
      profile: profile,
      days: days,
      sessions: await LocalDb.healthAgeSessions(window.fromTs, window.toTs),
      strengthSets: await LocalDb.healthAgeStrengthSets(
        window.fromTs, window.toTs),
    );
  }
}
