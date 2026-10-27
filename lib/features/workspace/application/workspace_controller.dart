import 'dart:async';
import '../../events/domain/events_store.dart';
import '../../debtors/domain/debtors_store.dart';
import '../../reports/domain/reports_store.dart';
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
  ReportsStore? get reportsStore => _session?.reportsStore;

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
      var confirmed = await session.store.readProfile();
      if (confirmed != null && confirmed.profileId != session.profileId) {
        throw StateError('La base corresponde a otro perfil.');
      }
      health = await session.store.readHealth();
      _checkHealth();
      if (confirmed == null) {
        await session.store.createProfile(
          BusinessProfile(
            profileId: session.profileId,
            businessName: 'Valinor',
            currencyCode: 'COP',
            moneyScale: 0,
            timezone: 'America/Bogota',
            createdAtUtc: DateTime.now().toUtc(),
          ),
        );
        confirmed = await session.store.readProfile();
        health = await session.store.readHealth();
        _checkHealth();
        if (confirmed == null ||
            confirmed.profileId != session.profileId ||
            confirmed.businessName != 'Valinor' ||
            confirmed.currencyCode != 'COP' ||
            confirmed.moneyScale != 0 ||
            confirmed.timezone != 'America/Bogota') {
          throw StateError('No se pudo recuperar la configuración de Valinor.');
        }
      }
      if (_disposed) return;
      profile = confirmed;
      state = WorkspaceState.ready;
    } catch (failure) {
      profile = null;
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
