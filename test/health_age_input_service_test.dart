import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/data/day_label.dart';
import 'package:openstrap_edge/health_age/health_age_input_repository.dart';
import 'package:openstrap_edge/health_age/health_age_input_service.dart';
import 'package:openstrap_edge/health_age/health_age_inputs.dart';

final window = HealthAgeWindow.completed180Days(DateTime(2026, 10, 16));

Map<String, dynamic> day(String date, {
  double steps = 0, double sleepMin = 420, double rhr = 55,
  double quality = 0.9, int version = 111,
}) => {
  'day_id': date, 'algo_version': version, 'source': 'band',
  'payload': {
    'device_family': 'whoop4',
    'steps': {'value': steps, 'source': 'phone', 'real_measured': true},
    'sleep_source': 'auto',
    'sleep': {'accounting': {'confidence': quality,
      'value': {'tst_sec': sleepMin * 60}}},
    'clinical': {'resting_hr': {'value': rhr, 'confidence': quality}},
    'zones': {'z1': 0, 'z2': 10, 'z3': 20, 'z4': 0, 'z5': 0},
    'zone_source': 'karvonen',
  },
};

class _Repository implements HealthAgeInputRepository {
  _Repository(this.data);
  final HealthAgeRawInputs data;
  HealthAgeWindow? received;
  @override
  Future<HealthAgeRawInputs> read(HealthAgeWindow window) async {
    received = window;
    return data;
  }
}

void main() {
  test('180 completed local dates exclude today across DST boundaries', () {
    final w = HealthAgeWindow.completed180Days(DateTime(2026, 4, 1, 14));
    expect(w.dates, hasLength(180));
    expect(w.fromDay, '2025-10-03');
    expect(w.dates.last, '2026-03-31');
    expect(w.toDayExclusive, '2026-04-01');
    expect(w.dates.toSet(), hasLength(180));
    expect(w.containsDay('2026-04-01'), isFalse);
    final spring = DateTime(2026, 3, 8);
    final next = DateTime(2026, 3, 9);
    if (spring.timeZoneOffset != next.timeZoneOffset) {
      expect(next.difference(spring).inHours, isNot(24));
    }
  });

  test('empty history keeps all metrics missing and daily gaps explicit', () {
    final out = buildHealthAgeInputs(window, HealthAgeRawInputs());
    expect(out.metrics, hasLength(10));
    for (final metric in out.metrics.values) {
      expect(metric.value, isNull);
      expect(metric.samplesAvailable, 0);
      expect(metric.daysAvailable, 0);
      expect(metric.coveragePercentage, 0);
      expect(metric.confidence, HealthAgeConfidence.low);
    }
    expect(out[HealthAgeMetricId.dailySteps].observations, hasLength(180));
    expect(out[HealthAgeMetricId.dailySteps].observations.last.date, '2026-10-15');
  });

  test('retains dated values and zeroes; means never divide by missing days', () {
    final out = buildHealthAgeInputs(window, HealthAgeRawInputs(days: [
      day('2026-10-14', steps: 0, sleepMin: 400),
      day('2026-10-15', steps: 1000, sleepMin: 440),
      day('2026-10-16', steps: 99999),
      day('2026-04-18', steps: 99999),
    ]));
    final steps = out[HealthAgeMetricId.dailySteps];
    expect(steps.value, 500);
    expect(steps.daysAvailable, 2);
    expect(steps.samplesAvailable, 2);
    expect(steps.coveragePercentage, closeTo(2 / 180 * 100, 1e-9));
    expect(steps.observations[178].value, 0);
    expect(steps.observations[179].value, 1000);
    expect(steps.observations.first.value, isNull);
    expect(out[HealthAgeMetricId.sleepDuration].value, 420);
    expect(out[HealthAgeMetricId.zoneOneToThreeMinutes].value, 30);
    expect(out[HealthAgeMetricId.zoneFourToFiveMinutes].value, 0);
    expect(steps.observations.last.details['stepSource'], 'phone');
  });

  test('one missing zone bin stays missing; unrelated inputs survive', () {
    final d = day('2026-10-15');
    ((d['payload'] as Map)['zones'] as Map).remove('z3');
    final out = buildHealthAgeInputs(window, HealthAgeRawInputs(days: [d]));
    expect(out[HealthAgeMetricId.zoneOneToThreeMinutes].value, isNull);
    expect(out[HealthAgeMetricId.zoneFourToFiveMinutes].value, 0);
    expect(out[HealthAgeMetricId.restingHeartRate].value, 55);
  });

  test('explicit absent envelope wins over stale scalar; invalid numbers missing', () {
    final d = day('2026-10-15', steps: double.nan, rhr: 0);
    d['rhr'] = 55;
    (d['payload'] as Map)['scalars'] = {'tst_min': 500, 'steps': 9000};
    (d['payload'] as Map)['sleep'] = {'accounting': {
      'value': '—', 'confidence': 0}};
    final out = buildHealthAgeInputs(window, HealthAgeRawInputs(days: [d]));
    expect(out[HealthAgeMetricId.sleepDuration].value, isNull);
    expect(out[HealthAgeMetricId.dailySteps].value, isNull);
    expect(out[HealthAgeMetricId.restingHeartRate].value, isNull);
  });

  test('per-metric unavailable and estimated-source gates are respected', () {
    final d = day('2026-10-15');
    d['methods'] = [
      {'key': 'steps', 'class': 'unavailable'},
      {'key': 'strain', 'class': 'estimated'},
    ];
    final out = buildHealthAgeInputs(window, HealthAgeRawInputs(days: [d]));
    expect(out[HealthAgeMetricId.dailySteps].value, isNull);
    expect(out[HealthAgeMetricId.zoneFourToFiveMinutes].value, isNull);
    expect(out[HealthAgeMetricId.sleepDuration].value, 420);
  });

  test('reported age has an undated observation and unknown freshness', () {
    final out = buildHealthAgeInputs(window,
      HealthAgeRawInputs(profile: {'age': 35, 'weight_kg': 80, 'height_cm': 180}));
    final age = out[HealthAgeMetricId.chronologicalAge];
    expect(age.value, 35);
    expect(age.observations.single.date, isNull);
    expect(age.observations.single.timestamp, isNull);
    expect(age.source.single['freshness'], 'unknown');
    expect(age.coverageBasis, 'profile_field');
    expect(age.daysAvailable, 0);
    expect(age.samplesAvailable, 1);
    expect(age.coveragePercentage, 100);
    expect(age.confidence, HealthAgeConfidence.low);
    expect(out[HealthAgeMetricId.leanMassPercentage].value, isNull);
    expect(out[HealthAgeMetricId.vo2Max].value, isNull);
  });

  test('low source quality and mixed versions cap availability confidence', () {
    final full = [
      for (final date in window.dates) day(date),
    ];
    final good = buildHealthAgeInputs(window, HealthAgeRawInputs(days: full));
    expect(good[HealthAgeMetricId.sleepDuration].confidence,
      HealthAgeConfidence.high);
    final mixed = [
      for (var i = 0; i < window.days; i++)
        day(window.dates[i], version: i.isEven ? 110 : 111),
    ];
    final out = buildHealthAgeInputs(window, HealthAgeRawInputs(days: mixed));
    expect(out[HealthAgeMetricId.sleepDuration].confidence,
      HealthAgeConfidence.medium);
    final low = [
      for (final date in window.dates) day(date, quality: 0.3),
    ];
    expect(buildHealthAgeInputs(window, HealthAgeRawInputs(days: low))
      [HealthAgeMetricId.sleepDuration].confidence, HealthAgeConfidence.low);
    expect(good[HealthAgeMetricId.dailySteps].confidence, HealthAgeConfidence.low,
      reason: 'no source confidence is invented for step counts');
  });

  test('VO2 keeps every session estimate and selects latest; strength keeps sets', () {
    final start = localDayStartSec('2026-10-14')!;
    Map<String, dynamic> session(String id, int ts, {String type = 'run',
      double? vo2, num? minutes = 30}) => {
      'id': id, 'status': 'done', 'type': type, 'start_ts': ts,
      'end_ts': ts + 3600, 'duration_min': minutes, 'source': 'manual',
      if (vo2 != null) 'vo2max_estimate': vo2,
    };
    final a = session('a', start, vo2: 40);
    final b = session('b', start + 86400, vo2: 42);
    final c = session('c', start, type: 'strength', minutes: null);
    final out = buildHealthAgeInputs(window, HealthAgeRawInputs(
      sessions: [b, c, a, a, {...b, 'id': 'live', 'status': 'live'},
        {...b, 'id': 'boundary', 'end_ts': window.toTs + 10}],
      strengthSets: [
        {'session_id': 'c', 'seq': 0, 'reps': 8, 'load_kg': null},
        {'session_id': 'orphan', 'seq': 0, 'reps': 99},
      ],
    ));
    final vo2 = out[HealthAgeMetricId.vo2Max];
    expect(vo2.value, 42);
    expect(vo2.observations.map((o) => o.value), [40, 42]);
    expect(vo2.observations.map((o) => o.date), ['2026-10-14', '2026-10-15']);
    expect(vo2.source.every((s) => s['isEstimate'] == true), isTrue);
    final strength = out[HealthAgeMetricId.strengthActivity];
    expect((strength.value as Map)['sessions'], 1);
    expect((strength.value as Map)['sets'], 1);
    expect((strength.value as Map)['minutes'], isNull);
    final storedSet = (strength.observations.single.details['sets'] as List).single as Map;
    expect(storedSet['reps'], 8);
    expect(storedSet['load_kg'], isNull);
  });

  test('observations and their nested recorded evidence are immutable', () {
    final d = day('2026-10-15', steps: 100);
    final out = buildHealthAgeInputs(window, HealthAgeRawInputs(days: [d]));
    final steps = out[HealthAgeMetricId.dailySteps];
    ((d['payload'] as Map)['steps'] as Map)['value'] = 999;
    expect(steps.observations.last.value, 100);
    expect((steps.observations.last.details['evidence'] as Map)['value'], 100);
    expect(() => steps.observations.clear(), throwsUnsupportedError);
    expect(() => (steps.observations.last.details['evidence'] as Map)['value'] = 3,
      throwsUnsupportedError);
  });

  test('public service reads once and assembles off the calling isolate', () async {
    final repo = _Repository(HealthAgeRawInputs(days: [day('2026-10-15')]));
    final out = await HealthAgeInputService(repo,
      clock: () => DateTime(2026, 10, 16, 15)).load();
    expect(repo.received!.toDayExclusive, '2026-10-16');
    expect(out[HealthAgeMetricId.sleepDuration].value, 420);
  });
}
