# Reporte compacto con egresos — 0.20.0

El propietario pidió egresos del rango y una presentación ordenada como factura, bonita y con poco desplazamiento. Reportes pasa a un comprobante único con nombre del negocio, rango generado, tabla de saldos y dos columnas: ventas y egresos. Los importes se alinean a la derecha con cifras tabulares, separadores y totales destacados. Se mantienen fechas seguidas de hora AM/PM y las políticas de ventas estimadas y parciales.

En ventanas amplias, ventas y egresos aparecen lado a lado; en estrechas se apilan sin desplazamiento horizontal ni ocultar datos. El rango impreso pertenece a la consulta generada, no a los cambios pendientes de los selectores. Las aclaraciones de historia y calidad quedan al pie en texto breve. Es un formato visual de comprobante, sin emisión de factura fiscal, impresión ni exportación añadidas.

## Qué suman los egresos

Se muestran Caja, Nequi/Transferencia y Total egresos. Son salidas registradas de esas dos cuentas: compras pagadas, gastos y costos fijos de eventos pagados. No suman transferencias internas, aperturas, costos de productos usados en un evento sin salida de dinero, movimientos de Caja mayor ni disminuciones de deuda. Los egresos no se deducen de la diferencia de saldos ni se presentan como costo de ventas o ganancia.

Para operaciones nuevas, se agregan las salidas de los movimientos contables confirmados dentro del rango. Para la copia, se leen únicamente las filas archivadas de `movimientos` con tipo egreso y cuenta Caja o Nequi. Se preservan montos registrados y fechas de Bogotá, desde el comienzo del minuto inicial hasta terminar el minuto final. No se consulta ni modifica la base original. Los importes históricos inválidos se señalan como información faltante y el subtotal se marca parcial.

`ReportOutflowTotals` mantiene este agregado separado del total nativo usado internamente por los gráficos anteriores. No se añadieron tablas, vistas persistentes, migraciones ni escrituras comerciales. Esquema14.

## Verificación

La primera ejecución aprobó 36 casos y detectó cuatro errores de carga relacionados con la estructura de estado de la pantalla reorganizada. Se restauró la separación StatefulWidget/State y los selectores existentes. La ejecución de interfaz corregida aprobó 11 casos, incluido un render sintético. La ejecución final completa del alcance aprobó **47 casos: 46 de aplicación y un render**. El análisis final no tiene incidencias; se corrigieron importación redundante y composición de cadenas. No se repitió la suite financiera completa.

Las pruebas cubren compras/gastos/eventos como salidas reales de dinero, exclusión de transferencias/aperturas/Caja mayor/deudas, importes faltantes y desbordamientos, límites de minuto y fracciones, ausencia de escrituras, ventas antiguas/nuevas, AM/PM, cancelar, conservar el último reporte y navegación. Una comprobación de interfaz exige que el comprobante base completo quede dentro de una superficie de 1000×850; se inspeccionaron las imágenes con estimaciones y parciales tanto amplia como estrecha.

Se auditaron 236 egresos históricos registrados de Caja/Nequi. Siete rangos se contrastaron en respaldo privado con una suma independiente: coinciden los dos medios y el total. Las 63 tablas y el esquema de esa copia permanecen idénticos después de consultar. La base original no se abrió ni modificó.

## Entrega

Release Windows 0.20.0+31 compilado sin overrides y publicado con la app cerrada. ZIP, acceso estable y copia versionada coinciden en sus 17 archivos privados excluidos. Las distribuciones anteriores se eliminaron conforme a la retención autorizada.

Respaldo consistente verificado en `backups/report-invoice-20261027`. Después de publicar, las 63 tablas y el esquema permanecen íntegramente idénticos, integridad correcta, cero violaciones FK, esquema14 y escala0. La app se deja cerrada, sin operaciones de prueba sobre los datos del propietario ni recorrido nativo nuevo. Abrir con `Iniciar Valinor Sanctum.cmd`. Ver [evidencia](evidence/report-invoice.json).
