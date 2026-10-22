# Deudores — alcance del incremento

Solicitud del propietario: reemplazar Cobros por un módulo que registre personas, permita elegirlas en Ventas al fiar y reciba abonos que reduzcan su deuda e ingresen a la cuenta correspondiente. Se confirmó **una persona por cuenta de Ventas** y **permitir deuda anterior**.

## Flujo

- **Deudores**: registrar nombre, consultar saldo e historial y seleccionar una persona para abonar. La identidad es estable; no se agrupan personas solo por nombres escritos en las ventas.
- **Ventas**: al elegir Deudas aparece la selección obligatoria de persona registrada. Todas las líneas fiadas de esa cuenta pertenecen a esa persona. Las líneas pagadas siguen admitiendo Efectivo o Transferencia. La deuda aumenta al registrar la venta, no al editar el borrador.
- **Abono**: persona, importe positivo y Efectivo o Transferencia. Admite pago parcial o total, nunca mayor al saldo pendiente. Se aplica primero a los cargos más antiguos sin exigir elegir cada venta. Deuda y dinero se registran juntos; no se repiten ventas ni salidas de inventario.
- **Historial**: ventas fiadas, saldos anteriores y abonos, con fecha, importe y medio de pago. Un cambio de disponibilidad para fiar no impide cobrar una deuda existente. No se borran hechos confirmados.

## Deudas anteriores y datos existentes

Al declarar deuda anterior se distingue entre **importe ya incluido en la cartera importada** y **deuda adicional no registrada**. El primero identifica una parte del saldo global pendiente de asignar sin aumentar la deuda total; el segundo incorpora un saldo anterior declarado, sin inventar una venta, producto o movimiento de caja. Se conserva la procedencia y se limita a un saldo inicial por persona para evitar repetirlo por error.

Las ventas anteriores que solo guardan nombres permanecen íntegras y pueden asignarse explícitamente a una persona. No se unen nombres parecidos automáticamente. La cartera importada sin detalle sigue separada hasta que el propietario identifique sus importes; no se distribuye por suposición ni se vuelve a importar.

## Integridad

Migración aditiva, respaldo y ensayo con conservación de los datos propios. Se conservan canónicos y reintentos de ventas/cobros ya preparados. Los registros nuevos con Deudas requieren identidad de deudor; dinero en enteros y BigInt, solicitudes durables y confirmación atómica e idempotente. Transferencia en Deudores utiliza la cuenta de Nequi existente; Compras, Eventos y Tesorería conservan sus nombres actuales.

Fuera del alcance: intereses, cupos de crédito, recordatorios, cuentas bancarias nuevas, eliminación de historia y reversas/anulaciones. No se registran operaciones de prueba en el perfil del propietario.

## Uso en la versión 0.16.0

1. En **Deudores → Registrar persona**, escribe el nombre. Usa deuda anterior 0 si inicia sin saldo. Si tiene saldo previo, indica si ya estaba incluido en la cartera anterior o si es adicional.
2. En **Ventas**, elige **Deudas** en las líneas fiadas y selecciona la **Persona de la deuda** de esa cuenta. Registrar venta confirma el cargo; preparar un borrador no aumenta su saldo.
3. En **Deudores**, selecciona la persona, escribe el valor del abono y elige **Efectivo** o **Transferencia**. **Pagar todo** completa el saldo pendiente. **Registrar abono** actualiza deuda y dinero juntos.
4. Consulta **Deudas registradas** y **Abonos** en su cuenta. **Bloquear fiado** impide nuevos cargos, conservando saldo e historial y permitiendo abonos.
5. Si hay ventas anteriores sin identidad registrada, usa **Asignar persona**. El saldo global importado sin detalle se identifica mediante deuda anterior incluida, sin volver a sumarlo.

## Validación

La suite general ejecutó 645 pruebas aprobadas y tres omitidas por enlaces del host. Dos casos de prueba fallaron: uno intentó cambiar una identidad monetaria que ya era inmutable y otro pulsó una opción fuera del área visible del menú. Corregidos esos preparativos, la revisión final aprobó 44 casos (43 de aplicación y una captura sintética), incluyendo los dos corregidos y tres casos nuevos de compatibilidad/reapertura. Entre ejecuciones quedaron 650 casos distintos de aplicación aprobados. No se presenta la primera ejecución como suite completa sin fallos.

Análisis sin incidencias y formato limpio de 35 archivos Dart modificados. Se verificaron abonos parciales/totales, asignación histórica sin alterar hechos, rechazos por saldo cambiado, rollback y reintento, inmutabilidad, reapertura real de archivo y confirmación/replay de una venta v2 preparada antes de v13. La imagen sintética del módulo se inspeccionó.

Las doce migraciones publicadas anteriores conservan sus nombres y checksums. Respaldo propio v12 y ensayo v13: las 53 tablas anteriores conservan todas sus filas y columnas originales; siete tablas añadidas, integridad correcta y cero violaciones FK. La cartera e inventario no se vuelven a importar. La publicación local espera el cierre de la copia anterior; el ZIP 0.16.0+23 ya está compilado sin overrides y revisado sin datos privados.
