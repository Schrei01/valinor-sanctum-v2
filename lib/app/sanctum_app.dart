import 'dart:async';
import 'package:flutter/material.dart';
import '../features/workspace/application/workspace_controller.dart';
import '../features/inventory/application/inventory_controller.dart';
import '../features/inventory/presentation/catalog_page.dart';
import '../features/inventory/presentation/purchases_page.dart';
import '../features/sales/application/sales_controller.dart';
import '../features/sales/presentation/sales_page.dart';
import '../features/collections/application/collections_controller.dart';
import '../features/collections/presentation/collections_page.dart';

const _forest = Color(0xFF183D35);
const _gold = Color(0xFFD8BB80);
const _paper = Color(0xFFF5F5F0);

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
  int _section = 0;
  InventoryController? _inventory;
  SalesController? _sales;
  CollectionsController? _collections;

  void _selectSection(int index) {
    setState(() => _section = index);
    if (widget.controller.profile == null) return;
    if (index == 1 || index == 2) unawaited(_inventory?.load());
    if (index == 3) unawaited(_sales?.load());
    if (index == 4) unawaited(_collections?.load());
  }

  @override
  void dispose() {
    _inventory?.dispose();
    _sales?.dispose();
    _collections?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final controller = widget.controller;
      final store = controller.inventoryStore;
      if (!identical(_inventory?.store, store)) {
        _inventory?.dispose();
        _inventory = store == null ? null : InventoryController(store: store);
      }
      if (_inventory != null &&
          controller.profile != null &&
          _inventory!.snapshot == null &&
          !_inventory!.loading &&
          _inventory!.loadError == null) {
        unawaited(_inventory!.load());
      }
      final salesStore = controller.salesStore;
      if (!identical(_sales?.store, salesStore)) {
        _sales?.dispose();
        _sales = salesStore == null ? null : SalesController(store: salesStore);
      }
      if (_sales != null &&
          controller.profile != null &&
          _sales!.snapshot == null &&
          !_sales!.loading &&
          _sales!.loadError == null) {
        unawaited(_sales!.load());
      }
      final collectionsStore = controller.collectionsStore;
      if (!identical(_collections?.store, collectionsStore)) {
        _collections?.dispose();
        _collections = collectionsStore == null
            ? null
            : CollectionsController(store: collectionsStore);
      }
      if (_collections != null &&
          controller.profile != null &&
          _collections!.snapshot == null &&
          !_collections!.loading &&
          _collections!.loadError == null) {
        unawaited(_collections!.load());
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
                              _scrollPage(_Home(controller: controller), wide),
                              _scrollPage(
                                controller.profile == null
                                    ? const _ConfigureFirst()
                                    : _inventory == null
                                    ? const _ModuleUnavailable()
                                    : CatalogPage(
                                        key: ObjectKey(_inventory),
                                        controller: _inventory!,
                                        profile: controller.profile!,
                                      ),
                                wide,
                              ),
                              _scrollPage(
                                controller.profile == null
                                    ? const _ConfigureFirst()
                                    : _inventory == null
                                    ? const _ModuleUnavailable()
                                    : PurchasesPage(
                                        key: ObjectKey(_inventory),
                                        controller: _inventory!,
                                        profile: controller.profile!,
                                      ),
                                wide,
                              ),
                              _scrollPage(
                                controller.profile == null
                                    ? const _ConfigureFirst()
                                    : _sales == null
                                    ? const _ModuleUnavailable()
                                    : SalesPage(
                                        key: ObjectKey(_sales),
                                        controller: _sales!,
                                        profile: controller.profile!,
                                      ),
                                wide,
                              ),
                              _scrollPage(
                                controller.profile == null
                                    ? const _ConfigureFirst()
                                    : _collections == null
                                    ? const _ModuleUnavailable()
                                    : CollectionsPage(
                                        key: ObjectKey(_collections),
                                        controller: _collections!,
                                        profile: controller.profile!,
                                      ),
                                wide,
                              ),
                              _scrollPage(
                                _System(controller: controller),
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
                : NavigationBar(
                    selectedIndex: _section,
                    onDestinationSelected: _selectSection,
                    destinations: const [
                      NavigationDestination(
                        icon: Icon(Icons.home_outlined),
                        label: 'Inicio',
                      ),
                      NavigationDestination(
                        icon: Icon(Icons.inventory_2_outlined),
                        label: 'Catálogo',
                      ),
                      NavigationDestination(
                        icon: Icon(Icons.local_shipping_outlined),
                        label: 'Compras',
                      ),
                      NavigationDestination(
                        icon: Icon(Icons.point_of_sale_outlined),
                        label: 'Ventas',
                      ),
                      NavigationDestination(
                        icon: Icon(Icons.payments_outlined),
                        label: 'Cobros',
                      ),
                      NavigationDestination(
                        icon: Icon(Icons.settings_outlined),
                        label: 'Sistema',
                      ),
                    ],
                  ),
          );
        },
      );
    },
  );

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
}

class _ConfigureFirst extends StatelessWidget {
  const _ConfigureFirst();
  @override
  Widget build(BuildContext context) => const Card(
    child: Padding(
      padding: EdgeInsets.all(28),
      child: Text(
        'Primero configura tu espacio de trabajo en Inicio para abrir catálogo, compras, ventas y cobros.',
      ),
    ),
  );
}

class _ModuleUnavailable extends StatelessWidget {
  const _ModuleUnavailable();
  @override
  Widget build(BuildContext context) =>
      const Text('El módulo no está disponible en esta sesión.');
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
              child: Icon(Icons.local_library_outlined, color: _gold, size: 34),
            ),
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                'VALINOR\nSANCTUM',
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
            const SizedBox(height: 44),
            for (final entry in [
              (0, Icons.home_outlined, 'Inicio'),
              (1, Icons.inventory_2_outlined, 'Catálogo'),
              (2, Icons.local_shipping_outlined, 'Compras'),
              (3, Icons.point_of_sale_outlined, 'Ventas'),
              (4, Icons.payments_outlined, 'Cobros'),
              (5, Icons.settings_outlined, 'Sistema'),
            ])
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  selected: selected == entry.$1,
                  selectedTileColor: Colors.white.withValues(alpha: .12),
                  selectedColor: Colors.white,
                  iconColor: Colors.white70,
                  textColor: Colors.white70,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  leading: Icon(entry.$2),
                  title: Text(entry.$3),
                  onTap: () => onSelected(entry.$1),
                ),
              ),
            const Spacer(),
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
                    'Versión 0.4.0',
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

class _Home extends StatelessWidget {
  const _Home({required this.controller});
  final WorkspaceController controller;
  @override
  Widget build(BuildContext context) {
    final profile = controller.profile;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _Eyebrow('ESPACIO DE TRABAJO'),
        const SizedBox(height: 12),
        Text(
          profile == null ? 'Prepara tu ludoteca' : 'Tu espacio está preparado',
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: _forest,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          profile == null
              ? 'Configura la identidad y la precisión monetaria de este nuevo espacio.'
              : 'La configuración se conserva en una base local independiente.',
          style: const TextStyle(color: Color(0xFF65716A), height: 1.6),
        ),
        const SizedBox(height: 28),
        if (profile == null)
          _ProfileForm(controller: controller)
        else
          Card(
            child: Padding(
              padding: const EdgeInsets.all(26),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.check_circle_outline,
                    color: _forest,
                    size: 32,
                  ),
                  const SizedBox(height: 18),
                  Text(
                    profile.businessName,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      _Tag(
                        text: profile.currencyCode,
                        icon: Icons.payments_outlined,
                      ),
                      _Tag(
                        text: '${profile.moneyScale} decimales',
                        icon: Icons.calculate_outlined,
                      ),
                      const _Tag(text: 'Bogotá', icon: Icons.schedule_outlined),
                    ],
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Ya puedes organizar el catálogo, recibir compras, confirmar ventas a crédito y registrar cobros desde el menú.',
                    style: TextStyle(color: Color(0xFF65716A)),
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 30),
        const _Eyebrow('MÓDULOS'),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 720 ? 2 : 1;
            final width = (constraints.maxWidth - (columns - 1) * 16) / columns;
            return Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                for (final module in [
                  (
                    Icons.inventory_2_outlined,
                    'Catálogo e inventario',
                    'Productos, proveedores y recepción de compras a crédito. Ajustes pendientes.',
                    'Disponible',
                  ),
                  (
                    Icons.point_of_sale_outlined,
                    'Ventas y cuentas abiertas',
                    'Cuentas guardadas, entregas a crédito, cobros completos y abonos.',
                    'Disponible',
                  ),
                  (
                    Icons.account_balance_wallet_outlined,
                    'Caja y movimientos',
                    'Gastos, transferencias y conciliación.',
                    'Pendiente',
                  ),
                  (
                    Icons.insights_outlined,
                    'Reportes y análisis',
                    'Indicadores sustentados en operaciones.',
                    'Pendiente',
                  ),
                ])
                  SizedBox(
                    width: width,
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(22),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(module.$1, color: _forest),
                            const SizedBox(height: 16),
                            Text(
                              module.$2,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              module.$3,
                              style: const TextStyle(
                                color: Color(0xFF65716A),
                                height: 1.5,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              module.$4,
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF65716A),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _ProfileForm extends StatefulWidget {
  const _ProfileForm({required this.controller});
  final WorkspaceController controller;
  @override
  State<_ProfileForm> createState() => _ProfileFormState();
}

class _ProfileFormState extends State<_ProfileForm> {
  final _key = GlobalKey<FormState>();
  final _name = TextEditingController();
  int _scale = 2;
  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(26),
      child: Form(
        key: _key,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Configura tu espacio',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 20),
            ),
            const SizedBox(height: 24),
            TextFormField(
              key: const Key('business-name'),
              controller: _name,
              enabled: !widget.controller.busy,
              maxLength: 80,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Nombre de la ludoteca',
                hintText: 'Escribe el nombre del negocio',
              ),
              validator: (value) => value == null || value.trim().length < 2
                  ? 'Escribe un nombre de al menos 2 caracteres.'
                  : null,
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<int>(
              isExpanded: true,
              key: const Key('money-scale'),
              initialValue: _scale,
              decoration: const InputDecoration(
                labelText: 'Precisión para pesos colombianos (COP)',
              ),
              items: const [
                DropdownMenuItem(
                  value: 0,
                  child: Text('Pesos enteros · 0 decimales'),
                ),
                DropdownMenuItem(
                  value: 2,
                  child: Text('Pesos y centavos · 2 decimales'),
                ),
              ],
              onChanged: widget.controller.busy
                  ? null
                  : (value) => setState(() => _scale = value!),
            ),
            const SizedBox(height: 16),
            const Text(
              'La precisión se fija antes de registrar operaciones. Zona horaria: Bogotá.',
              style: TextStyle(color: Color(0xFF65716A), height: 1.5),
            ),
            const SizedBox(height: 20),
            if (widget.controller.error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(
                  widget.controller.error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            FilledButton.icon(
              key: const Key('create-profile'),
              onPressed: widget.controller.busy
                  ? null
                  : () async {
                      if (_key.currentState!.validate()) {
                        await widget.controller.createProfile(
                          businessName: _name.text,
                          moneyScale: _scale,
                        );
                      }
                    },
              icon: Icon(
                widget.controller.busy
                    ? Icons.hourglass_empty
                    : Icons.arrow_forward,
              ),
              label: Text(
                widget.controller.busy
                    ? 'Guardando…'
                    : 'Crear espacio de trabajo',
              ),
              style: FilledButton.styleFrom(
                backgroundColor: _forest,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 20,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _System extends StatelessWidget {
  const _System({required this.controller});
  final WorkspaceController controller;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const _Eyebrow('SISTEMA'),
      const SizedBox(height: 12),
      Text(
        'Almacenamiento y diagnóstico',
        style: Theme.of(
          context,
        ).textTheme.headlineMedium?.copyWith(color: _forest),
      ),
      const SizedBox(height: 12),
      const Text(
        'Comprueba el estado del archivo exclusivo de este espacio.',
        style: TextStyle(color: Color(0xFF65716A)),
      ),
      const SizedBox(height: 28),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(26),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Perfil: ${controller.profileId}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 16),
              const Text(
                'Ubicación de la base de datos',
                style: TextStyle(color: Color(0xFF65716A)),
              ),
              const SizedBox(height: 8),
              SelectableText(
                controller.databasePath,
                key: const Key('database-path'),
              ),
              const Divider(height: 36),
              _HealthRow(
                label: 'Integridad SQLite',
                ok: controller.health['integrityOk'] == true,
              ),
              _HealthRow(
                label: 'Relaciones protegidas',
                ok: controller.health['foreignKeysEnabled'] == true,
              ),
              _HealthRow(
                label: 'Esquema verificado',
                ok: controller.health['schemaChecksumVerified'] == true,
              ),
              _HealthRow(
                label: 'Migración verificada',
                ok: controller.health['migrationChecksumVerified'] == true,
              ),
              const SizedBox(height: 16),
              Text(
                'Versión del esquema: ${controller.health['schemaVersion'] ?? '—'}',
              ),
              const SizedBox(height: 24),
              if (controller.error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text(
                    controller.error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              OutlinedButton.icon(
                onPressed: controller.busy ? null : controller.verifyStorage,
                icon: const Icon(Icons.verified_outlined),
                label: Text(
                  controller.busy ? 'Verificando…' : 'Volver a verificar',
                ),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 24),
      const Text(
        'Entorno de desarrollo. Catálogo, compras, ventas a crédito y cobros disponibles. Pagos a proveedores, arqueo, usuarios e importación aún están pendientes.',
        style: TextStyle(color: Color(0xFF65716A), height: 1.5),
      ),
    ],
  );
}

class _HealthRow extends StatelessWidget {
  const _HealthRow({required this.label, required this.ok});
  final String label;
  final bool ok;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(
      children: [
        Icon(
          ok ? Icons.check_circle_outline : Icons.error_outline,
          size: 21,
          color: ok ? _forest : Theme.of(context).colorScheme.error,
        ),
        const SizedBox(width: 12),
        Expanded(child: Text(label)),
        Text(ok ? 'Correcto' : 'Revisar', style: const TextStyle(fontSize: 12)),
      ],
    ),
  );
}

class _Eyebrow extends StatelessWidget {
  const _Eyebrow(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w600,
      letterSpacing: 1.6,
      color: Color(0xFF65716A),
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
