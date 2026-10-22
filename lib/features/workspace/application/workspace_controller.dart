import 'dart:async';
import '../../events/domain/events_store.dart';
import '../../debtors/domain/debtors_store.dart';
import 'package:flutter/foundation.dart';
import '../domain/business_profile.dart';
import '../domain/workspace_store.dart';
import '../../inventory/domain/inventory_store.dart';
import '../../inventory/domain/reference_inventory.dart';
import '../../sales/domain/sales_store.dart';
import '../../collections/domain/collections_store.dart';
import '../../supplier_payments/domain/supplier_payments_store.dart';
import '../../quick_sales/domain/quick_sales_store.dart';
import '../../stock_intake/domain/stock_intake_store.dart';
import '../../treasury/domain/treasury_store.dart';
import '../../treasury/domain/treasury_operation_store.dart';
import '../../treasury/domain/legacy_treasury_snapshot.dart';

enum WorkspaceState { loading, ready, failed }

class WorkspaceController extends ChangeNotifier {
  WorkspaceController({required this.openSession});
  final Future<WorkspaceSession> Function() openSession;
  WorkspaceSession? _session;
  WorkspaceState state = WorkspaceState.loading;
  BusinessProfile? profile;
  Map<String, Object?> health = const {};
  String? error;
  bool busy = false;
  bool _disposed = false;
  String get databasePath => _session?.databasePath ?? '';
  String get profileId => _session?.profileId ?? '';
  InventoryStore? get inventoryStore => _session?.inventoryStore;
  ReferenceInventoryStore? get referenceInventoryStore =>
      _session?.referenceInventoryStore;
  SalesStore? get salesStore => _session?.salesStore;
  CollectionsStore? get collectionsStore => _session?.collectionsStore;
  SupplierPaymentsStore? get supplierPaymentsStore =>
      _session?.supplierPaymentsStore;
  QuickSalesStore? get quickSalesStore => _session?.quickSalesStore;
  StockIntakeStore? get stockIntakeStore => _session?.stockIntakeStore;
  TreasuryStore? get treasuryStore => _session?.treasuryStore;
  TreasuryOperationStore? get treasuryOperationStore =>
      _session?.treasuryOperationStore;
  LegacyTreasuryStore? get legacyTreasuryStore => _session?.legacyTreasuryStore;
  EventsStore? get eventsStore => _session?.eventsStore;
  DebtorsStore? get debtorsStore => _session?.debtorsStore;

  Future<void> initialize() async {
    if (busy || _disposed || state == WorkspaceState.ready) return;
    busy = true;
    state = WorkspaceState.loading;
    error = null;
    _emit();
    try {
      final session = await openSession();
      if (_disposed) {
        await session.store.close();
        return;
      }
      _session = session;
      profile = await session.store.readProfile();
      if (profile != null && profile!.profileId != session.profileId) {
        throw StateError('La base corresponde a otro perfil.');
      }
      health = await session.store.readHealth();
      _checkHealth();
      state = WorkspaceState.ready;
    } catch (failure) {
      error = failure.toString();
      state = WorkspaceState.failed;
      final session = _session;
      _session = null;
      if (session != null) await session.store.close();
    } finally {
      busy = false;
      _emit();
    }
  }

  Future<bool> createProfile({
    required String businessName,
    required int moneyScale,
  }) async {
    if (busy || state != WorkspaceState.ready || profile != null) return false;
    final session = _session!;
    busy = true;
    error = null;
    _emit();
    var committed = false;
    try {
      final next = BusinessProfile(
        profileId: session.profileId,
        businessName: businessName,
        currencyCode: 'COP',
        moneyScale: moneyScale,
        timezone: 'America/Bogota',
        createdAtUtc: DateTime.now().toUtc(),
      );
      await session.store.createProfile(next);
      committed = true;
      // Read the committed configuration; never present an unconfirmed form as saved.
      final confirmed = await session.store.readProfile();
      health = await session.store.readHealth();
      _checkHealth();
      if (confirmed == null || confirmed.profileId != session.profileId) {
        throw StateError('No se pudo recuperar el perfil confirmado.');
      }
      profile = confirmed;
      return true;
    } catch (failure) {
      error = failure.toString();
      if (committed) {
        state = WorkspaceState.failed;
        _session = null;
        await session.store.close();
      }
      return false;
    } finally {
      busy = false;
      _emit();
    }
  }

  Future<void> verifyStorage() async {
    final session = _session;
    if (busy || _disposed || session == null) return;
    busy = true;
    error = null;
    _emit();
    try {
      health = await session.store.readHealth();
      _checkHealth();
    } catch (failure) {
      error = failure.toString();
      state = WorkspaceState.failed;
      if (identical(_session, session)) {
        _session = null;
        await session.store.close();
      }
    } finally {
      busy = false;
      _emit();
    }
  }

  void _checkHealth() {
    if (health['identityVerified'] != true ||
        health['integrityOk'] != true ||
        health['foreignKeysEnabled'] != true ||
        health['foreignKeyViolations'] != 0 ||
        health['schemaChecksumVerified'] != true ||
        health['migrationChecksumVerified'] != true) {
      throw StateError(
        'La verificación de almacenamiento no fue satisfactoria.',
      );
    }
  }

  void _emit() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    final session = _session;
    _session = null;
    if (session != null) unawaited(session.store.close());
    super.dispose();
  }
}
