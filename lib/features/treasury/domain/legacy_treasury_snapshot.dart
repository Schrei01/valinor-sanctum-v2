/// A read-only source snapshot. Historical rows never post money to the ledger.
class LegacyTreasuryBalance {
  const LegacyTreasuryBalance({
    required this.role,
    required this.sourceTable,
    required this.sourceRowId,
    required this.sourceDateRaw,
    required this.amountMinor,
  });

  final String role;
  final String sourceTable;
  final int sourceRowId;
  final String sourceDateRaw;
  final int amountMinor;

  Map<String, Object?> toJson() => {
    'role': role,
    'sourceTable': sourceTable,
    'sourceRowId': sourceRowId,
    'sourceDateRaw': sourceDateRaw,
    'amountMinor': amountMinor,
  };
}

class LegacyTreasuryMovement {
  const LegacyTreasuryMovement({
    required this.sourceTable,
    required this.sourceRowId,
    required this.type,
    required this.fromRole,
    required this.toRole,
    required this.amountMinor,
    required this.reason,
    required this.sourceDateRaw,
  });

  final String sourceTable;
  final int sourceRowId;
  final String type;
  final String? fromRole;
  final String? toRole;
  final int amountMinor;
  final String reason;
  final String sourceDateRaw;

  Map<String, Object?> toJson() => {
    'sourceTable': sourceTable,
    'sourceRowId': sourceRowId,
    'type': type,
    'fromRole': fromRole,
    'toRole': toRole,
    'amountMinor': amountMinor,
    'reason': reason,
    'sourceDateRaw': sourceDateRaw,
  };
}

class LegacyTreasurySnapshot {
  LegacyTreasurySnapshot({
    required this.sourceName,
    required String sourceSha256,
    required this.extractedAtUtc,
    required this.moneyScale,
    required List<LegacyTreasuryBalance> balances,
    List<LegacyTreasuryMovement> movements = const [],
    this.currencyCode = 'COP',
  }) : sourceSha256 = sourceSha256.toLowerCase(),
       balances = List.unmodifiable(balances),
       movements = List.unmodifiable(movements) {
    if (sourceName.trim().isEmpty ||
        sourceName.contains(RegExp(r'[/\\]')) ||
        !RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(sourceSha256) ||
        !extractedAtUtc.isUtc ||
        extractedAtUtc.year < 1 ||
        extractedAtUtc.year > 9999 ||
        currencyCode != 'COP' ||
        moneyScale < 0 ||
        moneyScale > 6) {
      throw const LegacyTreasuryFormatException(
        'Los metadatos de tesorería de la copia no son válidos.',
      );
    }
    final roles = <String>{};
    for (final row in this.balances) {
      if (sourceTables[row.role] != row.sourceTable ||
          !roles.add(row.role) ||
          !_validSourceId(row.sourceRowId) ||
          !_validSourceDate(row.sourceDateRaw) ||
          !_validAmount(row.amountMinor)) {
        throw const LegacyTreasuryFormatException(
          'Los saldos de la copia contienen campos inválidos o duplicados.',
        );
      }
    }
    if (roles.length != sourceTables.length) {
      throw const LegacyTreasuryFormatException(
        'La copia debe contener los cuatro saldos de tesorería.',
      );
    }
    if (this.movements.length > 200) {
      throw const LegacyTreasuryFormatException(
        'El historial de consulta excede el límite de 200 movimientos.',
      );
    }
    final movementIds = <String>{};
    for (final row in this.movements) {
      final isIncome =
          row.sourceTable == 'movimientos' &&
          row.type == 'ingreso' &&
          row.fromRole == null &&
          sourceTables.containsKey(row.toRole);
      final isExpense =
          row.sourceTable == 'movimientos' &&
          row.type == 'egreso' &&
          row.toRole == null &&
          sourceTables.containsKey(row.fromRole);
      final isTransfer =
          row.sourceTable == 'transfermovements' &&
          row.type == 'transferencia' &&
          sourceTables.containsKey(row.fromRole) &&
          sourceTables.containsKey(row.toRole) &&
          row.fromRole != row.toRole;
      if (!(isIncome || isExpense || isTransfer) ||
          !_validSourceId(row.sourceRowId) ||
          !_validAmount(row.amountMinor) ||
          row.amountMinor <= 0 ||
          !_validSourceDate(row.sourceDateRaw) ||
          row.reason.trim().isEmpty ||
          !movementIds.add('${row.sourceTable}:${row.sourceRowId}')) {
        throw const LegacyTreasuryFormatException(
          'El historial de la copia contiene un movimiento inválido o duplicado.',
        );
      }
    }
  }

  static const sourceTables = <String, String>{
    'cash': 'cash',
    'nequi': 'nequi',
    'reserve': 'caja_mayor',
    'receivables': 'deudas',
  };
  static final BigInt maxInteger = (BigInt.one << 63) - BigInt.one;
  static final BigInt minInteger = -(BigInt.one << 63);

  final String sourceName;
  final String sourceSha256;
  final DateTime extractedAtUtc;
  final String currencyCode;
  final int moneyScale;
  final List<LegacyTreasuryBalance> balances;
  final List<LegacyTreasuryMovement> movements;

  LegacyTreasuryBalance balanceByRole(String role) =>
      balances.firstWhere((row) => row.role == role);

  Map<String, Object?> toJson() => {
    'formatVersion': 1,
    'sourceName': sourceName,
    'sourceSha256': sourceSha256,
    'extractedAtUtc': extractedAtUtc.toIso8601String(),
    'currencyCode': currencyCode,
    'moneyScale': moneyScale,
    'balances': [for (final row in balances) row.toJson()],
    'movements': [for (final row in movements) row.toJson()],
  };

  factory LegacyTreasurySnapshot.fromJson(Object? document) {
    if (document is! Map<String, dynamic> ||
        document['formatVersion'] is! int ||
        document['formatVersion'] != 1 ||
        document['balances'] is! List ||
        (document['movements'] != null && document['movements'] is! List)) {
      throw const LegacyTreasuryFormatException(
        'El formato de la copia de tesorería no es compatible.',
      );
    }
    final extractedRaw = _string(document, 'extractedAtUtc');
    final extracted = DateTime.tryParse(extractedRaw);
    if (!_validSourceDate(extractedRaw) ||
        !extractedRaw.endsWith('Z') ||
        extracted == null ||
        !extracted.isUtc) {
      throw const LegacyTreasuryFormatException(
        'La fecha de extracción de tesorería no es UTC válida.',
      );
    }
    return LegacyTreasurySnapshot(
      sourceName: _string(document, 'sourceName'),
      sourceSha256: _string(document, 'sourceSha256'),
      extractedAtUtc: extracted,
      currencyCode: _string(document, 'currencyCode'),
      moneyScale: _integer(document, 'moneyScale'),
      balances: [
        for (final item in document['balances'] as List) _balance(_map(item)),
      ],
      movements: [
        for (final item in (document['movements'] as List? ?? const []))
          _movement(_map(item)),
      ],
    );
  }

  static LegacyTreasuryBalance _balance(Map<String, dynamic> row) =>
      LegacyTreasuryBalance(
        role: _string(row, 'role'),
        sourceTable: _string(row, 'sourceTable'),
        sourceRowId: _integer(row, 'sourceRowId'),
        sourceDateRaw: _string(row, 'sourceDateRaw'),
        amountMinor: _integer(row, 'amountMinor'),
      );

  static LegacyTreasuryMovement _movement(Map<String, dynamic> row) =>
      LegacyTreasuryMovement(
        sourceTable: _string(row, 'sourceTable'),
        sourceRowId: _integer(row, 'sourceRowId'),
        type: _string(row, 'type'),
        fromRole: _nullableString(row, 'fromRole'),
        toRole: _nullableString(row, 'toRole'),
        amountMinor: _integer(row, 'amountMinor'),
        reason: _string(row, 'reason'),
        sourceDateRaw: _string(row, 'sourceDateRaw'),
      );
}

abstract interface class LegacyTreasuryStore {
  Future<LegacyTreasurySnapshot?> load();
}

class LegacyTreasuryFormatException implements Exception {
  const LegacyTreasuryFormatException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Parses SQLite CAST(amount AS TEXT) without floating point or rounding.
int legacyTreasuryAmountToMinor(Object? input, {required int moneyScale}) {
  if (input is! String ||
      input.length > 128 ||
      moneyScale < 0 ||
      moneyScale > 6) {
    throw const LegacyTreasuryFormatException(
      'El importe o la escala no es válido.',
    );
  }
  final match = RegExp(
    r'^([+-]?)([0-9]+)(?:\.([0-9]+))?(?:[eE]([+-]?[0-9]+))?$',
  ).firstMatch(input);
  final exponent = match == null ? null : int.tryParse(match.group(4) ?? '0');
  if (match == null ||
      exponent == null ||
      exponent < -1000 ||
      exponent > 1000) {
    throw const LegacyTreasuryFormatException(
      'El importe no es un decimal válido.',
    );
  }
  final fraction = match.group(3) ?? '';
  var value = BigInt.parse('${match.group(2)}$fraction');
  final shift = moneyScale + exponent - fraction.length;
  if (shift >= 0) {
    value *= BigInt.from(10).pow(shift);
  } else {
    final divisor = BigInt.from(10).pow(-shift);
    if (value % divisor != BigInt.zero) {
      throw const LegacyTreasuryFormatException(
        'El importe no es exacto con esta escala; no se redondeó.',
      );
    }
    value ~/= divisor;
  }
  if (match.group(1) == '-') value = -value;
  if (value < LegacyTreasurySnapshot.minInteger ||
      value > LegacyTreasurySnapshot.maxInteger) {
    throw const LegacyTreasuryFormatException(
      'El importe excede el rango permitido.',
    );
  }
  return value.toInt();
}

bool _validAmount(int value) =>
    BigInt.from(value) >= LegacyTreasurySnapshot.minInteger &&
    BigInt.from(value) <= LegacyTreasurySnapshot.maxInteger;
bool _validSourceId(int value) => value > 0 && _validAmount(value);

bool _validSourceDate(String raw) {
  final match = RegExp(
    r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.\d{1,6})?(?:Z|[+-]\d{2}:\d{2})?$',
  ).firstMatch(raw);
  if (match == null) return false;
  final offset = RegExp(r'[+-](\d{2}):(\d{2})$').firstMatch(raw);
  if (offset != null &&
      (int.parse(offset.group(1)!) > 23 || int.parse(offset.group(2)!) > 59)) {
    return false;
  }
  final year = int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  final day = int.parse(match.group(3)!);
  return year > 0 &&
      month > 0 &&
      month <= 12 &&
      day > 0 &&
      day <= DateTime.utc(year, month + 1, 0).day &&
      int.parse(match.group(4)!) <= 23 &&
      int.parse(match.group(5)!) <= 59 &&
      int.parse(match.group(6)!) <= 59 &&
      DateTime.tryParse(raw) != null;
}

Map<String, dynamic> _map(Object? value) {
  if (value is! Map<String, dynamic>) {
    throw const LegacyTreasuryFormatException(
      'Una fila de tesorería no es válida.',
    );
  }
  return value;
}

String _string(Map<String, dynamic> row, String field) {
  final value = row[field];
  if (value is! String) {
    throw LegacyTreasuryFormatException('El campo $field debe ser texto.');
  }
  return value;
}

String? _nullableString(Map<String, dynamic> row, String field) =>
    row[field] == null ? null : _string(row, field);

int _integer(Map<String, dynamic> row, String field) {
  final value = row[field];
  if (value is! int) {
    throw LegacyTreasuryFormatException(
      'El campo $field debe ser un entero exacto.',
    );
  }
  return value;
}
