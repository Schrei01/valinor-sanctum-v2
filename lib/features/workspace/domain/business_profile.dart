/// Settings only. Creating a profile never introduces money or stock.
class BusinessProfile {
  BusinessProfile({
    required this.profileId,
    required String businessName,
    required this.currencyCode,
    required this.moneyScale,
    required this.timezone,
    required this.createdAtUtc,
  }) : businessName = businessName.trim() {
    if (this.businessName.length < 2 ||
        this.businessName.length > 80 ||
        RegExp(r'[\x00-\x1f]').hasMatch(this.businessName)) {
      throw ArgumentError('El nombre debe tener entre 2 y 80 caracteres.');
    }
    if (!RegExp(r'^[A-Z]{3}$').hasMatch(currencyCode) ||
        moneyScale < 0 ||
        moneyScale > 6 ||
        timezone.isEmpty ||
        profileId.isEmpty) {
      throw ArgumentError(
        'La configuración monetaria o del perfil no es válida.',
      );
    }
    if (!createdAtUtc.isUtc) throw ArgumentError('La fecha debe estar en UTC.');
  }

  final String profileId;
  final String businessName;
  final String currencyCode;
  final int moneyScale;
  final String timezone;
  final DateTime createdAtUtc;

  factory BusinessProfile.fromRow(Map<String, Object?> row) => BusinessProfile(
    profileId: row['profile_id'] as String,
    businessName: row['business_name'] as String,
    currencyCode: row['currency_code'] as String,
    moneyScale: row['money_scale'] as int,
    timezone: row['business_timezone'] as String,
    createdAtUtc: DateTime.parse(row['created_at_utc'] as String).toUtc(),
  );

  Map<String, Object?> toRow() => {
    'id': 1,
    'profile_id': profileId,
    'business_name': businessName,
    'currency_code': currencyCode,
    'money_scale': moneyScale,
    'business_timezone': timezone,
    'created_at_utc': createdAtUtc.toIso8601String(),
  };
}
