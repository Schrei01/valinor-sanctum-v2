import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:valinor_sanctum_2/features/memberships/domain/membership.dart';
import 'package:valinor_sanctum_2/features/memberships/presentation/membership_alerts.dart';
import 'package:valinor_sanctum_2/features/memberships/presentation/memberships_page.dart';

void main() {
  for (final width in [1120.0, 400.0]) {
    testWidgets(
      'birthday alerts include expired and never-paid people at $width',
      (tester) async {
        await tester.binding.setSurfaceSize(Size(width, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final now = DateTime.utc(2026, 12, 28, 17);
        final expired = Membership(
          personId: 'expired',
          name: 'Vencida',
          email: '',
          birthDay: 28,
          birthMonth: 12,
          starts: DateTime.utc(2026, 10, 1),
          ends: DateTime.utc(2026, 11, 1),
        );
        const unpaid = Membership(
          personId: 'unpaid',
          name: 'Sin mensualidad',
          email: '',
          birthDay: 4,
          birthMonth: 1,
        );
        var opened = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Column(
                children: [
                  MembershipAlerts(
                    members: [
                      unpaid,
                      expired,
                      const Membership(
                        personId: 'later',
                        name: 'Fuera del rango',
                        email: '',
                        birthDay: 5,
                        birthMonth: 1,
                      ),
                      const Membership(
                        personId: 'none',
                        name: 'Sin fecha',
                        email: '',
                      ),
                    ],
                    now: now,
                    onOpen: () => opened++,
                  ),
                  MembershipBenefitsPanel(member: unpaid),
                ],
              ),
            ),
          ),
        );
        expect(
          find.byKey(const ValueKey('membership-expiry-alert')),
          findsOneWidget,
        );
        final birthday = find.byKey(
          const ValueKey('membership-birthday-alert'),
        );
        expect(birthday, findsOneWidget);
        final text = tester
            .widget<Text>(
              find.descendant(of: birthday, matching: find.byType(Text)).first,
            )
            .data!;
        expect(text, contains('Vencida · Cumpleaños hoy'));
        expect(text, contains('Sin mensualidad · Cumpleaños en 7 días'));
        expect(text, isNot(contains('Fuera del rango')));
        expect(text, isNot(contains('Sin fecha')));
        expect(
          text.indexOf('Vencida'),
          lessThan(text.indexOf('Sin mensualidad')),
        );
        await tester.tap(birthday);
        expect(opened, 1);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
