# Reportes — versión 0.17.0 (horarios ampliados en 0.17.1)

El propietario autorizó construir el módulo con el alcance discutido: fechas inicial y final, saldos de dinero, ingresos y egresos, ventas a Deudas, transferencias entre cuentas, productos vendidos, filtros y barras con resultados. Esta entrega consulta las operaciones confirmadas de Sanctum 2.0; no reimporta el historial original ni modifica los hechos comerciales.

## Criterios

- Desde 0.17.1 se eligen fecha y hora inicial/final en Bogotá, en formato de 24 horas. El minuto inicial y todo el minuto final están incluidos. Los valores predeterminados 00:00–23:59 conservan días completos. El saldo inicial se toma justo antes del comienzo y el final al terminar el minuto final. Las aperturas importadas o declaradas se identifican aparte de ventas e ingresos comerciales. Si un saldo anterior a la apertura importada no puede reconstruirse, se muestra sin dato, no cero.
- El dinero recibido se separa en cobro de ventas de mostrador y abonos posteriores de deudores, por Efectivo/Caja y Transferencia/Nequi. Ventas totales incluye lo fiado al confirmar la entrega. Los abonos no vuelven a sumar ventas ni costo de inventario.
- Deudas iniciales/finales, nuevo fiado y declaraciones adicionales de deuda anterior se distinguen. Identificar una parte de la cartera importada conserva el total; no se trata como nueva venta ni nueva cartera.
- Los egresos monetarios se desglosan en compras, gastos y costos fijos de eventos. Las transferencias presentan origen y destino una sola vez, con sus dos movimientos para conciliar cada cuenta, incluyendo Caja mayor.
- El listado de productos usa el nombre, valor vendido y costo histórico de cada venta. No recalcula el pasado con el PVP ni el costo actual del catálogo. Incluye productos agotados y eventos desactivados cuando tuvieron ventas en el período.
- Las ventas no guardaban categoría histórica. Por eso Categoría agrupa según la clasificación actual del catálogo, con aviso explícito; no se inventa un dato histórico. Los filtros de categoría y producto afectan el listado y las gráficas comerciales, conservando el resumen general del período.
- Margen de mercancía física: ventas de esas unidades menos su costo FIFO guardado. Resultado operativo del período: todas las ventas menos costo de mercancía vendida, costos reales de eventos creados en el período y gastos registrados. El pago de una compra no vuelve a descontarse como gasto del resultado.
- En un evento, el costo ya fue reconocido al crearlo. El reporte muestra además su resultado acumulado hasta la fecha final: inscripciones menos costo real total, sin multiplicar el PU orientativo por cada inscripción. Esto se distingue del resultado del período cuando creación e inscripciones ocurren en fechas distintas.
- Las barras permiten cambiar métrica y agrupación. Ventas/unidades/margen físico por día, semana, mes, categoría o producto; egresos por fecha o motivo; variación de dinero por fecha o cuenta. Las pérdidas se muestran negativas y cada grupo tiene sus valores y detalle accesibles.
- Solo documentos y asientos confirmados. Las sumas usan enteros y BigInt, se rechazan desbordamientos y se lee en una única transacción coherente. Sin límite de los últimos 50 movimientos de Tesorería.

## Entrega

Nueva entrada Reportes antes de Sistema. El esquema permanece v13: el módulo es de consulta, sin nuevas tablas ni migraciones.

La ejecución ampliada de integración/controlador de Reportes y todos los widgets tuvo 134 casos aprobados y un fallo en la preparación de la prueba de rotación monetaria (faltaba inicializar su cuenta sintética de gastos). Corregida esa preparación, la ejecución final de Reportes aprobó 28 casos: 27 de aplicación y una captura sintética. La última revisión visual aprobó seis casos. Entre ejecuciones se aprobaron 135 casos distintos de aplicación; no se repitió la suite completa. Análisis limpio y formato sin cambios en 14 Dart.

Se verificaron ventas mixtas sobre un mismo producto, abonos nuevos e históricos, transferencias, deudas anteriores, precios/costos históricos, costos de eventos entre períodos, corte exacto de Bogotá, más de 50 movimientos, pérdidas y desbordamientos. La revisión independiente detectó y verificó corregido el saldo inicial falso de cero si la importación coincide exactamente con el inicio del rango. Categoría sin clasificación y agrupación por identidad también están cubiertas.

Una copia propia actual se consultó en tres rangos: las 60 tablas y el esquema permanecieron idénticos, con integridad correcta y cero violaciones FK. Tras respaldar con la app cerrada y publicar 0.17.0+24 sin overrides, se comparó el perfil activo antes/después de abrir: todas las filas y el esquema siguen idénticos, sin operaciones comerciales de prueba. ZIP, entrega estable y copia versionada coinciden en 17 archivos sin datos privados.

Windows mostró inicio, Versión 0.17.0 y la entrada Reportes. El clic por accesibilidad falló por índice no disponible y su única recuperación falló con timeout de captura; no se afirma recorrido nativo de la pantalla. Formulario, detalle y gráficas se verificaron en widgets e imágenes sintéticas. La ventana queda abierta para el propietario. Ver [evidencia](evidence/reports.json).

## Uso

Abre **Reportes**, elige **Fecha inicial**, **Hora inicial**, **Fecha final** y **Hora final** y pulsa **Generar reporte**. Para un día completo usa 00:00–23:59; para un turno usa sus horas. Consulta los saldos y pulsa los totales para ver su composición. En **Productos vendidos** filtra por Categoría o Producto; en **Gráfica de barras** cambia Mostrar y Agrupar por. Pulsa una barra o su fila para ver los movimientos que la componen. El resultado acumulado de cada evento presenta inscripciones, valor vendido, costo real y resultado; no ofrece el detalle de inscripciones fuera del período.

Si no hay operaciones confirmadas en el rango, aparece un aviso. No se incluyen borradores ni ventas del sistema anterior: solo se importaron inventario y saldos iniciales. Ver [horarios 0.17.1](41-horarios-reportes.md).
