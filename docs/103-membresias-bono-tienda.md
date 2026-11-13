# Bono de Mensualidad Élfica — Desarrollo 0.49.0

La revisión vigente 0.49.1 conserva este funcionamiento y corrige la recreación innecesaria de líneas de Ventas detectada por CI. [Corrección y validación](104-correccion-ci-lineas-bono.md).

La mensualidad conserva COP 109.000 por un mes calendario y acceso ilimitado. Sus beneficios de tienda pasan a ser un bono de COP 30.000 por período; ya no se entregan boosters incluidos ni se ofrecen descuentos de boosters. El propietario confirmó que el diseño anterior solo se probó en Desarrollo. La comprobación previa de su base encontró cero períodos y cero beneficios.

## Uso

1. En Membresías registra la persona o selecciona una existente, con correo y día/mes de nacimiento opcionales. Inscribe o renueva desde Ventas y confirma la mensualidad con Efectivo, Transferencia, Deudas o pago dividido. Confirmarla activa el período incluso si queda deuda.
2. En una cuenta de Ventas asocia esa persona. La tarjeta muestra vigencia, acceso, bono disponible y redimido.
3. Agrega sus productos y marca **Usar bono** en los consumos que cubrirá. Se asigna por orden de las líneas marcadas. El PVP y las cantidades permanecen visibles e inalterados; se muestra consumo, cobertura y restante por pagar.
4. Si el bono cubre todo, registra sin escoger un pago adicional. Si excede el saldo, elige el medio o divide únicamente el excedente entre Efectivo, Transferencia y Deudas. Una modificación del consumo obliga a revisar la división.
5. El bono y el inventario se descuentan al confirmar. Los borradores no reservan el saldo. Otra cuenta abierta de la misma persona se recalcula si cambia el bono; la confirmación vuelve a comprobarlo para impedir uso doble.

Ejemplo: consumo COP 40.000 y bono COP 30.000. Se redimen 30.000 y quedan 10.000 para pago normal o dividido. Solo esa parte puede aumentar Caja/Nequi o deuda personal. El bono no paga mensualidades ni abonos a deudas anteriores. Al vencer termina el saldo no usado; la renovación otorga otro bono para su propio período, sin reiniciar el vigente anticipadamente.

## Datos y reportes

Migración 29 agrega `membership_voucher_grants`, `membership_voucher_plans` y `membership_voucher_collections`, más la selección y asignación por línea de borrador. Conserva las tablas y migraciones anteriores, incluido el historial de beneficios del diseño previo. Los períodos nuevos reciben el bono al confirmar su inscripción. No se convierten retroactivamente beneficios antiguos en un bono adicional.

La venta conserva el PVP y su salida de inventario. Dentro de la misma transacción se aplica una bonificación sin efectivo exclusivamente a la cuenta por cobrar originada por esa venta. El formato v4 de pagos anterior mantiene sus validaciones; una asignación inmutable relaciona las líneas con el bono y la bonificación liquida su importe. No puede abonar deudas de otro documento ni modificar Caja/Nequi. Los saldos y el historial públicos muestran únicamente el crédito real del excedente. Reintentar una confirmación recupera el resultado sin repetir canjes.

Reportes muestra **Consumo con bono** separado del ingreso por ventas: la mensualidad se cuenta al venderla y el consumo cubierto no vuelve a sumarse a Total vendido. Se conservan las cantidades entregadas y el rótulo Bono en los ítems. El costo de inventario permanece registrado; los resultados de eventos también descuentan la bonificación de sus inscripciones.

## Entrega y validación

Desarrollo 0.49.0+84, esquema 29. Solo se publica el portable de Desarrollo para revisión; Producción 1.8.0 y su base operativa permanecen independientes. El incremento depende de los PR #10 (Membresías) y #11 (Deuda anterior), ambos con CI completo aprobado pero todavía abiertos. Su PR se apila sobre #11, y requiere revisión del propietario y CI completo aprobado antes de integrarse. No se crea etiqueta de lanzamiento antes de la integración.

Las pruebas cubren inscripción pagada/fiada/parcial, mes calendario, renovación anticipada, vencimiento, pago íntegro con bono, excedente dividido, cantidades/PVP exactos, líneas marcadas/no marcadas del mismo producto, concurrencia entre cuentas, fallos de stock sin consumo, reapertura y reintentos, restricciones SQL, Reportes e historial. Las migraciones sintéticas 27/28→29 verifican conservación de filas, respaldo automático, integridad y claves foráneas. Se inspeccionaron cuatro imágenes de Membresías y Ventas a 1120/400 píxeles. Los resultados finales y artefactos se registran en [evidencia](evidence/membership-voucher-049.json).
