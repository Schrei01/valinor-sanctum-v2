/// Legacy desktop dates without an offset were local business time in Bogotá.
DateTime? parseLegacyDate(Object? value) {
  if (value == null || value == '') return null;
  if (value is! String) {
    throw const FormatException('Fecha histórica no textual.');
  }
  final match = RegExp(
    r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.\d{1,6})?(Z|[+-]\d{2}:\d{2})?$',
  ).firstMatch(value);
  if (match == null) throw const FormatException('Fecha histórica inválida.');
  final parts = [for (var i = 1; i <= 6; i++) int.parse(match[i]!)];
  final day = DateTime.utc(parts[0], parts[1], parts[2]);
  if (parts[0] < 1 ||
      parts[0] > 9998 ||
      day.year != parts[0] ||
      day.month != parts[1] ||
      day.day != parts[2] ||
      parts[3] > 23 ||
      parts[4] > 59 ||
      parts[5] > 59) {
    throw const FormatException('Fecha histórica fuera de calendario.');
  }
  final zone = match[7];
  if (zone != null &&
      zone != 'Z' &&
      (int.parse(zone.substring(1, 3)) > 23 ||
          int.parse(zone.substring(4, 6)) > 59)) {
    throw const FormatException('Zona horaria inválida.');
  }
  return zone == null
      ? DateTime.parse('${value}Z').add(const Duration(hours: 5))
      : DateTime.parse(value).toUtc();
}

String legacyUtcKey(DateTime value) {
  final text = value.toUtc().toIso8601String();
  return RegExp(r'\.\d{3}Z$').hasMatch(text)
      ? '${text.substring(0, text.length - 1)}000Z'
      : text;
}
