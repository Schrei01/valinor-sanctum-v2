/// Calendar dates in Valinor's America/Bogota business timezone.
DateTime membershipDay(DateTime utc) {
  final local = utc.toUtc().subtract(const Duration(hours: 5));
  return DateTime.utc(local.year, local.month, local.day);
}

DateTime membershipNextMonth(DateTime day) {
  final last = DateTime.utc(day.year, day.month + 2, 0).day;
  return DateTime.utc(day.year, day.month + 1, day.day > last ? last : day.day);
}

class Membership {
  const Membership({
    required this.personId,
    required this.name,
    required this.email,
    this.birthDay,
    this.birthMonth,
    this.periodId,
    this.starts,
    this.ends,
    this.includedClaimed = false,
    this.discountsUsed = 0,
    this.voucherGrantedMinor = 0,
    this.voucherUsedMinor = 0,
    this.moneyScale = 0,
    this.currencyCode = 'COP',
  });
  final String personId, name, email;
  final int? birthDay, birthMonth;
  final String? periodId;
  final DateTime? starts, ends;
  final bool includedClaimed;
  final int discountsUsed;
  final int voucherGrantedMinor, voucherUsedMinor;
  final int moneyScale;
  final String currencyCode;
  int get voucherRemainingMinor => voucherGrantedMinor - voucherUsedMinor;
  int? daysUntilBirthday(DateTime utc) {
    final month = birthMonth, day = birthDay;
    if (month == null || day == null || month < 1 || month > 12 || day < 1) {
      return null;
    }
    final valid = DateTime.utc(2000, month, day);
    if (valid.month != month || valid.day != day) return null;
    final today = membershipDay(utc);
    DateTime occurrence(int year) {
      final last = DateTime.utc(year, month + 1, 0).day;
      return DateTime.utc(year, month, day > last ? last : day);
    }

    var next = occurrence(today.year);
    if (next.isBefore(today)) next = occurrence(today.year + 1);
    return next.difference(today).inDays;
  }

  String? birthdayNoticeAt(DateTime utc) {
    final days = daysUntilBirthday(utc);
    if (days == null || days > 7) return null;
    return days == 0
        ? 'Cumpleaños hoy'
        : days == 1
        ? 'Cumpleaños mañana'
        : 'Cumpleaños en $days días';
  }

  bool activeAt(DateTime utc) =>
      starts != null &&
      ends != null &&
      !membershipDay(utc).isBefore(starts!) &&
      membershipDay(utc).isBefore(ends!);
  String statusAt(DateTime utc) {
    if (starts == null) return 'Sin inscripción';
    final day = membershipDay(utc);
    if (day.isBefore(starts!)) return 'Próxima';
    final remaining = ends!.difference(day).inDays;
    if (remaining <= 0) return remaining == 0 ? 'Vence hoy' : 'Vencida';
    return remaining <= 3 ? 'Por vencer · $remaining días' : 'Activa';
  }
}

abstract interface class MembershipStore {
  Future<List<Membership>> load({DateTime? atUtc});
  Future<String> savePerson({
    required String commandId,
    String? personId,
    required String name,
    required String email,
    int? birthDay,
    int? birthMonth,
  });
  Future<void> claimIncluded({
    required String commandId,
    required String periodId,
    required String productId,
    required DateTime atUtc,
  });
  Future<List<({String name, String period, String detail})>> history(
    String personId,
  );
}
