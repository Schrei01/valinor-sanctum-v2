import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:valinor_sanctum_2/core/infrastructure/app_config.dart';
import 'package:valinor_sanctum_2/features/treasury/application/treasury_controller.dart';
import 'package:valinor_sanctum_2/features/treasury/application/treasury_operation_controller.dart';
import 'package:valinor_sanctum_2/features/treasury/domain/treasury_operation_store.dart';
import 'package:valinor_sanctum_2/features/treasury/domain/treasury_store.dart';
import 'package:valinor_sanctum_2/features/treasury/presentation/treasury_page.dart';
import 'package:valinor_sanctum_2/features/workspace/domain/business_profile.dart';

import '../support/fake_treasury_operation_store.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final fonts = p.join(
      AppConfig.repositoryRootPath,
      '.tooling',
      'flutter',
      'bin',
      'cache',
      'artifacts',
      'material_fonts',
    );
    for (final family in {
      'Roboto': ['roboto-regular.ttf', 'roboto-medium.ttf', 'roboto-bold.ttf'],
      'MaterialIcons': ['materialicons-regular.otf'],
    }.entries) {
      final loader = FontLoader(family.key);
      for (final name in family.value) {
        loader.addFont(
          Future.value(
            ByteData.sublistView(await File(p.join(fonts, name)).readAsBytes()),
          ),
        );
      }
      await loader.load();
    }
  });

  final profile = BusinessProfile(
    profileId: 'treasury-ui',
    businessName: 'Tienda sintética',
    currencyCode: 'COP',
    moneyScale: 2,
    timezone: 'America/Bogota',
    createdAtUtc: DateTime.utc(2026, 10, 20),
  );
  late FakeTreasuryOperationStore store;
  late TreasuryOperationController controller;
  late _LiveProjection projection;
  late TreasuryController treasury;
  setUp(() {
    store = FakeTreasuryOperationStore();
    controller = TreasuryOperationController(store: store);
    projection = _LiveProjection(store);
    treasury = TreasuryController(store: projection);
  });
  tearDown(() {
    controller.dispose();
    treasury.dispose();
  });

  Future<void> open(
    WidgetTester tester, {
    Size size = const Size(1120, 1050),
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await controller.load();
    await treasury.load();
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true),
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: TreasuryPage(
              controller: treasury,
              operationController: controller,
              profile: profile,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    addTearDown(() async => tester.pumpWidget(const SizedBox()));
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> enter(WidgetTester tester, String key, String value) async {
    final finder = find.byKey(Key(key));
    await tester.ensureVisible(finder);
    await tester.enterText(finder, value);
    await tester.pumpAndSettle();
  }

  Future<void> choose(WidgetTester tester, String key, String label) async {
    await tap(tester, find.byKey(Key(key)));
    await tap(tester, find.text(label).last);
  }

  String field(WidgetTester tester, String key) =>
      tester.widget<TextFormField>(find.byKey(Key(key))).controller!.text;
  String? balance(WidgetTester tester, String role) =>
      tester.widget<Text>(find.byKey(Key('treasury-amount-$role'))).data;
  Future<void> submit(WidgetTester tester) =>
      tap(tester, find.byKey(const Key('treasury-operation-submit')));
  Finder destination() => find.descendant(
    of: find.byKey(const Key('treasury-operation-destination')),
    matching: find.byType(DropdownButtonFormField<String>),
  );

  DropdownButton<String> dropdown(WidgetTester tester, Finder field) =>
      tester.widget<DropdownButton<String>>(
        find.descendant(
          of: field,
          matching: find.byType(DropdownButton<String>),
        ),
      );

  testWidgets(
    'expense uses the selected account and refreshes dashboard balances',
    (tester) async {
      await open(tester);
      final previousLoads = projection.loadCalls;
      await tap(tester, find.byKey(const Key('treasury-register-expense')));
      final source = dropdown(
        tester,
        find.byKey(const Key('treasury-operation-source')),
      );
      expect(source.items!.map((item) => item.value), ['cash', 'nequi']);
      expect(
        find.byKey(const Key('treasury-operation-destination')),
        findsNothing,
      );
      await choose(tester, 'treasury-operation-source', 'Nequi');
      await enter(tester, 'treasury-operation-amount', '123,45');
      await choose(tester, 'treasury-operation-reason', 'Aseo');
      await enter(tester, 'treasury-operation-note', 'Insumos de limpieza');
      await submit(tester);
      expect(find.byType(AlertDialog), findsNothing);
      final command = store.preparedCommands.single;
      expect(command.kind, TreasuryOperationKind.expense);
      expect(command.sourceAccountId, 'nequi');
      expect(command.destinationAccountId, isNull);
      expect(command.amountMinor, 12345);
      expect(command.reason, 'Aseo');
      expect(command.note, 'Insumos de limpieza');
      expect(command.occurredAtUtc.isUtc, isTrue);
      expect(balance(tester, 'cash'), 'COP 1.000,00');
      expect(balance(tester, 'nequi'), 'COP 376,55');
      expect(balance(tester, 'reserve'), 'COP -200,00');
      expect(balance(tester, 'total'), 'COP 1.376,55');
      expect(projection.loadCalls, greaterThan(previousLoads));
      expect(find.textContaining('Gasto registrado.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'transfer can fund negative reserve and refreshes available total',
    (tester) async {
      await open(tester);
      await tap(tester, find.byKey(const Key('treasury-transfer')));
      expect(find.byKey(const Key('treasury-operation-reason')), findsNothing);
      expect(dropdown(tester, destination()).items!.map((item) => item.value), [
        'nequi',
        'reserve',
      ]);
      await choose(tester, 'treasury-operation-destination', 'Caja mayor');
      await enter(tester, 'treasury-operation-amount', '200,00');
      await enter(tester, 'treasury-operation-note', 'Reserva del día');
      await submit(tester);
      final command = store.preparedCommands.single;
      expect(command.kind, TreasuryOperationKind.transfer);
      expect(command.sourceAccountId, 'cash');
      expect(command.destinationAccountId, 'reserve');
      expect(command.amountMinor, 20000);
      expect(command.reason, 'Transferencia');
      expect(balance(tester, 'cash'), 'COP 800,00');
      expect(balance(tester, 'nequi'), 'COP 500,00');
      expect(balance(tester, 'reserve'), 'COP 0,00');
      expect(balance(tester, 'total'), 'COP 1.300,00');
      expect(
        store.accounts.fold<int>(0, (sum, a) => sum + a.balanceMinor),
        130000,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'expense validates amount and funds while Otro observation stays optional',
    (tester) async {
      await open(tester);
      await tap(tester, find.byKey(const Key('treasury-register-expense')));
      await submit(tester);
      expect(store.preparedCommands, isEmpty);
      await enter(tester, 'treasury-operation-amount', '0');
      await submit(tester);
      expect(find.text('Escribe un valor mayor que cero.'), findsOneWidget);
      await enter(tester, 'treasury-operation-amount', '2.000,00');
      await submit(tester);
      expect(find.text('El saldo de Caja no alcanza.'), findsOneWidget);
      await enter(tester, 'treasury-operation-amount', '25,00');
      await choose(tester, 'treasury-operation-reason', 'Otro');
      expect(store.preparedCommands, isEmpty);
      expect(find.text('Observación (opcional)'), findsOneWidget);
      await submit(tester);
      expect(store.preparedCommands.single.reason, 'Otro');
      expect(store.preparedCommands.single.note, isNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'changing source clears matching destination and negative source cannot spend',
    (tester) async {
      await open(tester);
      await tap(tester, find.byKey(const Key('treasury-transfer')));
      await choose(tester, 'treasury-operation-destination', 'Nequi');
      await choose(tester, 'treasury-operation-source', 'Nequi');
      expect(
        tester
            .widget<DropdownButtonFormField<String>>(destination())
            .initialValue,
        isNull,
      );
      expect(
        dropdown(
          tester,
          destination(),
        ).items!.any((item) => item.value == 'nequi'),
        isFalse,
      );
      await enter(tester, 'treasury-operation-amount', '25,00');
      await submit(tester);
      expect(
        find.text('Elige una cuenta de destino distinta.'),
        findsOneWidget,
      );
      await choose(tester, 'treasury-operation-source', 'Caja mayor');
      await choose(tester, 'treasury-operation-destination', 'Caja');
      await submit(tester);
      expect(find.text('El saldo de Caja mayor no alcanza.'), findsOneWidget);
      expect(store.preparedCommands, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'unknown result locks exact dialog values and retries one identity',
    (tester) async {
      store.confirmFailure = StateError('response lost');
      store.commitBeforeConfirmFailure = true;
      await open(tester);
      await tap(tester, find.byKey(const Key('treasury-register-expense')));
      await enter(tester, 'treasury-operation-amount', '12,34');
      await enter(tester, 'treasury-operation-note', 'Detalle conservado');
      await submit(tester);
      final command = store.preparedCommands.single;
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(field(tester, 'treasury-operation-amount'), '12,34');
      expect(field(tester, 'treasury-operation-note'), 'Detalle conservado');
      expect(
        tester
            .widget<TextFormField>(
              find.byKey(const Key('treasury-operation-amount')),
            )
            .enabled,
        isFalse,
      );
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const Key('treasury-operation-submit')),
            )
            .onPressed,
        isNull,
      );
      expect(store.results, hasLength(1));
      await tap(tester, find.text('Cerrar'));
      expect(
        find.byKey(ValueKey('treasury-pending-${command.commandId}')),
        findsOneWidget,
      );
      await tap(tester, find.text('Reintentar'));
      expect(store.confirmedCalls, [command.commandId, command.commandId]);
      expect(store.results, hasLength(1));
      expect(controller.pendingOperations, isEmpty);
      expect(balance(tester, 'cash'), 'COP 987,66');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'reopened prepared request is available for retry before any new form',
    (tester) async {
      final command = TreasuryOperationCommand(
        commandId: 'recovered-expense',
        kind: TreasuryOperationKind.expense,
        sourceAccountId: 'cash',
        amountMinor: 2500,
        reason: 'Servicios',
        note: 'Solicitud guardada',
        occurredAtUtc: DateTime.utc(2026, 10, 20),
      );
      store.pending.add(
        PreparedTreasuryOperation(
          command: command,
          status: 'prepared',
          preparedAtUtc: command.occurredAtUtc,
          sourceAccountName: 'Caja',
        ),
      );
      await open(tester);
      expect(find.text('Gasto pendiente de confirmar'), findsOneWidget);
      expect(find.text('Solicitud guardada'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const Key('treasury-register-expense')),
            )
            .onPressed,
        isNull,
      );
      await tap(tester, find.text('Reintentar'));
      expect(store.preparedCommands, isEmpty);
      expect(store.confirmedCalls, ['recovered-expense']);
      expect(store.results, hasLength(1));
      expect(balance(tester, 'cash'), 'COP 975,00');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'rejected request opens a prefilled correction and uses a fresh identity',
    (tester) async {
      final command = TreasuryOperationCommand(
        commandId: 'rejected-transfer',
        kind: TreasuryOperationKind.transfer,
        sourceAccountId: 'cash',
        destinationAccountId: 'reserve',
        amountMinor: 20000,
        reason: 'Transferencia',
        note: 'Corregir importe',
        occurredAtUtc: DateTime.utc(2026, 10, 20),
      );
      store.pending.add(
        PreparedTreasuryOperation(
          command: command,
          status: 'rejected',
          preparedAtUtc: command.occurredAtUtc,
          sourceAccountName: 'Caja',
          destinationAccountName: 'Caja mayor',
          rejectionReason: 'El saldo cambió.',
        ),
      );
      await open(tester);
      await tap(tester, find.text('Corregir'));
      expect(store.discardedIds, ['rejected-transfer']);
      expect(field(tester, 'treasury-operation-amount'), '200,00');
      expect(field(tester, 'treasury-operation-note'), 'Corregir importe');
      expect(
        tester
            .widget<DropdownButtonFormField<String>>(destination())
            .initialValue,
        'reserve',
      );
      await enter(tester, 'treasury-operation-amount', '100,00');
      await submit(tester);
      expect(store.preparedCommands.single.commandId, isNot(command.commandId));
      expect(store.preparedCommands.single.amountMinor, 10000);
      expect(store.results, hasLength(1));
      expect(balance(tester, 'cash'), 'COP 900,00');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('failed account load blocks operations until refresh succeeds', (
    tester,
  ) async {
    store.loadFailure = StateError('read unavailable');
    await open(tester);
    expect(
      find.byKey(const Key('treasury-operation-load-error')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const Key('treasury-register-expense')),
          )
          .onPressed,
      isNull,
    );
    store.loadFailure = null;
    await controller.load();
    await tester.pumpAndSettle();
    await tap(tester, find.byKey(const Key('treasury-register-expense')));
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(store.preparedCommands, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'confirmation queues a dashboard refresh after an older read finishes',
    (tester) async {
      await open(tester);
      await tap(tester, find.byKey(const Key('treasury-register-expense')));
      await enter(tester, 'treasury-operation-amount', '25,00');
      final oldSnapshot = projection.current;
      final previousLoads = projection.loadCalls;
      final gate = projection.pendingLoad = Completer<TreasurySnapshot>();
      final oldRead = treasury.load();
      await tester.pump();
      await tester.tap(find.byKey(const Key('treasury-operation-submit')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(treasury.loading, isTrue);
      projection.pendingLoad = null;
      gate.complete(oldSnapshot);
      await oldRead;
      await tester.pumpAndSettle();
      expect(projection.loadCalls, greaterThanOrEqualTo(previousLoads + 2));
      expect(balance(tester, 'cash'), 'COP 975,00');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('both forms fit a narrow window and cancel without posting', (
    tester,
  ) async {
    await open(tester, size: const Size(400, 900));
    await tap(tester, find.byKey(const Key('treasury-register-expense')));
    await choose(tester, 'treasury-operation-reason', 'Otro');
    await enter(tester, 'treasury-operation-note', 'Detalle sintético');
    await tap(tester, find.text('Cancelar'));
    await tap(tester, find.byKey(const Key('treasury-transfer')));
    await choose(tester, 'treasury-operation-destination', 'Caja mayor');
    await enter(tester, 'treasury-operation-amount', '50,00');
    await tap(tester, find.text('Cancelar'));
    expect(find.byType(AlertDialog), findsNothing);
    expect(store.preparedCommands, isEmpty);
    expect(store.results, isEmpty);
    expect(tester.takeException(), isNull);
  });
}

class _LiveProjection implements TreasuryStore {
  _LiveProjection(this.operations);
  final FakeTreasuryOperationStore operations;
  int loadCalls = 0;
  Completer<TreasurySnapshot>? pendingLoad;
  TreasurySnapshot get current => TreasurySnapshot(
    accounts: operations.accounts,
    receivablesMinor: 50000,
    movements: const [],
  );
  @override
  Future<void> ensureDefaults() async {}
  @override
  Future<TreasurySnapshot> load() async {
    loadCalls++;
    final pending = pendingLoad;
    if (pending != null) return pending.future;
    return current;
  }
}
