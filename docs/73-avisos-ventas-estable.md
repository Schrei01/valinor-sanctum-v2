# Avisos y cobro estable — Desarrollo 0.35.0

Las confirmaciones y los avisos informativos de Ventas, Compras, Deudores, Eventos y Tesorería tienen fondo verde claro y texto verde oscuro. Los errores de carga, validación y conflictos que impiden continuar conservan el fondo rojo claro. El tipo de aviso se establece según su función, sin clasificar por palabras del mensaje. Las notificaciones temporales de errores también usan rojo claro; la confirmación de una corrección de inventario usa verde claro.

En cada cuenta de Ventas, el total, selector de pago, Dividir cuenta y Registrar venta permanecen en una fila que se adapta al ancho disponible. Los detalles variables aparecen después de esa fila: titular y saldo, cobrado y deuda, importes por medio y Volver a pago único. La falta de una persona activa para fiar se muestra allí en rojo. Esos detalles siguen visibles sin desplazar Registrar venta al elegir Deudas o guardar una división. La identidad de la cuenta no aumenta de altura al cambiar de medio de pago.

No cambian los cálculos, movimientos, validaciones, guardado de cuentas ni confirmación de ventas. El esquema sigue en 21 con 73 tablas. Este incremento corresponde a la edición portable Desarrollo 0.35.0+53; mantiene separada la última Producción 1.1.0.

Las verificaciones y la entrega se registran en [la evidencia sanitizada](evidence/notices-035.json). Las capturas sintéticas y los respaldos locales permanecen fuera de Git y del paquete.

Pasaron 103 pruebas de widgets de los módulos afectados y cuatro renders sintéticos, inspeccionados en anchos de 1280 y 400 píxeles. Tres pruebas adicionales dentro de esas 103 comparan el rectángulo exacto de Registrar venta en anchos de 1280, 900 y 400 al pasar por Efectivo, Deudas sin persona, Deudas asignadas, división de dos/tres medios y retorno a pago único. No se ejecutó una suite general nueva. Análisis limpio y formato de 213 archivos sin cambios finales.

El respaldo manual se verificó por contenido. Las definiciones y filas de las 73 tablas de desarrollo coinciden antes y después de iniciar el ejecutable; integridad correcta, cero violaciones de claves foráneas y ninguna operación comercial de prueba en la base activa. ZIP y bundle coinciden en 19 archivos, sin datos privados. Se retiró la entrega anterior de Desarrollo y la limpieza quedó sin pendientes. Los 21 archivos de distribución productiva, 20 de su instalación y el selector/historial de desarrollo conservaron sus huellas. No se accedió a la base productiva ni se cerró su ventana.

La aplicación Desarrollo quedó abierta y respondiendo con su título. La revisión visual utiliza los cuatro renders sintéticos; no se atribuye una inspección visual nativa nueva.
