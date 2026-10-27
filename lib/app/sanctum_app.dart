import 'package:flutter/services.dart';
import 'dart:async';
import '../features/events/application/events_controller.dart';
import '../features/events/presentation/events_page.dart';
import 'dart:ui' show AppExitResponse;
import 'package:flutter/material.dart';
import '../core/presentation/valinor_logo.dart';
import '../features/workspace/application/workspace_controller.dart';
import '../features/inventory/application/inventory_controller.dart';
import '../features/inventory/presentation/catalog_page.dart';
import '../features/inventory/presentation/purchases_page.dart';
import '../features/debtors/application/debtors_controller.dart';
import '../features/debtors/presentation/debtors_page.dart';
import '../features/reports/application/reports_controller.dart';
import '../features/reports/presentation/reports_page.dart';
import '../features/supplier_payments/application/supplier_payments_controller.dart';
import '../features/supplier_payments/presentation/supplier_payments_page.dart';
import '../features/quick_sales/application/quick_sales_controller.dart';
import '../features/quick_sales/presentation/quick_sales_page.dart';
import '../features/stock_intake/application/stock_intake_controller.dart';
import '../features/treasury/application/treasury_controller.dart';
import '../features/treasury/application/treasury_operation_controller.dart';
import '../features/treasury/presentation/treasury_page.dart';

const _forest = Color(0xFF183D35);
const _gold = Color(0xFFD8BB80);
const _paper = Color(0xFFF5F5F0);
const _destinations = [
  (Icons.inventory_2_outlined, 'Catálogo'),
  (Icons.local_shipping_outlined, 'Compras'),
  (Icons.point_of_sale_outlined, 'Ventas'),
  (Icons.people_outline, 'Deudores'),
  (Icons.account_balance_outlined, 'Tesorería'),
  (Icons.event_outlined, 'Eventos'),
  (Icons.bar_chart_outlined, 'Reportes'),
];

class SanctumApp extends StatelessWidget {
  const SanctumApp({super.key, required this.controller});
  final WorkspaceController controller;

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'Valinor Sanctum 2.0',
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: _forest),
      scaffoldBackgroundColor: _paper,
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
        filled: true,
        fillColor: Colors.white,
      ),
      cardTheme: const CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: Colors.white,
      ),
    ),
    home: _WorkspaceShell(controller: controller),
  );
}

class _WorkspaceShell extends StatefulWidget {
  const _WorkspaceShell({required this.controller});
  final WorkspaceController controller;
  @override
  State<_WorkspaceShell> createState() => _WorkspaceShellState();
}

class _WorkspaceShellState extends State<_WorkspaceShell> {
  int _section = 2;
  InventoryController? _inventory;
  GlobalKey<CatalogPageState> _catalogKey = GlobalKey<CatalogPageState>();
  DebtorsController? _debtors;
  ReportsController? _reports;
  SupplierPaymentsController? _supplierPayments;
  QuickSalesController? _quickSales;
  StockIntakeController? _stockIntake;
  TreasuryController? _treasury;
  TreasuryOperationController? _treasuryOperations;
  EventsController? _events;
  bool _supplierWasConfirming = false;
  late final AppLifecycleListener _exitListener;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleCatalogShortcut);
    _exitListener = AppLifecycleListener(
      onExitRequested: () async {
        final saved = await _quickSales?.flushAll() ?? true;
        if (saved) return AppExitResponse.exit;
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Hay cambios sin guardar. Reintenta el guardado de las cuentas antes de cerrar.',
              ),
            ),
          );
        }
        return AppExitResponse.cancel;
      },
    );
  }

  bool _handleCatalogShortcut(KeyEvent event) {
    final keyboard = HardwareKeyboard.instance;
    if (!mounted ||
        _section != 0 ||
        widget.controller.profile == null ||
        ModalRoute.of(context)?.isCurrent != true ||
        event is! KeyDownEvent ||
        event.logicalKey != LogicalKeyboardKey.keyD ||
        !keyboard.isControlPressed ||
        keyboard.isAltPressed ||
        keyboard.isMetaPressed ||
        keyboard.isShiftPressed) {
      return false;
    }
    unawaited(
      _catalogKey.currentState?.openStockAdjustment() ?? Future<void>.value(),
    );
    return true;
  }

  void _selectSection(int index) {
    setState(() => _section = index);
    if (widget.controller.profile == null) return;
    if (index == 0) unawaited(_inventory?.load());
    if (index == 1) unawaited(_stockIntake?.load());
    if (index == 2) unawaited(_quickSales?.load());
    if (index == 3) unawaited(_debtors?.load());
    if (index == 5) unawaited(_events?.load());
    if (index == 6) unawaited(_reports?.load());
    if (index == 4) {
      unawaited(_treasury?.load());
      unawaited(_treasuryOperations?.load());
      unawaited(_supplierPayments?.load());
    }
  }

  void _supplierPaymentsChanged() {
    final confirming = _supplierPayments?.confirming ?? false;
    final completed = _supplierWasConfirming && !confirming;
    _supplierWasConfirming = confirming;
    if (completed && _section == 4) unawaited(_treasury?.load());
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleCatalogShortcut);
    _exitListener.dispose();
    _inventory?.dispose();
    _debtors?.dispose();
    _reports?.dispose();
    _supplierPayments?.removeListener(_supplierPaymentsChanged);
    _supplierPayments?.dispose();
    _quickSales?.dispose();
    _stockIntake?.dispose();
    _treasury?.dispose();
    _treasuryOperations?.dispose();
    _events?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final controller = widget.controller;
      final eventsStore = controller.eventsStore;
      if (!identical(_events?.store, eventsStore)) {
        _events?.dispose();
        _events = eventsStore == null
            ? null
            : EventsController(store: eventsStore);
      }
      final store = controller.inventoryStore;
      if (!identical(_inventory?.store, store)) {
        _inventory?.dispose();
        _inventory = store == null ? null : InventoryController(store: store);
        _catalogKey = GlobalKey<CatalogPageState>();
      }
      if (_inventory != null &&
          controller.profile != null &&
          _inventory!.snapshot == null &&
          !_inventory!.loading &&
          _inventory!.loadError == null) {
        unawaited(_inventory!.load());
      }
      final quickSalesStore = controller.quickSalesStore;
      final intakeStore = controller.stockIntakeStore;
      if (!identical(_stockIntake?.store, intakeStore)) {
        _stockIntake?.dispose();
        _stockIntake = intakeStore == null
            ? null
            : StockIntakeController(store: intakeStore);
      }
      if (_stockIntake != null &&
          controller.profile != null &&
          _stockIntake!.snapshot == null &&
          !_stockIntake!.loading &&
          _stockIntake!.loadError == null) {
        unawaited(_stockIntake!.load());
      }
      if (!identical(_quickSales?.store, quickSalesStore)) {
        _quickSales?.dispose();
        _quickSales = quickSalesStore == null
            ? null
            : QuickSalesController(store: quickSalesStore);
      }
      if (_quickSales != null &&
          controller.profile != null &&
          _quickSales!.snapshot == null &&
          !_quickSales!.loading &&
          _quickSales!.loadError == null) {
        unawaited(_quickSales!.load());
      }
      final debtorsStore = controller.debtorsStore;
      final reportsStore = controller.reportsStore;
      if (!identical(_reports?.store, reportsStore)) {
        _reports?.dispose();
        _reports = reportsStore == null
            ? null
            : ReportsController(store: reportsStore);
      }
      if (!identical(_debtors?.store, debtorsStore)) {
        _debtors?.dispose();
        _debtors = debtorsStore == null
            ? null
            : DebtorsController(store: debtorsStore);
      }
      final supplierPaymentsStore = controller.supplierPaymentsStore;
      if (!identical(_supplierPayments?.store, supplierPaymentsStore)) {
        _supplierPayments?.removeListener(_supplierPaymentsChanged);
        _supplierPayments?.dispose();
        _supplierPayments = supplierPaymentsStore == null
            ? null
            : SupplierPaymentsController(store: supplierPaymentsStore);
        _supplierWasConfirming = false;
        _supplierPayments?.addListener(_supplierPaymentsChanged);
      }
      if (_supplierPayments != null &&
          controller.profile != null &&
          _supplierPayments!.snapshot == null &&
          !_supplierPayments!.loading &&
          _supplierPayments!.loadError == null) {
        unawaited(_supplierPayments!.load());
      }
      final treasuryStore = controller.treasuryStore;
      final treasuryOperationStore = controller.treasuryOperationStore;
      if (!identical(_treasuryOperations?.store, treasuryOperationStore)) {
        _treasuryOperations?.dispose();
        _treasuryOperations = treasuryOperationStore == null
            ? null
            : TreasuryOperationController(store: treasuryOperationStore);
      }
      if (_treasuryOperations != null &&
          controller.profile != null &&
          _treasuryOperations!.snapshot == null &&
          !_treasuryOperations!.loading &&
          _treasuryOperations!.loadError == null) {
        unawaited(_treasuryOperations!.load());
      }
      if (!identical(_treasury?.store, treasuryStore)) {
        _treasury?.dispose();
        _treasury = treasuryStore == null
            ? null
            : TreasuryController(store: treasuryStore);
      }
      if (_treasury != null &&
          controller.profile != null &&
          _treasury!.snapshot == null &&
          !_treasury!.loading &&
          _treasury!.loadError == null) {
        unawaited(_treasury!.load());
      }
      if (controller.state == WorkspaceState.loading) {
        return const Scaffold(
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 24),
                Text('Preparando tu espacio de trabajo…'),
              ],
            ),
          ),
        );
      }
      if (controller.state == WorkspaceState.failed) {
        return Scaffold(
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.storage_outlined,
                      size: 40,
                      color: _forest,
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'No pudimos abrir este espacio',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Revisa la ubicación de los datos y vuelve a intentarlo.',
                    ),
                    const SizedBox(height: 16),
                    SelectableText(
                      controller.error ?? 'Error de almacenamiento.',
                    ),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: controller.initialize,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Reintentar'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }
      return LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 840;
          return Scaffold(
            body: Row(
              children: [
                if (wide)
                  SizedBox(
                    width: 230,
                    child: _Sidebar(
                      selected: _section,
                      onSelected: _selectSection,
                    ),
                  ),
                Expanded(
                  child: SafeArea(
                    child: Column(
                      children: [
                        _Header(businessName: controller.profile?.businessName),
                        Expanded(
                          child: IndexedStack(
                            index: _section,
                            alignment: Alignment.topCenter,
                            children: [
                              _scrollPage(
                                _inventory == null
                                    ? const _ModuleUnavailable()
                                    : CatalogPage(
                                        key: _catalogKey,
                                        controller: _inventory!,
                                        profile: controller.profile!,
                                        referenceStore:
                                            controller.referenceInventoryStore,
                                        onDeactivateEvent: _events == null
                                            ? null
                                            : _deactivateEvent,
                                      ),
                                wide,
                              ),
                              _scrollPage(
                                _stockIntake == null
                                    ? const _ModuleUnavailable()
                                    : PurchasesPage(
                                        key: ObjectKey(_stockIntake),
                                        controller: _stockIntake!,
                                        profile: controller.profile!,
                                      ),
                                wide,
                              ),
                              _scrollPage(_salesContent(controller), wide),
                              _scrollPage(
                                _debtors == null
                                    ? const _ModuleUnavailable()
                                    : DebtorsPage(
                                        key: ObjectKey(_debtors),
                                        controller: _debtors!,
                                        profile: controller.profile!,
                                      ),
                                wide,
                              ),
                              _scrollPage(
                                _treasury == null
                                    ? const _ModuleUnavailable()
                                    : TreasuryPage(
                                        key: ObjectKey(_treasury),
                                        controller: _treasury!,
                                        operationController:
                                            _treasuryOperations,
                                        profile: controller.profile!,
                                        legacyStore:
                                            controller.legacyTreasuryStore,
                                        supplierPaymentsPanel:
                                            _supplierPayments == null
                                            ? null
                                            : SupplierPaymentsPage(
                                                key: ObjectKey(
                                                  _supplierPayments,
                                                ),
                                                controller: _supplierPayments!,
                                                profile: controller.profile!,
                                              ),
                                      ),
                                wide,
                              ),
                              _scrollPage(
                                _events == null
                                    ? const _ModuleUnavailable()
                                    : EventsPage(
                                        key: ObjectKey(_events),
                                        controller: _events!,
                                        profile: controller.profile!,
                                      ),
                                wide,
                              ),
                              _scrollPage(
                                _reports == null
                                    ? const _ModuleUnavailable()
                                    : ReportsPage(
                                        key: ObjectKey(_reports),
                                        controller: _reports!,
                                        profile: controller.profile!,
                                      ),
                                wide,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            bottomNavigationBar: wide
                ? null
                : _CompactNavigation(
                    selected: _section,
                    onSelected: _selectSection,
                  ),
          );
        },
      );
    },
  );

  Future<void> _deactivateEvent(String id) async {
    final ok = await _events?.deactivate(id) ?? false;
    if (ok) {
      await _inventory?.load();
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_events?.error ?? 'No se pudo desactivar el evento.'),
        ),
      );
    }
  }

  Widget _scrollPage(Widget child, bool wide) => SingleChildScrollView(
    padding: EdgeInsets.all(wide ? 36 : 20),
    child: Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1050),
        child: child,
      ),
    ),
  );

  Widget _salesContent(WorkspaceController controller) {
    if (_quickSales == null) return const _ModuleUnavailable();
    return QuickSalesPage(
      key: ObjectKey(_quickSales),
      controller: _quickSales!,
      profile: controller.profile!,
    );
  }
}

class _ModuleUnavailable extends StatelessWidget {
  const _ModuleUnavailable();
  @override
  Widget build(BuildContext context) =>
      const Text('El módulo no está disponible en esta sesión.');
}

class _CompactNavigation extends StatelessWidget {
  const _CompactNavigation({required this.selected, required this.onSelected});
  final int selected;
  final ValueChanged<int> onSelected;
  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    child: SafeArea(
      top: false,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth < 600 ? 4 : _destinations.length;
          return Wrap(
            children: [
              for (var index = 0; index < _destinations.length; index++)
                SizedBox(
                  width: constraints.maxWidth / columns,
                  child: Semantics(
                    selected: selected == index,
                    button: true,
                    child: InkWell(
                      onTap: () => onSelected(index),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _destinations[index].$1,
                              color: selected == index
                                  ? _forest
                                  : Colors.black54,
                            ),
                            const SizedBox(height: 3),
                            Text(
                              _destinations[index].$2,
                              style: TextStyle(
                                fontSize: 12,
                                color: selected == index
                                    ? _forest
                                    : Colors.black54,
                                fontWeight: selected == index
                                    ? FontWeight.w600
                                    : FontWeight.normal,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    ),
  );
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.selected, required this.onSelected});
  final int selected;
  final ValueChanged<int> onSelected;
  @override
  Widget build(BuildContext context) => Material(
    color: _forest,
    child: SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(left: 12, bottom: 6),
              child: ValinorLogo(),
            ),
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                'SANCTUM',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 23,
                  letterSpacing: 2,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.only(left: 12),
              child: Text(
                'GESTIÓN COMERCIAL · 2.0',
                style: TextStyle(
                  color: _gold,
                  fontSize: 10,
                  letterSpacing: 1.2,
                ),
              ),
            ),
            const SizedBox(height: 24),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    for (var index = 0; index < _destinations.length; index++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          selected: selected == index,
                          selectedTileColor: Colors.white.withValues(
                            alpha: .12,
                          ),
                          selectedColor: Colors.white,
                          iconColor: Colors.white70,
                          textColor: Colors.white70,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          leading: Icon(_destinations[index].$1),
                          title: Text(_destinations[index].$2),
                          onTap: () => onSelected(index),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'EN DESARROLLO',
                    style: TextStyle(
                      color: _gold,
                      fontSize: 11,
                      letterSpacing: 1.2,
                    ),
                  ),
                  SizedBox(height: 6),
                  Text(
                    'Versión 0.25.0',
                    style: TextStyle(color: Colors.white60, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _Header extends StatelessWidget {
  const _Header({this.businessName});
  final String? businessName;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
    decoration: const BoxDecoration(
      color: Colors.white,
      border: Border(bottom: BorderSide(color: Color(0xFFE4E7E0))),
    ),
    child: Row(
      children: [
        const ValinorLogo(width: 40, height: 40),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            businessName ?? 'Valinor Sanctum 2.0',
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        const SizedBox(width: 12),
        const _Tag(text: 'Desarrollo', icon: Icons.science_outlined),
      ],
    ),
  );
}

class _Tag extends StatelessWidget {
  const _Tag({required this.text, required this.icon});
  final String text;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    decoration: BoxDecoration(
      color: _forest.withValues(alpha: .06),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: _forest),
        const SizedBox(width: 6),
        Text(text, style: const TextStyle(fontSize: 12, color: _forest)),
      ],
    ),
  );
}
