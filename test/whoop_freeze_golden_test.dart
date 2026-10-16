// CI-only adapter: the existing workflow names these files in its timezone
// step. Run Health Age calendar-boundary checks here, not unrelated suites.
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/health_age/health_age_inputs.dart';
void main() {
  test('Health Age 180 completed dates respect the process timezone', () {
    final w = HealthAgeWindow.completed180Days(DateTime(2026, 4, 1, 12));
    expect(w.dates.length, 180);
    expect(w.fromDay, '2025-10-03');
    expect(w.dates.last, '2026-03-31');
    expect(w.endExclusive.hour, 0);
    expect(w.toTs, DateTime(2026, 4, 1).millisecondsSinceEpoch ~/ 1000);
    final a = DateTime(2026, 3, 8);
    final b = DateTime(2026, 3, 9);
    if (a.timeZoneOffset != b.timeZoneOffset) {
      expect(b.difference(a).inHours, isNot(24));
    }
  });
}
