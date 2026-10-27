import 'package:flutter/services.dart';

/// es_CO display formatting only: storage and money precision stay unchanged.
class GroupedNumberFormatter extends TextInputFormatter {
  const GroupedNumberFormatter({this.integerOnly = false, this.maxDigits});
  final bool integerOnly;
  final int? maxDigits;

  static String format(String text) {
    if (!RegExp(r'^[+-]?[0-9.]*,?[0-9]*$').hasMatch(text)) return text;
    final raw = text.replaceAll('.', '');
    final parts = raw.split(',');
    final whole = parts.first;
    final sign = whole.startsWith('-') || whole.startsWith('+')
        ? whole.substring(0, 1)
        : '';
    final digits = whole
        .substring(sign.length)
        .replaceFirst(RegExp(r'^0+(?=\d)'), '');
    final grouped = digits.replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (_) => '.',
    );
    return '$sign$grouped${parts.length == 2 ? ',${parts[1]}' : ''}';
  }

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (!newValue.composing.isCollapsed) return newValue;
    var raw = newValue.text;
    if (integerOnly && !RegExp(r'^[0-9.]*$').hasMatch(raw)) return newValue;
    if (maxDigits != null && raw.replaceAll('.', '').length > maxDigits!) {
      return oldValue;
    }
    // Deleting a separator should remove the adjacent digit, rather than
    // continually reinserting the separator and trapping the caret.
    if (oldValue.selection.isCollapsed &&
        newValue.selection.isCollapsed &&
        oldValue.text.length == raw.length + 1) {
      final at = newValue.selection.extentOffset;
      if (at >= 0 &&
          at < oldValue.text.length &&
          oldValue.text[at] == '.' &&
          raw == oldValue.text.replaceRange(at, at + 1, '')) {
        final backspace = oldValue.selection.extentOffset > at;
        final digit = backspace ? at - 1 : at;
        if (digit >= 0 && digit < raw.length) {
          raw = raw.replaceRange(digit, digit + 1, '');
          newValue = newValue.copyWith(
            text: raw,
            selection: TextSelection.collapsed(offset: backspace ? digit : at),
          );
        }
      }
    }
    final formatted = format(raw);
    int offset(int original) {
      if (original < 0) return formatted.length;
      final target = raw
          .substring(0, original.clamp(0, raw.length))
          .replaceAll('.', '')
          .length;
      if (target == 0) return 0;
      var count = 0;
      for (var i = 0; i < formatted.length; i++) {
        if (formatted[i] != '.') count++;
        if (count == target) return i + 1;
      }
      return formatted.length;
    }

    return newValue.copyWith(
      text: formatted,
      composing: TextRange.empty,
      selection: TextSelection(
        baseOffset: offset(newValue.selection.baseOffset),
        extentOffset: offset(newValue.selection.extentOffset),
      ),
    );
  }
}
