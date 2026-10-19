import 'package:flutter_test/flutter_test.dart';
import 'package:valinor_sanctum_2/core/domain/money.dart';

Money cop(int value, {int scale = 2}) =>
    Money.fromMinorUnits(value, currency: 'COP', scale: scale);

Money parse(String text, {int scale = 2}) =>
    Money.parseEsCo(text, currency: 'COP', scale: scale);

void main() {
  group('Money profile and exact parsing', () {
    test('parses Colombian grouping and decimal comma without rounding', () {
      expect(parse('12.345,67').minorUnits, 1234567);
      expect(parse('12345,67').minorUnits, 1234567);
      expect(parse('  +12.345,6  ').minorUnits, 1234560);
      expect(parse('-0,01').minorUnits, -1);
      expect(parse('-0,00'), cop(0));
      expect(parse('1.234', scale: 0).minorUnits, 1234);
      expect(parse('0,000001', scale: 6).minorUnits, 1);
    });

    test('rejects malformed or ambiguous numeric notation', () {
      for (final text in [
        '',
        ' ',
        '1.23',
        '12.34.567',
        '1234.567',
        '1,234.56',
        '1,',
        ',50',
        '1 234,56',
        r'$1.234,00',
        'COP 1.234,00',
        '1e3',
        'NaN',
        'Infinity',
        '--1',
      ]) {
        expect(() => parse(text), throwsFormatException, reason: text);
      }
    });

    test('rejects excess precision even when the extra digits are zero', () {
      expect(() => parse('1,005'), throwsFormatException);
      expect(() => parse('1,000'), throwsFormatException);
      expect(() => parse('1,0', scale: 0), throwsFormatException);
    });

    test('validates currency and the configured scale', () {
      for (final currency in ['cop', '', 'CO', 'COP ', 'COPX']) {
        expect(
          () => Money.fromMinorUnits(0, currency: currency, scale: 2),
          throwsArgumentError,
        );
      }
      expect(() => cop(0, scale: -1), throwsRangeError);
      expect(() => cop(0, scale: 7), throwsRangeError);
    });

    test('preserves both signed 64-bit endpoints and rejects overflow', () {
      final maximum = parse('92.233.720.368.547.758,07');
      final minimum = parse('-92.233.720.368.547.758,08');
      expect(maximum.asBigInt, Money.maxMinorUnits);
      expect(minimum.asBigInt, Money.minMinorUnits);
      expect(() => parse('92.233.720.368.547.758,08'), throwsRangeError);
      expect(() => parse('-92.233.720.368.547.758,09'), throwsRangeError);
      expect(() => parse('999999999999999999999999999'), throwsRangeError);
      expect(
        () => Money.fromBigInt(
          Money.maxMinorUnits + BigInt.one,
          currency: 'COP',
          scale: 0,
        ),
        throwsRangeError,
      );
    });
  });

  group('Money formatting and identity', () {
    test('formats exact Colombian text with fixed configured precision', () {
      expect(cop(1234567).formatEsCo(), '12.345,67');
      expect(cop(-1).formatEsCo(includeCurrency: true), 'COP -0,01');
      expect(cop(0).formatEsCo(), '0,00');
      expect(cop(1234, scale: 0).formatEsCo(), '1.234');
      expect(cop(1, scale: 6).formatEsCo(), '0,000001');
      expect(cop(1234567).formatEsCo(groupThousands: false), '12345,67');
      expect(
        parse('-92.233.720.368.547.758,08').formatEsCo(),
        '-92.233.720.368.547.758,08',
      );
    });

    test('formatting round trips boundaries and every supported scale', () {
      for (var scale = 0; scale <= 6; scale++) {
        for (final amount in [
          Money.minMinorUnits,
          BigInt.from(-1),
          BigInt.zero,
          BigInt.one,
          Money.maxMinorUnits,
        ]) {
          final value = Money.fromBigInt(amount, currency: 'COP', scale: scale);
          expect(parse(value.formatEsCo(), scale: scale), value);
        }
      }
    });

    test('equality includes currency and scale, comparison requires both', () {
      expect(cop(12), cop(12));
      expect(cop(12).hashCode, cop(12).hashCode);
      expect(cop(12) == cop(12, scale: 0), isFalse);
      final usd = Money.fromMinorUnits(12, currency: 'USD', scale: 2);
      expect(cop(12) == usd, isFalse);
      expect(cop(10).compareTo(cop(11)), lessThan(0));
      expect(() => cop(12).compareTo(usd), throwsArgumentError);
    });
  });

  group('Money arithmetic', () {
    test('adds, subtracts and multiplies signed minor units exactly', () {
      expect(cop(100) + cop(23), cop(123));
      expect(cop(100) - cop(123), cop(-23));
      expect(-cop(23), cop(-23));
      expect(cop(101).multiply(3), cop(303));
      expect(cop(-101).multiply(-3), cop(303));
      expect(cop(101).multiply(0), cop(0));
      expect(() => cop(1) + cop(1, scale: 0), throwsArgumentError);
      expect(
        () => cop(1) - Money.fromMinorUnits(1, currency: 'USD', scale: 2),
        throwsArgumentError,
      );
    });

    test('detects overflow before converting an arithmetic result to int', () {
      final maximum = Money.fromBigInt(
        Money.maxMinorUnits,
        currency: 'COP',
        scale: 2,
      );
      final minimum = Money.fromBigInt(
        Money.minMinorUnits,
        currency: 'COP',
        scale: 2,
      );
      expect(() => maximum + cop(1), throwsRangeError);
      expect(() => minimum - cop(1), throwsRangeError);
      expect(() => -minimum, throwsRangeError);
      expect(() => maximum.multiply(2), throwsRangeError);
    });

    test('requires explicit rounding and handles signed half-unit ties', () {
      expect(
        cop(
          101,
        ).multiplyByRatio(1, 2, rounding: MoneyRounding.halfAwayFromZero),
        cop(51),
      );
      expect(
        cop(
          -101,
        ).multiplyByRatio(1, 2, rounding: MoneyRounding.halfAwayFromZero),
        cop(-51),
      );
      expect(
        cop(101).multiplyByRatio(1, 2, rounding: MoneyRounding.towardsZero),
        cop(50),
      );
      expect(
        cop(-101).multiplyByRatio(1, 2, rounding: MoneyRounding.floor),
        cop(-51),
      );
      expect(
        cop(-101).multiplyByRatio(1, 2, rounding: MoneyRounding.ceiling),
        cop(-50),
      );
      expect(
        cop(101).multiplyByRatio(-1, 2, rounding: MoneyRounding.ceiling),
        cop(-50),
      );
    });

    test('uses BigInt for a large intermediate whose final result fits', () {
      final maximum = Money.fromBigInt(
        Money.maxMinorUnits,
        currency: 'COP',
        scale: 2,
      );
      expect(
        maximum.multiplyByRatio(2, 2, rounding: MoneyRounding.towardsZero),
        maximum,
      );
      expect(
        () =>
            maximum.multiplyByRatio(2, 1, rounding: MoneyRounding.towardsZero),
        throwsRangeError,
      );
      for (final denominator in [0, -1]) {
        expect(
          () => cop(100).multiplyByRatio(
            1,
            denominator,
            rounding: MoneyRounding.halfAwayFromZero,
          ),
          throwsRangeError,
        );
      }
    });
  });
}
