import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:valinor_sanctum_2/features/inventory/presentation/inventory_widgets.dart';

void main() {
  testWidgets(
    'information is light green and blocking notices retain the error palette',
    (t) async {
      final scheme = ColorScheme.fromSeed(seedColor: const Color(0xFF183D35));
      await t.pumpWidget(
        MaterialApp(
          theme: ThemeData(colorScheme: scheme),
          home: const Scaffold(
            body: Column(
              children: [
                InventoryNotice(
                  key: Key('info'),
                  text: 'Movimiento registrado',
                  kind: InventoryNoticeKind.information,
                ),
                InventoryNotice(
                  key: Key('error'),
                  text: 'No hay saldo suficiente',
                ),
              ],
            ),
          ),
        ),
      );
      Color? background(String key) =>
          (t
                      .widget<Container>(
                        find
                            .descendant(
                              of: find.byKey(Key(key)),
                              matching: find.byType(Container),
                            )
                            .first,
                      )
                      .decoration
                  as BoxDecoration)
              .color;
      expect(background('info'), InventoryNotice.informationBackground);
      expect(background('error'), scheme.errorContainer);
      expect(
        DefaultTextStyle.of(
          t.element(find.text('Movimiento registrado')),
        ).style.color,
        InventoryNotice.informationForeground,
      );
      expect(
        DefaultTextStyle.of(
          t.element(find.text('No hay saldo suficiente')),
        ).style.color,
        scheme.onErrorContainer,
      );
    },
  );
}
