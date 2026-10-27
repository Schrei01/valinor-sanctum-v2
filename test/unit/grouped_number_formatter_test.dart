import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:valinor_sanctum_2/core/domain/money.dart';
import 'package:valinor_sanctum_2/core/presentation/grouped_number_formatter.dart';

TextEditingValue value(String text, [int? caret]) => TextEditingValue(
  text: text,
  selection: TextSelection.collapsed(offset: caret ?? text.length),
);

void main() {
  const money = GroupedNumberFormatter();
  const integer = GroupedNumberFormatter(integerOnly: true, maxDigits: 10);
  test('typing, paste and fractional amounts retain exact es_CO value', () {
    for (final pair in [
      ('1234567', '1.234.567'),
      ('25000,50', '25.000,50'),
      ('-1234567,', '-1.234.567,'),
      ('0001234', '1.234'),
      ('', ''),
    ]) {
      expect(money.formatEditUpdate(value(''), value(pair.$1)).text, pair.$2);
    }
    final result = money.formatEditUpdate(value(''), value('1234567890123,45'));
    expect(
      Money.parseEsCo(result.text, currency: 'COP', scale: 2).minorUnits,
      123456789012345,
    );
    // Invalid money is retained for validation, never silently converted.
    expect(money.formatEditUpdate(value(''), value('25k')).text, '25k');
  });
  test(
    'editing in the middle keeps caret and selection at the edited digits',
    () {
      final middle = money.formatEditUpdate(
        value('12.345', 2),
        value('129.345', 3),
      );
      expect(middle.text, '129.345');
      expect(middle.selection.extentOffset, 3);
      final selected = money.formatEditUpdate(
        value(''),
        const TextEditingValue(
          text: '1234567',
          selection: TextSelection(baseOffset: 1, extentOffset: 6),
        ),
      );
      expect(
        selected.selection,
        const TextSelection(baseOffset: 1, extentOffset: 8),
      );
    },
  );
  test(
    'backspace and delete at separators remove a digit without trapping caret',
    () {
      final back = integer.formatEditUpdate(
        value('1.234', 2),
        value('1234', 1),
      );
      expect(back.text, '234');
      expect(back.selection.extentOffset, 0);
      final forward = integer.formatEditUpdate(
        value('1.234', 1),
        value('1234', 1),
      );
      expect(forward.text, '134');
      expect(forward.selection.extentOffset, 1);
    },
  );
  test(
    'integer digit limit excludes grouping and IME composition is untouched',
    () {
      expect(
        integer.formatEditUpdate(value(''), value('1234567890')).text,
        '1.234.567.890',
      );
      expect(integer.formatEditUpdate(value('12'), value('12,5')).text, '12,5');
      expect(
        integer.formatEditUpdate(value('12'), value('12345678901')).text,
        '12',
      );
      final composing = value(
        '1234',
      ).copyWith(composing: const TextRange(start: 0, end: 4));
      expect(integer.formatEditUpdate(value(''), composing), composing);
      expect(integer.formatEditUpdate(value('1.000'), value('')).text, '');
    },
  );
}
