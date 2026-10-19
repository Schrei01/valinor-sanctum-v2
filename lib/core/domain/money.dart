/// Rounding is explicit at the operation that creates a monetary result.
enum MoneyRounding { towardsZero, floor, ceiling, halfAwayFromZero }

/// An exact amount in the minor unit of one currency and scale.
///
/// Negative values are allowed for balances and reversals. Commands such as
/// collecting a payment must enforce their own positive-amount rule.
final class Money implements Comparable<Money> {
  static final BigInt minMinorUnits = -(BigInt.one << 63);
  static final BigInt maxMinorUnits = (BigInt.one << 63) - BigInt.one;

  final int minorUnits;
  final String currency;
  final int scale;

  const Money._(this.minorUnits, this.currency, this.scale);

  factory Money.fromMinorUnits(
    int minorUnits, {
    required String currency,
    required int scale,
  }) => Money.fromBigInt(
    BigInt.from(minorUnits),
    currency: currency,
    scale: scale,
  );

  factory Money.fromBigInt(
    BigInt minorUnits, {
    required String currency,
    required int scale,
  }) {
    _validateProfile(currency, scale);
    return Money._(_checkedInt(minorUnits), currency, scale);
  }

  /// Parses es_CO numeric text, with optional dots separating groups of three
  /// digits and a comma as the decimal separator. Currency symbols, exponents,
  /// internal spaces and excess fractional digits are rejected.
  ///
  /// There is no implicit rounding: `1,234` is invalid at scale 2.
  factory Money.parseEsCo(
    String input, {
    required String currency,
    required int scale,
  }) {
    _validateProfile(currency, scale);
    final text = input.trim();
    final match = RegExp(
      r'^([+-]?)([0-9]+|[1-9][0-9]{0,2}(?:\.[0-9]{3})+)(?:,([0-9]+))?$',
    ).firstMatch(text);
    if (match == null) {
      throw FormatException('Importe es_CO inválido.', input);
    }

    final fractionalDigits = match.group(3) ?? '';
    if (fractionalDigits.length > scale) {
      throw FormatException(
        'El importe supera la precisión de $scale decimales.',
        input,
      );
    }

    final factor = BigInt.from(10).pow(scale);
    final whole = BigInt.parse(match.group(2)!.replaceAll('.', ''));
    final fraction = fractionalDigits.isEmpty
        ? BigInt.zero
        : BigInt.parse(fractionalDigits.padRight(scale, '0'));
    var amount = whole * factor + fraction;
    if (match.group(1) == '-') amount = -amount;
    return Money.fromBigInt(amount, currency: currency, scale: scale);
  }

  BigInt get asBigInt => BigInt.from(minorUnits);

  bool get isNegative => minorUnits < 0;

  bool get isZero => minorUnits == 0;

  Money operator +(Money other) {
    _requireCompatible(other);
    return _withAmount(asBigInt + other.asBigInt);
  }

  Money operator -(Money other) {
    _requireCompatible(other);
    return _withAmount(asBigInt - other.asBigInt);
  }

  Money operator -() => _withAmount(-asBigInt);

  Money multiply(int quantity) => _withAmount(asBigInt * BigInt.from(quantity));

  /// Applies an exact rational factor and rounds once to the stored scale.
  ///
  /// The denominator must be positive. Intermediate products use BigInt, so a
  /// result in range is valid even when its intermediate numerator exceeds
  /// signed 64-bit storage.
  Money multiplyByRatio(
    int numerator,
    int denominator, {
    required MoneyRounding rounding,
  }) {
    if (denominator <= 0) {
      throw RangeError.value(denominator, 'denominator', 'Debe ser positivo.');
    }

    final product = asBigInt * BigInt.from(numerator);
    final divisor = BigInt.from(denominator);
    final magnitude = product.abs();
    var rounded = magnitude ~/ divisor;
    final remainder = magnitude % divisor;
    final hasRemainder = remainder != BigInt.zero;
    final increment = switch (rounding) {
      MoneyRounding.towardsZero => false,
      MoneyRounding.floor => product.isNegative && hasRemainder,
      MoneyRounding.ceiling => !product.isNegative && hasRemainder,
      MoneyRounding.halfAwayFromZero => remainder * BigInt.two >= divisor,
    };
    if (increment) rounded += BigInt.one;
    if (product.isNegative) rounded = -rounded;
    return _withAmount(rounded);
  }

  /// Formats without floating-point conversion or rounding.
  String formatEsCo({
    bool includeCurrency = false,
    bool groupThousands = true,
  }) {
    final magnitude = asBigInt.abs();
    final factor = BigInt.from(10).pow(scale);
    final whole = (magnitude ~/ factor).toString();
    final buffer = StringBuffer();
    if (isNegative) buffer.write('-');
    for (var index = 0; index < whole.length; index++) {
      if (groupThousands && index > 0 && (whole.length - index) % 3 == 0) {
        buffer.write('.');
      }
      buffer.write(whole[index]);
    }
    if (scale > 0) {
      buffer.write(',');
      buffer.write((magnitude % factor).toString().padLeft(scale, '0'));
    }
    final formatted = buffer.toString();
    return includeCurrency ? '$currency $formatted' : formatted;
  }

  @override
  int compareTo(Money other) {
    _requireCompatible(other);
    return minorUnits.compareTo(other.minorUnits);
  }

  @override
  bool operator ==(Object other) =>
      other is Money &&
      minorUnits == other.minorUnits &&
      currency == other.currency &&
      scale == other.scale;

  @override
  int get hashCode => Object.hash(minorUnits, currency, scale);

  @override
  String toString() => formatEsCo(includeCurrency: true);

  Money _withAmount(BigInt value) =>
      Money.fromBigInt(value, currency: currency, scale: scale);

  void _requireCompatible(Money other) {
    if (currency != other.currency || scale != other.scale) {
      throw ArgumentError('Moneda y escala deben coincidir.');
    }
  }

  static void _validateProfile(String currency, int scale) {
    if (!RegExp(r'^[A-Z]{3}$').hasMatch(currency)) {
      throw ArgumentError.value(
        currency,
        'currency',
        'Use un código de 3 letras.',
      );
    }
    if (scale < 0 || scale > 6) {
      throw RangeError.range(scale, 0, 6, 'scale');
    }
  }

  static int _checkedInt(BigInt value) {
    if (value < minMinorUnits || value > maxMinorUnits) {
      throw RangeError(
        'El importe excede el rango entero con signo de 64 bits.',
      );
    }
    final result = value.toInt();
    if (BigInt.from(result) != value) {
      throw RangeError('El entorno no representa este entero exactamente.');
    }
    return result;
  }
}
