import 'dart:convert';
import 'dart:isolate';

import '../compute/crossday_pipeline.dart' show sleepRegularityFromDays;
import '../data/day_label.dart';
import 'health_age_input_repository.dart';
import 'health_age_inputs.dart';

class HealthAgeInputService {
  HealthAgeInputService(this.repository, {DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;
  final HealthAgeInputRepository repository;
  final DateTime Function() _clock;

  Future<HealthAgeInputs> load({DateTime? asOf}) async {
    final window = HealthAgeWindow.completed180Days(asOf ?? _clock());
    final raw = await repository.read(window);
    return Isolate.run(() => buildHealthAgeInputs(window, raw));
  }
}

Map<String, dynamic> _map(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : {};
double? _number(Object? value, {bool positive = false}) {
  if (value is! num || !value.isFinite) return null;
  final n = value.toDouble();
  return (positive ? n > 0 : n >= 0) ? n : null;
}
double? _confidence(Object? value) {
  if (value is! num || !value.isFinite || value < 0 || value > 1) return null;
  return value.toDouble();
}
double? _envelopeNumber(Object? raw, {bool positive = false}) {
  final m = _map(raw);
  if (m.isEmpty) return null;
  if (m['confidence'] is num && (m['confidence'] as num) <= 0) return null;
  return _number(m['value'], positive: positive);
}
Map<String, dynamic>? _decodedDay(Map<String, dynamic>? row) {
  if (row == null || row['payload'] is Map) return row;
  try {
    final payload = jsonDecode(row['payload_json'] as String);
    final rawMethods = row['methods_json'];
    final methods = rawMethods is String ? jsonDecode(rawMethods) : const [];
    return {...row, 'payload': payload is Map ? payload : const {},
      'methods': methods is List ? methods : const [],
      'invalid_payload': payload is! Map};
  } catch (_) {
    return {...row, 'payload': const {}, 'methods': const [],
      'invalid_payload': true};
  }
}
Map<String, Object?> _source(
  Map<String, dynamic> row, Map<String, dynamic> bundle, String method,
) => {
  'storage': 'day_result',
  'origin': row['source'] ?? bundle['source'],
  'deviceFamily': bundle['device_family'],
  'algoVersion': row['algo_version'],
  'method': method,
  'partial': row['partial'] == 1,
  'producerMethods': row['methods'] ?? const [],
  'coverageDevices': row['coverage_devices'],
  'priorityOrder': row['priority_hash'],
};

/// Deterministic assembly only. Never writes or calls the derivation engine.
HealthAgeInputs buildHealthAgeInputs(
  HealthAgeWindow window, HealthAgeRawInputs raw,
) {
  final dates = window.dates;
  final inWindow = dates.toSet();
  final byDate = <String, Map<String, dynamic>>{};
  for (final row in raw.days) {
    final date = row['day_id'];
    if (date is! String || !inWindow.contains(date) || row['skipped'] == 1) {
      continue;
    }
    final prior = byDate[date];
    if (prior == null ||
        ((row['algo_version'] as num?) ?? 0) >
            ((prior['algo_version'] as num?) ?? 0)) byDate[date] = row;
  }
  final daily = {
    for (final id in [
      HealthAgeMetricId.sleepDuration, HealthAgeMetricId.dailySteps,
      HealthAgeMetricId.zoneOneToThreeMinutes,
      HealthAgeMetricId.zoneFourToFiveMinutes,
      HealthAgeMetricId.restingHeartRate, HealthAgeMetricId.sleepConsistency,
    ]) id: <HealthAgeObservation>[],
  };
  final sriDays = <Map<String, dynamic>>[];
  for (final date in dates) {
    final row = _decodedDay(byDate[date]);
    final b = _map(row?['payload']);
    final sc = _map(b['scalars']);
    final sleep = _map(b['sleep']);
    final accounting = _map(sleep['accounting']);
    final account = _map(accounting['value']);
    final rhr = _map(_map(b['clinical'])['resting_hr']);
    final steps = _map(b['steps']);
    final zones = _map(b['zones']);
    final methods = (row?['methods'] as List?) ?? const [];
    bool allowed(String key) => !methods.whereType<Map>().any(
      (m) => m['key'] == key &&
          (m['class'] == 'unavailable' || m['class'] == 'estimated'));
    final usable = row != null && row['invalid_payload'] != true &&
        row['payload_valid'] != 0;
    void add(HealthAgeMetricId id, Object? value, String method, {
      double? quality, Map<String, Object?> details = const {},
      String? reason,
    }) {
      daily[id]!.add(HealthAgeObservation(
        date: date, value: usable ? value : null,
        source: row == null ? {'storage': 'missing'} : _source(row, b, method),
        sourceConfidence: quality,
        missingReason: !usable ? 'no_usable_day_record' :
            value == null ? (reason ?? 'metric_not_available') : null,
        details: details,
      ));
    }
    final tst = accounting.isNotEmpty
        ? (accounting['confidence'] is num &&
                (accounting['confidence'] as num) <= 0
            ? null : _number(account['tst_sec']))
        : _number(sc['tst_min']);
    add(HealthAgeMetricId.sleepDuration,
      allowed('tst_min') && tst != null
          ? (accounting.isNotEmpty ? tst / 60 : tst) : null,
      'stored_main_sleep_tst',
      quality: _confidence(accounting['confidence']),
      details: {'accounting': accounting, 'sleepSource': b['sleep_source']});
    add(HealthAgeMetricId.dailySteps,
      allowed('steps') ? (steps.isNotEmpty
          ? _number(steps['value']) : _number(sc['steps'])) : null,
      'stored_daily_steps',
      details: {'stepSource': steps['source'], 'evidence': steps});
    final rv = rhr.isNotEmpty
        ? _envelopeNumber(rhr, positive: true)
        : _number(row?['rhr'] ?? sc['rhr'], positive: true);
    add(HealthAgeMetricId.restingHeartRate,
      allowed('rhr') ? rv : null, 'stored_nocturnal_rhr',
      quality: _confidence(rhr['confidence']), details: {'clinical': rhr});
    double? zoneSum(List<String> keys) {
      if (!allowed('strain')) return null;
      final ns = [for (final k in keys) _number(zones[k])];
      if (ns.any((n) => n == null)) return null;
      return ns.fold<double>(0, (s, n) => s + n!);
    }
    final zoneDetails = <String, Object?>{
      'bins': zones, 'zoneSource': b['zone_source'],
      'zoneMaxHr': b['zone_max_hr'], 'zoneLowerBpm': b['zone_lower_bpm'],
      'coverage': b['coverage'],
    };
    add(HealthAgeMetricId.zoneOneToThreeMinutes,
      zoneSum(['z1', 'z2', 'z3']), 'stored_daily_zone_minutes',
      details: zoneDetails);
    add(HealthAgeMetricId.zoneFourToFiveMinutes,
      zoneSum(['z4', 'z5']), 'stored_daily_zone_minutes',
      details: zoneDetails);
    final rawHyp = _map(b['series'])['hypnogram'];
    final hyp = <Map<String, dynamic>>[
      if (rawHyp is List)
        for (final seg in rawHyp.whereType<Map>())
          if (seg['start'] is num && (seg['start'] as num).isFinite &&
              seg['end'] is num && (seg['end'] as num).isFinite &&
              (seg['end'] as num) > (seg['start'] as num) &&
              const {'wake', 'light', 'deep', 'rem', 'nrem', 'asleep',
                'unobserved'}.contains(seg['stage']))
            Map<String, dynamic>.from(seg),
    ];
    final haveHyp = usable && allowed('tst_min') &&
        hyp.any((s) => s['stage'] != 'unobserved') &&
        !(accounting['confidence'] is num &&
          (accounting['confidence'] as num) <= 0);
    if (haveHyp) sriDays.add({'date': date, 'hypnogram': hyp});
    add(HealthAgeMetricId.sleepConsistency,
      haveHyp ? {'hypnogram': hyp} : null, 'existing_phillips_sri_input',
      quality: _confidence(accounting['confidence']),
      details: {'sleepSource': b['sleep_source'], 'recordedHypnogram': rawHyp});
  }

  final result = <HealthAgeMetricId, HealthAgeInputMetric>{};
  final age = _number(raw.profile?['age'], positive: true);
  final validAge = age != null && age == age.roundToDouble();
  final ageObs = <HealthAgeObservation>[
    if (validAge) HealthAgeObservation(
      date: null, value: age,
      source: {'storage': 'profile', 'field': 'age',
        'origin': null, 'freshness': 'unknown'},
      details: {'readAsOf': window.asOf.toIso8601String()},
    ),
  ];
  result[HealthAgeMetricId.chronologicalAge] = _metric(window, ageObs,
    value: validAge ? age : null, unit: 'years',
    method: 'stored_reported_age', basis: 'profile_field',
    notes: ['DOB and observation date are not stored; freshness is unknown.']);
  for (final id in daily.keys.where((k) => k != HealthAgeMetricId.sleepConsistency)) {
    final obs = daily[id]!;
    final ns = obs.map((o) => o.value).whereType<num>().toList();
    result[id] = _metric(window, obs,
      value: ns.isEmpty ? null :
          ns.fold<double>(0, (s, n) => s + n) / ns.length,
      unit: id == HealthAgeMetricId.dailySteps ? 'steps/day' :
          id == HealthAgeMetricId.restingHeartRate ? 'bpm' :
          id == HealthAgeMetricId.sleepDuration ? 'min/night' : 'min/day',
      method: 'mean_of_available_days',
      notes: ['Missing days are excluded, never treated as zero.']);
  }
  final sri = sleepRegularityFromDays(sriDays);
  final sriValue = _map(sri['value']);
  final sriObs = <HealthAgeObservation>[
    for (final o in daily[HealthAgeMetricId.sleepConsistency]!)
      HealthAgeObservation(date: o.date, value: o.value, source: o.source,
        sourceConfidence: o.sourceConfidence, missingReason: o.missingReason,
        details: {...o.details, 'comparisons': [
          for (final p in (sriValue['pairs'] as List?) ?? const [])
            if (p is Map && p['date'] == o.date) p,
        ]}),
  ];
  final sriNumber = sriValue['sri'];
  result[HealthAgeMetricId.sleepConsistency] = _metric(window, sriObs,
    value: sriNumber is num && sriNumber.isFinite ? sriNumber : null,
    unit: 'SRI', method: 'existing_phillips_sri',
    missingReason: 'no_valid_adjacent_sleep_comparison',
    summaryConfidence: _confidence(sri['confidence']),
    details: {'existingSriMetric': sri},
    notes: ['Observations retain night hypnograms, including thin comparisons '
      'omitted from the published pair list. SRI is not WHOOP consistency.']);

  final sets = <String, List<Map<String, dynamic>>>{};
  for (final s in raw.strengthSets) {
    final id = s['session_id'];
    if (id is String) (sets[id] ??= []).add(s);
  }
  final vo2 = <HealthAgeObservation>[];
  final strength = <HealthAgeObservation>[];
  final seen = <String>{};
  final sessions = [...raw.sessions]..sort((a, b) =>
      ((a['start_ts'] as num?) ?? 0).compareTo((b['start_ts'] as num?) ?? 0));
  for (final s in sessions) {
    final id = s['id'];
    final start = _number(s['start_ts']);
    final end = _number(s['end_ts']);
    if (id is! String || !seen.add(id) || s['status'] != 'done' ||
        start == null || end == null || end <= start ||
        start < window.fromTs || start >= window.toTs || end > window.toTs) {
      continue;
    }
    final date = dayLabelOf(DateTime.fromMillisecondsSinceEpoch(
      (start * 1000).round()));
    final source = <String, Object?>{
      'storage': 'sessions', 'origin': s['source'],
      'sessionId': id, 'deviceFamily': s['device_family'],
    };
    final context = <String, Object?>{
      'startTs': start, 'endTs': end, 'type': s['type'],
      'private': s['private'], 'recordedDurationMin': s['duration_min'],
    };
    final v = _number(s['vo2max_estimate'], positive: true);
    if (v != null) vo2.add(HealthAgeObservation(
      date: date, timestamp: start.toInt(), value: v,
      source: {...source, 'method': 'stored_submax_vo2max', 'isEstimate': true},
      details: {...context, 'timestampMeaning': 'session_start',
        'estimateTimestamp': null},
    ));
    final ss = sets[id] ?? const <Map<String, dynamic>>[];
    if (s['type'] == 'strength' || ss.isNotEmpty) {
      strength.add(HealthAgeObservation(
        date: date, timestamp: start.toInt(),
        value: {'sessions': 1, 'sets': ss.length,
          'minutes': _number(s['duration_min'])},
        source: {...source, 'method': 'recorded_strength_activity'},
        details: {...context, 'sets': ss},
      ));
    }
  }
  result[HealthAgeMetricId.vo2Max] = _metric(window, vo2,
    value: vo2.isEmpty ? null : vo2.last.value, unit: 'mL/kg/min',
    method: 'latest_existing_estimate',
    notes: ['Existing submaximal session estimate, not a laboratory measurement. '
      'No new estimate or RHR-based fallback is calculated.']);
  final knownMinutes = [
    for (final o in strength)
      if (_map(o.value)['minutes'] case final num n) n,
  ];
  result[HealthAgeMetricId.strengthActivity] = _metric(window, strength,
    value: strength.isEmpty ? null : {
      'sessions': strength.length,
      'sets': strength.fold<int>(0,
        (n, o) => n + (_map(o.value)['sets'] as int)),
      'minutes': knownMinutes.length != strength.length ? null :
          knownMinutes.fold<double>(0, (n, v) => n + v),
      'knownMinutes': knownMinutes.isEmpty ? null :
          knownMinutes.fold<double>(0, (n, v) => n + v),
      'sessionsWithKnownDuration': knownMinutes.length,
    }, unit: 'recorded_activity', method: 'recorded_strength_activity',
    basis: 'recorded_activity_days',
    notes: ['Unlogged days are unknown, not zero activity. Sets do not imply '
      'duration. Boundary-crossing, unfinished and orphaned sessions are excluded.']);
  result[HealthAgeMetricId.leanMassPercentage] = _metric(window, const [],
    value: null, unit: '%', method: 'unavailable',
    missingReason: 'no_supported_lean_mass_percentage_source',
    notes: ['Weight, BMI, impedance and body fat are not converted to lean mass.']);
  return HealthAgeInputs(window, result);
}

HealthAgeInputMetric _metric(
  HealthAgeWindow window, List<HealthAgeObservation> observations, {
  required Object? value, required String unit, required String method,
  String basis = 'calendar_days', String? missingReason,
  List<String> notes = const [], double? summaryConfidence,
  Map<String, Object?> details = const {},
}) {
  final available = observations.where((o) => o.value != null).toList();
  final days = available.map((o) => o.date).whereType<String>().toSet().length;
  final coverage = basis == 'profile_field'
      ? (available.isEmpty ? 0.0 : 100.0) : days / window.days * 100;
  var rank = value == null || coverage < 50 ? 0 : coverage < 80 ? 1 : 2;
  if (summaryConfidence != null) {
    final cap = summaryConfidence < 0.5 ? 0 : summaryConfidence < 0.8 ? 1 : 2;
    if (cap < rank) rank = cap;
  }
  final sources = <String, Map<String, Object?>>{};
  final versions = <Object?>{};
  final families = <String>{};
  for (final o in available) {
    sources[jsonEncode(o.source)] = o.source;
    families.add(jsonEncode([o.source['origin'], o.source['deviceFamily']]));
    if (o.source['algoVersion'] != null) versions.add(o.source['algoVersion']);
    final c = o.sourceConfidence;
    final cap = o.source['origin'] == null || c == null ||
        c < 0.5 || o.source['partial'] == true ? 0 : c < 0.8 ? 1 : 2;
    if (cap < rank) rank = cap;
    if (o.source['isEstimate'] == true && rank > 1) rank = 1;
  }
  if ((versions.length > 1 || families.length > 1) && rank > 1) rank = 1;
  return HealthAgeInputMetric(
    value: value, unit: unit, observations: observations,
    daysAvailable: days, samplesAvailable: available.length,
    coveragePercentage: coverage, coverageBasis: basis,
    confidence: HealthAgeConfidence.values[rank], summaryMethod: method,
    source: sources.values.toList(), details: details,
    missingReason: value == null ? (missingReason ?? 'no_valid_observations') : null,
    notes: [...notes, 'Confidence describes availability and source quality, '
      'not measurement accuracy or Health Age accuracy.',
      if (versions.length > 1) 'Mixed algorithm versions are retained and labelled.',
      if (families.length > 1) 'Mixed source families are retained and labelled.'],
  );
}
