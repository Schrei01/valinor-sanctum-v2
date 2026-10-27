import 'package:flutter_test/flutter_test.dart';
import 'package:valinor_sanctum_2/features/legacy_conversion/domain/legacy_time.dart';

void main() {
  test(
    'naive times use Bogotá, explicit zones remain exact and microseconds sort correctly',
    () {
      expect(
        parseLegacyDate('2026-10-19T23:30:00.000001'),
        DateTime.utc(2026, 10, 20, 4, 30, 0, 0, 1),
      );
      expect(
        parseLegacyDate('2026-10-19T23:30:00-05:00'),
        DateTime.utc(2026, 10, 20, 4, 30),
      );
      expect(
        parseLegacyDate('2026-10-19T23:30:00Z'),
        DateTime.utc(2026, 10, 19, 23, 30),
      );
      expect(
        legacyUtcKey(DateTime.utc(2026, 1, 1)),
        '2026-01-01T00:00:00.000000Z',
      );
      expect(
        legacyUtcKey(
          DateTime.utc(2026, 1, 1),
        ).compareTo(legacyUtcKey(DateTime.utc(2026, 1, 1, 0, 0, 0, 0, 1))),
        lessThan(0),
      );
    },
  );
  test(
    'undated snapshots remain undated and invalid calendar/offset are rejected',
    () {
      expect(parseLegacyDate(null), isNull);
      expect(parseLegacyDate(''), isNull);
      for (final value in [
        '2026-02-30T10:00:00',
        '2026-10-19T25:00:00',
        '2026-10-19T10:00:00+25:00',
        'bad',
      ]) {
        expect(() => parseLegacyDate(value), throwsFormatException);
      }
    },
  );
}
