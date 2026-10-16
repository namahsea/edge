import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/compute/crossday_pipeline.dart';
import 'package:openstrap_edge/data/day_label.dart';
import 'package:openstrap_edge/health_age/health_age_input_repository.dart';
import 'package:openstrap_edge/health_age/health_age_input_service.dart';
import 'package:openstrap_edge/health_age/health_age_inputs.dart';

Map<String, dynamic> night(DateTime date, {int offset = 0, bool observed = true}) {
  final start = DateTime(date.year, date.month, date.day, 1, offset)
      .millisecondsSinceEpoch ~/ 1000;
  return {'date': dayLabelOf(date), 'hypnogram': [
    {'start': start, 'end': start + 8 * 3600,
      'stage': observed ? 'nrem' : 'unobserved'},
  ]};
}

void main() {
  test('public reuse is exactly the existing cross-day regularity envelope', () {
    final days = [
      for (var i = 0; i < 8; i++)
        night(DateTime(2026, 10, i + 1), offset: i % 2 * 15),
    ];
    expect(sleepRegularityFromDays(days),
      equals(buildCrossDayBundle(days, const {})['regularity']));
  });

  test('helper supports 180 observed calendar days, not 90 latest rows', () {
    final w = HealthAgeWindow.completed180Days(DateTime(2026, 10, 16));
    final days = [
      for (var i = 0; i < w.days; i++)
        night(DateTime(w.start.year, w.start.month, w.start.day + i)),
    ];
    final m = sleepRegularityFromDays(days);
    final value = m['value'] as Map;
    expect(value['sri'], closeTo(100, 1e-9));
    final pairs = value['pairs'] as List;
    expect(pairs, hasLength(179));
    expect((pairs.first as Map)['prev_date'], w.fromDay);
    expect((pairs.last as Map)['date'], w.dates.last);
  });

  test('missing and unobserved days do not invent adjacent comparisons', () {
    final days = [
      night(DateTime(2026, 10, 1)),
      night(DateTime(2026, 10, 2)),
      night(DateTime(2026, 10, 3), observed: false),
      night(DateTime(2026, 10, 8)),
      night(DateTime(2026, 10, 9)),
    ];
    final m = sleepRegularityFromDays(days);
    final pairs = (m['value'] as Map)['pairs'] as List;
    expect(pairs.map((p) => (p as Map)['date']), ['2026-10-02', '2026-10-09']);
    expect(sleepRegularityFromDays([
      night(DateTime(2026, 10, 1), observed: false),
      night(DateTime(2026, 10, 2), observed: false),
    ])['value'], '—');
  });

  test('input layer retains every dated hypnogram used by existing SRI', () {
    final w = HealthAgeWindow.completed180Days(DateTime(2026, 10, 16));
    final nights = [
      for (var i = 1; i <= 3; i++) night(DateTime(2026, 10, i)),
    ];
    final out = buildHealthAgeInputs(w, HealthAgeRawInputs(days: [
      for (final n in nights) {
        'day_id': n['date'], 'algo_version': 111, 'source': 'band',
        'payload': {'series': {'hypnogram': n['hypnogram']},
          'sleep': {'accounting': {'confidence': 0.6, 'value': {'tst_sec': 28800}}}},
      },
    ]));
    final metric = out[HealthAgeMetricId.sleepConsistency];
    expect(metric.value, (sleepRegularityFromDays(nights)['value'] as Map)['sri']);
    expect(metric.observations, hasLength(180));
    expect(metric.samplesAvailable, 3);
    expect(metric.daysAvailable, 3);
    expect(metric.coveragePercentage, closeTo(3 / 180 * 100, 1e-9));
    final obs = metric.observations.where((o) => o.value != null).toList();
    expect(obs.map((o) => o.date), ['2026-10-01', '2026-10-02', '2026-10-03']);
    expect((obs.first.value as Map)['hypnogram'], nights.first['hypnogram']);
    expect(obs.last.details['comparisons'], isNotEmpty);
    expect(metric.details['existingSriMetric'], isNotNull);
  });
}
