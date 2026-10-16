import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/compute/derivation_engine.dart' show kAlgoVersion;
import 'package:openstrap_edge/data/db.dart';
import 'package:openstrap_edge/health_age/health_age_input_repository.dart';
import 'package:openstrap_edge/health_age/health_age_input_service.dart';
import 'package:openstrap_edge/health_age/health_age_inputs.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final window = HealthAgeWindow.completed180Days(DateTime(2026, 10, 16));
  const name = 'health_age_input_repository.db';
  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await LocalDb.close();
    LocalDb.dbName = name;
    await databaseFactory.deleteDatabase(
      p.join(await databaseFactory.getDatabasesPath(), name));
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(() async {
    await LocalDb.close();
    await databaseFactory.deleteDatabase(
      p.join(await databaseFactory.getDatabasesPath(), name));
  });

  Future<void> putDay(String date, int version, {
    double steps = 10, bool skipped = false, String? payload,
  }) async {
    final db = await LocalDb.instance;
    await db.insert('day_result', {
      'day_id': date, 'algo_version': version, 'computed_at': 1,
      'skipped': skipped ? 1 : 0,
      'payload_json': payload ?? jsonEncode({
        'device_family': 'whoop4',
        'steps': {'value': steps, 'source': 'phone', 'real_measured': true},
        'series': {'hypnogram': [], 'hr_curve': [{'t': 1, 'v': 999}]},
      }),
    });
  }

  LocalHealthAgeInputRepository repo() =>
      LocalHealthAgeInputRepository(getProfileMap: () => {'age': 35});

  test('date bounds and served version select one exact row per day', () async {
    await putDay(window.fromDay, kAlgoVersion, steps: 0);
    await putDay('2026-10-15', kAlgoVersion - 1, steps: 100);
    await putDay('2026-10-15', kAlgoVersion, steps: 200);
    await putDay('2026-10-15', kAlgoVersion + 1, steps: 99999);
    await putDay('2026-10-16', kAlgoVersion);
    await putDay('2026-04-18', kAlgoVersion);
    await putDay('2026-10-14', kAlgoVersion, skipped: true);
    final raw = await repo().read(window);
    expect(raw.days.map((r) => r['day_id']), [window.fromDay, '2026-10-15']);
    final out = buildHealthAgeInputs(window, raw);
    expect(out[HealthAgeMetricId.dailySteps].value, 100);
    expect(out[HealthAgeMetricId.dailySteps].observations.first.value, 0);
    final series = ((raw.days.last['payload'] as Map)['series'] as Map);
    expect(series.containsKey('hr_curve'), isFalse,
      reason: 'large unrelated curves are not loaded');
  });

  test('newer method stamps are not misattributed to the served old version', () async {
    await putDay('2026-10-15', kAlgoVersion);
    final db = await LocalDb.instance;
    await db.insert('metric_series_version', {
      'date': '2026-10-15', 'algo_version': kAlgoVersion + 1, 'source': 'future',
    });
    await db.insert('metric_method', {
      'date': '2026-10-15', 'key': 'steps', 'method': 'future_method',
      'family': 'device', 'class': 'unavailable',
    });
    var raw = await repo().read(window);
    expect(raw.days.single['source'], isNull);
    expect(raw.days.single['methods'], isEmpty);
    expect(buildHealthAgeInputs(window, raw)[HealthAgeMetricId.dailySteps].value, 10);
    await db.update('metric_series_version', {
      'algo_version': kAlgoVersion, 'source': 'band'});
    raw = await repo().read(window);
    expect(raw.days.single['source'], 'band');
    expect(buildHealthAgeInputs(window, raw)[HealthAgeMetricId.dailySteps].value,
      isNull, reason: 'matching unavailable-source gate is respected');
  });

  test('corrupt payload is missing while other dates remain usable', () async {
    await putDay('2026-10-14', kAlgoVersion, payload: '{broken');
    await putDay('2026-10-15', kAlgoVersion, steps: 22);
    final out = buildHealthAgeInputs(window, await repo().read(window));
    expect(out[HealthAgeMetricId.dailySteps].value, 22);
    expect(out[HealthAgeMetricId.dailySteps].daysAvailable, 1);
    expect(out[HealthAgeMetricId.dailySteps].observations[178].value, isNull);
  });

  test('completed session reads retain real estimates, sets and unknown load', () async {
    final ts = window.toTs - 7200;
    for (final row in [
      {'id': 'strength', 'start_ts': ts, 'end_ts': ts + 1800,
        'type': 'strength', 'status': 'done', 'duration_min': 20,
        'vo2max_estimate': 42.0},
      {'id': 'live', 'start_ts': ts, 'end_ts': null,
        'type': 'strength', 'status': 'live'},
      {'id': 'outside', 'start_ts': window.fromTs - 1,
        'end_ts': window.fromTs + 1800, 'type': 'strength', 'status': 'done'},
      {'id': 'crossing', 'start_ts': ts, 'end_ts': window.toTs + 1,
        'type': 'strength', 'status': 'done'},
    ]) {
      await LocalDb.putSession({...row, 'created_at': ts, 'source': 'manual'});
    }
    await LocalDb.saveStrengthSets('strength', [
      {'exercise_key': 'pull_up', 'set_index': 0, 'reps': 8, 'at_ts': ts},
    ]);
    final raw = await repo().read(window);
    expect(raw.sessions.map((s) => s['id']), ['strength']);
    expect(raw.strengthSets.single['load_kg'], isNull);
    final out = buildHealthAgeInputs(window, raw);
    expect(out[HealthAgeMetricId.vo2Max].value, 42);
    expect((out[HealthAgeMetricId.strengthActivity].value as Map)['minutes'], 20);
    expect(out[HealthAgeMetricId.strengthActivity].observations.single.date, '2026-10-15');
  });

  test('reading inputs leaves stored scores and compute queues unchanged', () async {
    await putDay('2026-10-15', kAlgoVersion, steps: 99);
    final db = await LocalDb.instance;
    const tables = ['day_result', 'sessions', 'strength_set',
      'metric_series', 'compute_jobs', 'baselines'];
    Future<Map<String, List<Map<String, Object?>>>> snapshot() async => {
      for (final table in tables) table: await db.query(table),
    };
    final before = await snapshot();
    final out = await HealthAgeInputService(repo()).load(asOf: window.asOf);
    expect(out[HealthAgeMetricId.dailySteps].value, 99);
    expect(await snapshot(), equals(before));
    expect(out[HealthAgeMetricId.chronologicalAge].value, 35);
  });
}
