import '../../../core/domain/money.dart';

enum TreasuryAccountRole { cash, nequi, reserve, other }

/// A local monetary account. Balances come exclusively from posted journals.
class TreasuryAccount {
  const TreasuryAccount({
    required this.id,
    required this.name,
    required this.role,
    required this.balanceMinor,
  });
  final String id;
  final String name;
  final TreasuryAccountRole role;
  final int balanceMinor;
}

/// The net movement of one account in one posted business document.
class TreasuryMovement {
  const TreasuryMovement({
    required this.id,
    required this.cashAccountId,
    required this.accountName,
    required this.documentId,
    required this.occurredAtUtc,
    required this.concept,
    required this.amountMinor,
  });
  final String id;
  final String cashAccountId;
  final String accountName;
  final String documentId;
  final DateTime occurredAtUtc;
  final String concept;
  final int amountMinor;
}

class TreasurySnapshot {
  TreasurySnapshot({
    required List<TreasuryAccount> accounts,
    required this.receivablesMinor,
    this.legacyReceivablesMinor = 0,
    required List<TreasuryMovement> movements,
  }) : accounts = List.unmodifiable(accounts),
       movements = List.unmodifiable(movements);

  final List<TreasuryAccount> accounts;

  /// Remaining customer receivables, excluded from available money.
  final int receivablesMinor;

  /// Included in receivablesMinor, imported as an aggregate without inventing
  /// individual customers or sales. It cannot be collected as a named debt.
  final int legacyReceivablesMinor;

  /// At most 50 movements per account, newest first with stable ID tie breaks.
  final List<TreasuryMovement> movements;

  int get cashMinor => _sum({TreasuryAccountRole.cash});
  int get nequiMinor => _sum({TreasuryAccountRole.nequi});
  int get reserveMinor => _sum({TreasuryAccountRole.reserve});
  int get totalAvailableMinor =>
      _sum({TreasuryAccountRole.cash, TreasuryAccountRole.nequi});

  int _sum(Set<TreasuryAccountRole> roles) {
    final sum = accounts
        .where((account) => roles.contains(account.role))
        .fold(
          BigInt.zero,
          (sum, account) => sum + BigInt.from(account.balanceMinor),
        );
    return treasuryCheckedMinor(sum, 'Total de cuentas');
  }
}

abstract interface class TreasuryStore {
  Future<void> ensureDefaults();
  Future<TreasurySnapshot> load();
}

class TreasuryValidationException implements Exception {
  const TreasuryValidationException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Shared range guard; intermediate financial sums must never use native int.
int treasuryCheckedMinor(BigInt value, String label) {
  if (value < Money.minMinorUnits || value > Money.maxMinorUnits) {
    throw TreasuryValidationException(
      '$label supera el rango monetario permitido.',
    );
  }
  final result = value.toInt();
  if (BigInt.from(result) != value) {
    throw TreasuryValidationException(
      '$label no puede representarse exactamente.',
    );
  }
  return result;
}
