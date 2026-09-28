import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:love_mobi/core/utils/formatting.dart';

/// The business runs entirely on Sri Lanka time, so these assertions must hold
/// no matter what timezone the phone is set to. They are written against
/// offset-bearing inputs, which is what the API now returns.
void main() {
  setUpAll(() async => initializeDateFormatting());

  group('Fmt renders instants on the Sri Lankan clock', () {
    test('a UTC instant past LKT midnight belongs to the next day', () {
      // 19:00Z is 00:30 the next morning in Colombo.
      expect(Fmt.date('2026-09-28T19:00:00Z'), '29 Sep 2026');
      expect(Fmt.time('2026-09-28T19:00:00Z'), '00:30');
      expect(Fmt.isoDate('2026-09-28T19:00:00Z'), '2026-09-29');
      expect(Fmt.isoDateTime('2026-09-28T19:00:00Z'), '2026-09-29 00:30:00');
    });

    test('a UTC instant before LKT midnight stays on the same day', () {
      // 18:00Z is 23:30 the same evening in Colombo.
      expect(Fmt.date('2026-09-28T18:00:00Z'), '28 Sep 2026');
      expect(Fmt.isoDate('2026-09-28T18:00:00Z'), '2026-09-28');
    });

    test('an explicit +05:30 offset is respected, not shifted again', () {
      expect(Fmt.dateTime('2026-09-28T19:00:00+05:30'), '28 Sep 2026, 19:00');
      expect(Fmt.isoDateTime('2026-09-28T00:00:00+05:30'),
          '2026-09-28 00:00:00');
    });

    test('a UTC DateTime is converted the same way', () {
      final instant = DateTime.utc(2026, 9, 28, 19, 0);
      expect(Fmt.isoDate(instant), '2026-09-29');
    });
  });

  group('Fmt treats zoneless values as wall clocks', () {
    test('a bare calendar date is never shifted', () {
      expect(Fmt.date('2026-09-28'), '28 Sep 2026');
      expect(Fmt.isoDate('2026-09-28'), '2026-09-28');
    });

    test('a zoneless date-time is our own clock', () {
      expect(Fmt.isoDateTime('2026-09-28 22:30:00'), '2026-09-28 22:30:00');
    });
  });

  group('lktNow', () {
    test('reports the Sri Lankan calendar day', () {
      final now = Fmt.lktNow();
      final expected = DateTime.now().toUtc().add(const Duration(hours: 5, minutes: 30));
      expect(now.year, expected.year);
      expect(now.month, expected.month);
      expect(now.day, expected.day);
    });

    test('is a local DateTime so the formatters read its fields', () {
      expect(Fmt.lktNow().isUtc, isFalse);
    });
  });

  group('nowIso stays an instant', () {
    test('is UTC, not a wall clock', () {
      expect(Fmt.nowIso().endsWith('Z'), isTrue);
    });
  });
}
