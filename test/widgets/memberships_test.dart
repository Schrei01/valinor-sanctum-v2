import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:valinor_sanctum_2/core/infrastructure/app_config.dart';
import 'package:valinor_sanctum_2/features/memberships/domain/membership.dart';
import 'package:valinor_sanctum_2/features/memberships/presentation/memberships_page.dart';
import 'package:valinor_sanctum_2/features/quick_sales/application/quick_sales_controller.dart';
import 'package:valinor_sanctum_2/features/quick_sales/domain/quick_sales_store.dart';
import 'package:valinor_sanctum_2/features/quick_sales/presentation/quick_sales_page.dart';
import 'package:valinor_sanctum_2/features/inventory/domain/inventory_store.dart';
import 'package:valinor_sanctum_2/features/workspace/domain/business_profile.dart';
import '../support/fake_quick_sales_store.dart';
import '../support/fake_debtors_store.dart';

class MembersFake implements MembershipStore {
  final now = DateTime.now().toUtc();
  late final person = Membership(
    personId: 'Cliente sintético',
    name: 'Cliente sintético',
    email: 'member@example.com',
    birthDay: 12,
    birthMonth: 6,
    periodId: 'period',
    voucherGrantedMinor: 30000,
    starts: membershipDay(now),
    ends: membershipNextMonth(membershipDay(now)),
  );
  @override
  Future<List<Membership>> load({DateTime? atUtc}) async => [person];
  @override
  Future<String> savePerson({
    required String commandId,
    String? personId,
    required String name,
    required String email,
    int? birthDay,
    int? birthMonth,
  }) async => personId ?? 'new';
  @override
  Future<void> claimIncluded({
    required String commandId,
    required String periodId,
    required String productId,
    required DateTime atUtc,
  }) async {}
  @override
  Future<List<({String name, String period, String detail})>> history(
    String id,
  ) async => [];
}

void main() {
  setUpAll(() async {
    for (final family in {
      'Roboto': ['roboto-regular.ttf', 'roboto-medium.ttf', 'roboto-bold.ttf'],
      'MaterialIcons': ['materialicons-regular.otf'],
    }.entries) {
      final loader = FontLoader(family.key);
      for (final file in family.value) {
        loader.addFont(
          Future.value(
            ByteData.sublistView(
              await File(
                p.join(
                  AppConfig.repositoryRootPath,
                  '.tooling',
                  'flutter',
                  'bin',
                  'cache',
                  'artifacts',
                  'material_fonts',
                  file,
                ),
              ).readAsBytes(),
            ),
          ),
        );
      }
      await loader.load();
    }
  });
  for (final width in [1120.0, 400.0]) {
    testWidgets('membership screen and sales discount controls at $width', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(Size(width, 1100));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final members = MembersFake(),
          debtors = FakeDebtorsStore(),
          sales = FakeQuickSalesStore();
      final controller = QuickSalesController(store: sales);
      addTearDown(controller.dispose);
      sales.memberships.add(members.person);
      sales.products.add(
        const CatalogProduct(
          id: 'booster',
          name: 'Booster Magic',
          listPriceMinor: 25000,
        ),
      );
      sales.stock.add(
        const StockPosition(
          productId: 'booster',
          quantity: 10,
          totalCostMinor: 100000,
        ),
      );
      Future<void> open(Widget child) async {
        await tester.pumpWidget(
          RepaintBoundary(
            key: const Key('membership-render'),
            child: MaterialApp(
              theme: ThemeData(
                colorScheme: ColorScheme.fromSeed(
                  seedColor: const Color(0xff183d35),
                ),
              ),
              home: Scaffold(
                body: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: child,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }

      Future<void> capture(String name) async {
        if (!const bool.fromEnvironment('SANCTUM_CAPTURE_MEMBERSHIP')) return;
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const Key('membership-render')),
        );
        await tester.runAsync(() async {
          final pic = await boundary.toImage(pixelRatio: 1);
          final bytes = await pic.toByteData(format: ui.ImageByteFormat.png);
          final file = File(
            p.join(
              AppConfig.repositoryRootPath,
              'tmp',
              'membership-$name-${width.toInt()}.png',
            ),
          );
          await file.writeAsBytes(bytes!.buffer.asUint8List());
          pic.dispose();
        });
      }

      await open(
        MembershipsPage(
          store: members,
          debtors: debtors,
          sales: sales,
          onEnroll: (_) async {},
        ),
      );
      expect(find.text('Membresías'), findsOneWidget);
      expect(find.text('Inscribir en Ventas'), findsNothing);
      expect(find.text('Renovar en Ventas'), findsOneWidget);
      await capture('directory');
      await controller.load();
      final id = controller.addAccount()!;
      controller.selectDebtor(id, 'Cliente sintético');
      final line = controller.accounts.single.lines.single;
      controller.editLine(
        id,
        QuickSaleLine(
          id: line.id,
          productId: 'booster',
          unitPriceMinor: 25000,
          paymentOptionId: line.paymentOptionId,
        ),
      );
      await controller.flush(id);
      await open(
        QuickSalesPage(
          controller: controller,
          membershipStore: members,
          profile: BusinessProfile(
            profileId: 'test',
            businessName: 'Valinor',
            currencyCode: 'COP',
            moneyScale: 0,
            timezone: 'America/Bogota',
            createdAtUtc: DateTime.utc(2026),
          ),
        ),
      );
      final checkbox = find.byKey(ValueKey('membership-voucher-${line.id}'));
      await tester.ensureVisible(checkbox);
      await tester.tap(checkbox);
      await tester.pumpAndSettle();
      expect(controller.accounts.single.lines.single.unitPriceMinor, 25000);
      expect(controller.accounts.single.lines.single.useVoucher, isTrue);
      await tester.enterText(
        find.byKey(ValueKey('quick-quantity-${line.id}')),
        '2',
      );
      await tester.pumpAndSettle();
      expect(controller.accounts.single.lines.single.useVoucher, isTrue);
      expect(tester.takeException(), isNull);
      await capture('sales');
      controller.selectAccountPayment(id, QuickPaymentOption.creditId);
      await tester.pumpAndSettle();
      expect(find.text('Cobrado: COP 0 · Deudas: COP 20.000'), findsOneWidget);
      await controller.flushAll();
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
