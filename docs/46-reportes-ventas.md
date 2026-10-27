# Reportes de ventas — 0.19.0

Reportes conserva los cuatro saldos de Caja y Nequi al inicio y al final del rango. Añade **Ingreso por ventas a Caja**, **Ingreso por ventas a Nequi/Transferencia**, **Ventas a Deudas** y **Total vendido**. La suma usa los importes guardados al confirmar cada venta y la forma de pago elegida en sus líneas. Si se registraron otros medios de pago locales, aparecen aparte y se incluyen en el total para que concilie.

Una venta a Deudas cuenta como venta en el momento de su confirmación. El abono posterior modifica dinero y cartera, pero no vuelve a sumar ventas. También se excluyen aperturas, transferencias internas, compras y gastos. Por eso estos ingresos no equivalen a restar saldo inicial al final ni a sumar todas las entradas de una cuenta.

Se mantienen los dos selectores de fecha seguidos de hora AM/PM y el horario de Bogotá. Todo el reporte usa el mismo rango: desde el comienzo del minuto inicial hasta terminar el minuto final. Cambiar los selectores no cambia las cifras ni sus rótulos hasta pulsar Generar reporte; si falla la consulta se conserva el último resultado. No se agregan gráficas ni otros indicadores.

## Ventas antiguas sin importe

El propietario eligió explícitamente **Sin información** para las ventas importadas cuyo importe no se guardó. El archivo histórico conserva producto, cantidad, fecha y medio, pero carece del precio de la venta. No se multiplica la cantidad por el PVP actual ni por el PVP archivado: ambos podrían diferir del precio realmente vendido.

Los grupos que contienen estas ventas y el total completo muestran Sin información. Debajo se conserva el subtotal de las ventas con importe conocido y se indica cuántos registros antiguos del rango carecen de importe. Los demás grupos pueden seguir mostrando un total exacto. Las ventas huérfanas también cuentan como información incompleta, aunque el producto ya no exista. Un rango sin ventas devuelve cero.

El nuevo agregado `ReportSalesTotals` complementa los detalles nativos del lector. Estos detalles siguen disponibles internamente para los reportes anteriores; el total visible incorpora expresamente la calidad del archivo histórico. No se crean ventas operativas a partir del archivo ni se vuelve a mover inventario, dinero o deuda.

## Archivos

- `reports_store.dart`: agregado por medio, subtotales conocidos y valores incompletos, con enteros y control de desbordamiento.
- `sqlite_reports_store.dart`: toma el reparto de pagos de las ventas confirmadas y detecta los registros históricos sin importe dentro del rango.
- `reports_page.dart`: nuevos indicadores debajo de los saldos existentes.
- Pruebas de integración, dominio e interfaz; versión, README e instrucciones del paquete actualizadas.

Esquema v14, sin migración ni tablas nuevas. La consulta no ejecuta comandos comerciales. Los datos privados, respaldos e imágenes sintéticas de verificación permanecen fuera de Git y del paquete distribuible.

## Verificación

La ejecución enfocada aprobó 40 casos de aplicación. Esa orden incluyó por error una ruta de prueba inexistente; por ello terminó con un error de carga. Se corrigió la ruta y la ejecución posterior aprobó nueve casos (siete de conversión, uno de navegación y una captura sintética). Tras simplificar la inicialización del agregado para cumplir el análisis, se repitieron sus 18 casos de dominio, controlador e interfaz, todos aprobados. Entre las ejecuciones quedaron aprobados 41 casos distintos de aplicación y una prueba de renderizado. No se repitió la suite financiera completa.

Las comprobaciones cubren efectivo, transferencia y deuda en un mismo producto, precios históricos tras modificar el catálogo, abonos sin nueva venta, compras y gastos sin reducir ventas, transferencias sin ingreso comercial, desbordamiento, límites del minuto final, archivos históricos con productos eliminados y rangos que combinan ventas nuevas con importes antiguos desconocidos. Se inspeccionaron imágenes sintéticas amplia y estrecha, sin datos privados.

Se auditaron las fechas y medios de los 4.305 registros históricos de la base activa. Siete rangos se contrastaron con un cálculo independiente sobre un respaldo consistente; todos coinciden. Las 63 tablas y el esquema de ese respaldo permanecieron idénticos después de consultar. La primera tentativa del helper con `query_only` rechazó el `BEGIN IMMEDIATE` que usa sqflite; se ejecutó después en la copia privada y se comprobó conservación completa, sin abrir la activa con Flutter. El análisis final no tiene incidencias.

## Entrega publicada

Release Windows 0.19.0+29 compilado sin overrides y publicado en el acceso estable después del cierre confirmado por el propietario. ZIP, entrega estable y copia versionada coinciden en sus 17 archivos, sin bases, perfiles ni snapshots privados. La carpeta y el ZIP de 0.18.1 se eliminaron conforme a la política de retención.

Se creó y verificó un respaldo consistente de la base cerrada en `backups/report-sales-20261026`. Después de publicar se compararon las 63 tablas y el esquema: todos sus registros permanecen idénticos, integridad correcta, cero violaciones FK, esquema14 y escala0. Sin migración ni operaciones de prueba en la base activa. La app se deja cerrada; no se afirma un recorrido nativo nuevo. El propietario puede abrir la 0.19.0 con `Iniciar Valinor Sanctum.cmd`. Ver [evidencia](evidence/report-sales.json).
