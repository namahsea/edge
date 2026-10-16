import '../data/day_label.dart';

enum HealthAgeConfidence { low, medium, high }

enum HealthAgeMetricId {
  chronologicalAge,
  sleepDuration,
  sleepConsistency,
  dailySteps,
  zoneOneToThreeMinutes,
  zoneFourToFiveMinutes,
  restingHeartRate,
  vo2Max,
  strengthActivity,
  leanMassPercentage,
}

/// Calendar dates, never a fixed number of 24-hour durations.
class HealthAgeWindow {
  HealthAgeWindow._(this.asOf, this.start, this.endExclusive);
  factory HealthAgeWindow.completed180Days(DateTime asOf) {
    final local = asOf.toLocal();
    final end = DateTime(local.year, local.month, local.day);
    return HealthAgeWindow._(
      asOf,
      DateTime(end.year, end.month, end.day - 180),
      end,
    );
  }
  final DateTime asOf;
  final DateTime start;
  final DateTime endExclusive;
  int get days => 180;
  String get fromDay => dayLabelOf(start);
  String get toDayExclusive => dayLabelOf(endExclusive);
  int get fromTs => start.millisecondsSinceEpoch ~/ 1000;
  int get toTs => endExclusive.millisecondsSinceEpoch ~/ 1000;
  List<String> get dates => [
    for (var i = 0; i < days; i++)
      dayLabelOf(DateTime(start.year, start.month, start.day + i)),
  ];
  bool containsDay(String date) =>
      dates.contains(date);
}

/// JSON-safe, recursively immutable provenance and original recorded fields.
Object? freezeHealthAgeValue(Object? value) {
  if (value is Map) {
    return Map<String, Object?>.unmodifiable({
      for (final e in value.entries)
        e.key.toString(): freezeHealthAgeValue(e.value),
    });
  }
  if (value is List) {
    return List<Object?>.unmodifiable(value.map(freezeHealthAgeValue));
  }
  return value;
}

class HealthAgeObservation {
  HealthAgeObservation({
    required this.date,
    required Object? value,
    required Map<String, Object?> source,
    this.timestamp,
    this.sourceConfidence,
    this.missingReason,
    Map<String, Object?> details = const {},
  }) : value = freezeHealthAgeValue(value),
       source = freezeHealthAgeValue(source) as Map<String, Object?>,
       details = freezeHealthAgeValue(details) as Map<String, Object?>;
  /// Null only when the source never recorded a date (the profile age).
  final String? date;
  final int? timestamp;
  final Object? value;
  final Map<String, Object?> source;
  final double? sourceConfidence;
  final String? missingReason;
  final Map<String, Object?> details;
}

class HealthAgeInputMetric {
  HealthAgeInputMetric({
    required Object? value,
    required this.unit,
    required List<HealthAgeObservation> observations,
    required this.daysAvailable,
    required this.samplesAvailable,
    required this.coveragePercentage,
    required this.coverageBasis,
    required this.confidence,
    required this.summaryMethod,
    required List<Map<String, Object?>> source,
    this.missingReason,
    List<String> notes = const [],
    Map<String, Object?> details = const {},
  }) : value = freezeHealthAgeValue(value),
       observations = List.unmodifiable(observations),
       source = List.unmodifiable(source.map(
         (s) => freezeHealthAgeValue(s) as Map<String, Object?>)),
       notes = List.unmodifiable(notes),
       details = freezeHealthAgeValue(details) as Map<String, Object?>;
  final Object? value;
  final String unit;
  final List<HealthAgeObservation> observations;
  final int daysAvailable;
  final int samplesAvailable;
  final double coveragePercentage;
  /// calendar_days, recorded_activity_days, or profile_field.
  final String coverageBasis;
  final HealthAgeConfidence confidence;
  final String summaryMethod;
  final List<Map<String, Object?>> source;
  final String? missingReason;
  final List<String> notes;
  final Map<String, Object?> details;
}

class HealthAgeInputs {
  HealthAgeInputs(this.window, Map<HealthAgeMetricId, HealthAgeInputMetric> metrics)
      : metrics = Map.unmodifiable(metrics);
  final HealthAgeWindow window;
  final Map<HealthAgeMetricId, HealthAgeInputMetric> metrics;
  HealthAgeInputMetric operator [](HealthAgeMetricId id) => metrics[id]!;
}
