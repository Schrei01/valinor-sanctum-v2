import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:valinor_sanctum_2/core/infrastructure/app_config.dart';
import 'package:valinor_sanctum_2/features/collections/domain/collections_store.dart';
import 'package:valinor_sanctum_2/features/supplier_payments/domain/supplier_payments_store.dart';
import 'package:valinor_sanctum_2/features/supplier_payments/presentation/supplier_payments_page.dart';
import 'package:valinor_sanctum_2/features/supplier_payments/application/supplier_payments_controller.dart';
import 'package:valinor_sanctum_2/features/workspace/domain/business_profile.dart';
import '../support/fake_supplier_payments_store.dart';

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
      for (final file in family.value) {
        loader.addFont(
          Future.value(
            ByteData.sublistView(await File(p.join(fonts, file)).readAsBytes()),
          ),
        );
      }
      await loader.load();
    }
  });
  FakeSupplierPaymentsStore store({bool configured = true}) =>
      FakeSupplierPaymentsStore()
        ..accounts.addAll(
          configured
              ? [
                  const CollectionAccount(
                    id: 'cash',
                    name: 'Caja sintética',
                    kind: 'cash',
                    balanceMinor: 10000,
                  ),
                ]
              : [],
        )
        ..methods.addAll(
          configured
              ? [
                  const CollectionMethod(
                    id: 'cash-method',
                    code: 'EFECTIVO',
                    name: 'Efectivo',
                  ),
                ]
              : [],
        )
        ..payables.add(
          PayableSummary(
            payableId: 'payable',
            purchaseDocumentId: 'purchase',
            label: 'Compra sintética',
            supplierName: 'Proveedor sintético',
            issuedAtUtc: DateTime.utc(2026, 10, 19),
            dueDate: '2099-12-31',
            initialMinor: 10000,
            paidMinor: 0,
            remainingMinor: 10000,
          ),
        );

  Future<void> open(
    WidgetTester tester,
    FakeSupplierPaymentsStore fake, {
    Size size = const Size(1120, 1000),
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final profile = BusinessProfile(
      profileId: 'test',
      businessName: 'Ludoteca sintética',
      currencyCode: 'COP',
      moneyScale: 2,
      timezone: 'America/Bogota',
      createdAtUtc: DateTime.utc(2026, 10, 19),
    );
    // The historical component is exercised independently; it is no longer a
    // destination or an embedded panel in the application's Treasury page.
    final controller = SupplierPaymentsController(store: fake);
    await controller.load();
    await tester.pumpWidget(
      RepaintBoundary(
        key: const Key('supplier-payments-preview'),
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: SupplierPaymentsPage(
                controller: controller,
                profile: profile,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    });
  }

  Finder keyed(String prefix) => find.byWidgetPredicate(
    (w) =>
        w.key is ValueKey<String> &&
        (w.key! as ValueKey<String>).value.startsWith(prefix),
  );
  Future<void> tap(WidgetTester tester, Finder target) async {
    await tester.ensureVisible(target);
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  Future<void> enter(WidgetTester tester, Finder target, String value) async {
    await tester.ensureVisible(target);
    await tester.enterText(target, value);
    await tester.pumpAndSettle();
  }

  Future<void> fill(WidgetTester tester, String amount) async {
    await tap(tester, keyed('supplier-payment-account-').first);
    await tap(tester, find.textContaining('Caja sintética · COP').last);
    await tap(tester, keyed('supplier-payment-method-').first);
    await tap(tester, find.text('Efectivo').last);
    await enter(tester, keyed('supplier-payment-amount-').first, amount);
  }

  Future<void> confirm(WidgetTester tester) async {
    await tap(tester, find.byKey(const Key('confirm-supplier-payment')));
    await tap(tester, find.byKey(const Key('accept-supplier-payment')));
  }

  Future<void> capture(WidgetTester tester) async {
    if (!const bool.fromEnvironment(
      'SANCTUM_CAPTURE_SUPPLIER_PAYMENTS_PREVIEW',
    )) {
      return;
    }
    await tester.binding.setSurfaceSize(const Size(1120, 2400));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Pagos a proveedores').last);
    await tester.pumpAndSettle();
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const Key('supplier-payments-preview')),
    );
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 1);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await File(
        p.join(
          AppConfig.repositoryRootPath,
          'docs',
          'images',
          'supplier-payments-credit.png',
        ),
      ).writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  testWidgets(
    'configuration explains funding and never fabricates opening money',
    (tester) async {
      final fake = store(configured: false);
      await open(tester, fake);
      expect(
        find.textContaining('Consulta las cuentas y sus saldos en Tesorería'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const Key('confirm-supplier-payment')),
            )
            .onPressed,
        isNull,
      );
      expect(fake.payments, isEmpty);
      expect(fake.accounts, isEmpty);
      expect(
        find.byKey(const Key('supplier-payment-account-name')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('split payment subtracts exactly from both funding accounts', (
    tester,
  ) async {
    final fake = store();
    fake.accounts.add(
      const CollectionAccount(
        id: 'mobile',
        name: 'Billetera sintética',
        kind: 'mobile',
        balanceMinor: 4000,
      ),
    );
    await open(tester, fake);
    await fill(tester, '65,00');
    await tap(tester, find.byKey(const Key('add-supplier-payment-part')));
    await tap(tester, keyed('supplier-payment-account-').at(1));
    await tap(tester, find.textContaining('Billetera sintética · COP').last);
    await tap(tester, keyed('supplier-payment-method-').at(1));
    await tap(tester, find.text('Efectivo').last);
    await enter(tester, keyed('supplier-payment-amount-').at(1), '35,00');
    await confirm(tester);
    expect(fake.payments.single.totalMinor, 10000);
    expect(fake.payments.single.parts, hasLength(2));
    expect(
      fake.accounts.firstWhere((item) => item.id == 'cash').balanceMinor,
      3500,
    );
    expect(
      fake.accounts.firstWhere((item) => item.id == 'mobile').balanceMinor,
      500,
    );
    expect(fake.payables.single.remainingMinor, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'repeated parts from the same account are checked against their combined amount',
    (tester) async {
      final fake = store();
      fake.accounts[0] = const CollectionAccount(
        id: 'cash',
        name: 'Caja sintética',
        kind: 'cash',
        balanceMinor: 6000,
      );
      await open(tester, fake);
      await fill(tester, '40,00');
      await tap(tester, find.byKey(const Key('add-supplier-payment-part')));
      await tap(tester, keyed('supplier-payment-account-').at(1));
      await tap(tester, find.textContaining('Caja sintética · COP').last);
      await tap(tester, keyed('supplier-payment-method-').at(1));
      await tap(tester, find.text('Efectivo').last);
      await enter(tester, keyed('supplier-payment-amount-').at(1), '40,00');
      expect(
        find.textContaining('Saldo insuficiente en Caja sintética'),
        findsOneWidget,
      );
      await tap(tester, find.byKey(const Key('confirm-supplier-payment')));
      expect(find.byKey(const Key('accept-supplier-payment')), findsNothing);
      expect(fake.preparedInputs, isEmpty);
      expect(fake.accounts.single.balanceMinor, 6000);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('unavailable funds are shown but cannot be used for a payment', (
    tester,
  ) async {
    final fake = store();
    fake.accounts[0] = const CollectionAccount(
      id: 'cash',
      name: 'Caja sintética',
      kind: 'cash',
      balanceMinor: 10000,
      isAvailable: false,
    );
    await open(tester, fake);
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const Key('confirm-supplier-payment')),
          )
          .onPressed,
      isNull,
    );
    await tap(tester, find.byKey(const Key('supplier-payment-balances')));
    expect(
      find.textContaining('No disponible · Saldo registrado: COP 100,00'),
      findsOneWidget,
    );
    expect(fake.preparedInputs, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('partial and final receipt use the exact remaining balance', (
    tester,
  ) async {
    final fake = store();
    await open(tester, fake);
    await fill(tester, '40,00');
    await confirm(tester);
    expect(fake.payables.single.paidMinor, 4000);
    expect(
      tester
          .widget<Text>(
            find.byKey(const Key('supplier-payment-current-balance')),
          )
          .data,
      'Pendiente: COP 60,00',
    );
    await capture(tester);
    await fill(tester, '1,00');
    await tap(tester, find.byKey(const Key('fill-supplier-payment-total')));
    expect(
      tester.widget<Text>(find.byKey(const Key('supplier-payment-total'))).data,
      'Total del pago: COP 60,00',
    );
    await confirm(tester);
    expect(fake.payables.single.remainingMinor, 0);
    expect(fake.accounts.single.balanceMinor, 0);
    expect(fake.payments, hasLength(2));
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'uncertain supplier-payment is recovered after reopening and retries the same identity',
    (tester) async {
      final fake = store()..confirmationFailure = StateError('unknown result');
      await open(tester, fake);
      await fill(tester, '40,00');
      await confirm(tester);
      final identity = fake.preparedInputs.single.commandId;
      expect(fake.payments, isEmpty);
      expect(
        tester
            .widget<TextFormField>(keyed('supplier-payment-amount-').first)
            .enabled,
        isFalse,
      );
      await tester.pumpWidget(const SizedBox());
      await open(tester, fake);
      expect(find.text('Reintentar el mismo pago'), findsOneWidget);
      fake.confirmationFailure = null;
      await tap(tester, find.byKey(const Key('confirm-supplier-payment')));
      expect(fake.confirmedIds, [identity, identity]);
      expect(fake.payments, hasLength(1));
      expect(fake.payables.single.remainingMinor, 6000);
    },
  );
  testWidgets(
    'lost commit reply and failed refresh never enable another supplier-payment before recovery',
    (tester) async {
      final fake = store()
        ..confirmationFailure = StateError('lost reply')
        ..commitBeforeConfirmationFailure = true;
      await open(tester, fake);
      await fill(tester, '40,00');
      await confirm(tester);
      final identity = fake.preparedInputs.single.commandId;
      expect(fake.payments, hasLength(1));
      fake.confirmationFailure = null;
      fake.loadFailure = StateError('read failed');
      await tap(tester, find.byKey(const Key('confirm-supplier-payment')));
      expect(fake.confirmedIds, [identity, identity]);
      expect(fake.payments, hasLength(1));
      expect(
        tester
            .widget<TextFormField>(keyed('supplier-payment-amount-').first)
            .enabled,
        isFalse,
      );
      fake.loadFailure = null;
      await tap(
        tester,
        find
            .descendant(
              of: find.byType(SupplierPaymentsPage),
              matching: find.text('Actualizar'),
            )
            .first,
      );
      expect(fake.payables.single.remainingMinor, 6000);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'refresh of a committed unknown result clears the previous amount',
    (tester) async {
      final fake = store()
        ..confirmationFailure = StateError('lost commit reply')
        ..commitBeforeConfirmationFailure = true;
      await open(tester, fake);
      await fill(tester, '40,00');
      await confirm(tester);
      expect(fake.payments, hasLength(1));
      expect(
        tester
            .widget<TextFormField>(keyed('supplier-payment-amount-').first)
            .enabled,
        isFalse,
      );
      await tap(
        tester,
        find
            .descendant(
              of: find.byType(SupplierPaymentsPage),
              matching: find.text('Actualizar'),
            )
            .first,
      );
      final amount = tester.widget<TextFormField>(
        keyed('supplier-payment-amount-').first,
      );
      expect(amount.enabled, isTrue);
      expect(amount.controller!.text, isEmpty);
      expect(find.text('Reintentar el mismo pago'), findsNothing);
      expect(fake.payables.single.remainingMinor, 6000);
      expect(fake.preparedInputs, hasLength(1));
      expect(fake.payments, hasLength(1));
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'historical supplier-payment can be corrected in the narrow standalone component',
    (tester) async {
      final fake = store()
        ..confirmationFailure = const SupplierPaymentsValidationException(
          'Saldo cambió',
        );
      await open(tester, fake, size: const Size(400, 900));
      await fill(tester, '40,00');
      expect(
        tester
            .widget<TextFormField>(keyed('supplier-payment-amount-').first)
            .controller!
            .text,
        '40,00',
      );
      await confirm(tester);
      expect(fake.pending.single.status, 'rejected');
      fake.confirmationFailure = null;
      await tap(tester, find.byKey(const Key('unlock-supplier-payment')));
      await enter(tester, keyed('supplier-payment-amount-').first, '30,00');
      await confirm(tester);
      expect(fake.payments.single.totalMinor, 3000);
      expect(fake.payables.single.remainingMinor, 7000);
      expect(tester.takeException(), isNull);
    },
  );
}
