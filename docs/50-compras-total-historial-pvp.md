# Compras por costo total e historial de PVP — 0.21.0

Compras ahora pide **Costo total de las unidades** y **Cantidad**. El valor ingresado es lo que se pagó por toda la mercancía. La sugerencia de PVP por unidad es `(total ÷ cantidad) ÷ 0,65`, redondeada a la unidad monetaria más cercana del perfil. Con COP/escala0, 10 unidades por $25.000 sugieren $3.846. Los perfiles históricos con centavos conservan su escala.

El PVP se completa con la sugerencia mientras el operador no lo haya editado. Es editable, incluso por debajo de la sugerencia o en cero, y Usar sugerido permite recuperarla. Modificar costo o cantidad no sobreescribe un PVP elegido manualmente. Al seleccionar un producto se muestra **PVP anterior**, se completan SKU/categoría/proveedor y se deja el nuevo costo total para registrar lo realmente pagado; el costo de una compra nueva no se presume por compras pasadas.

El PVP vigente es único por producto y se aplica a las unidades disponibles anteriores y nuevas. Los precios ya registrados en ventas y los costos de compra/FIFO no se revalorizan al cambiarlo. Cada ingreso conserva el PVP elegido en su historial.

## Costo y dinero exactos

Se conserva el costo total íntegro aunque no sea divisible en valores unitarios enteros. Por ejemplo, un costo de 1 unidad monetaria por tres productos sigue siendo 1, con distribución de remanentes según la política FIFO vigente. No se redondea el costo unitario para luego multiplicarlo y cambiar lo pagado.

Se elige Efectivo/Caja o Nequi como antes. Catálogo, existencias, compra, pago total e historial de precio se guardan en la misma transacción. La salida de dinero y los egresos de Reportes corresponden al total ingresado. Reintentar una confirmación no duplica existencias, pago ni precio histórico. El PVP sugerido es informativo: no exige ganancia mínima.

## Persistencia y compatibilidad

Esquema v15. Las migraciones v1–v14 y sus checksums permanecen intactos. `paid_purchase_entries` se reconstruye conservando todas sus filas y columnas: `unit_purchase_price_minor` admite NULL cuando el promedio exacto no puede representarse con la escala del perfil. `total_cost_minor` conserva el importe pagado. La solicitud y sus hechos continúan sujetos a las comprobaciones de compra contabilizada y pago completo.

Los comandos nuevos por costo total usan payload v2. Se conservan preparación, confirmación y recuperación de los comandos v1 por precio unitario; en el formulario recuperado se muestra su total equivalente.

Se añade `product_price_history`, con producto, PVP anterior y nuevo, fecha UTC de registro, fecha de operación y solicitud de compra cuando corresponda. Registra automáticamente altas y cambios del PVP, incluidas las modificaciones por otras rutas del catálogo. Es inmutable. La migración conserva el precio actual de cada producto como referencia inicial; su fecha histórica efectiva queda desconocida, sin inventar cuándo empezó a usarse. Los cambios futuros se guardan con su procedencia. El visor completo de evolución de precios queda para una entrega futura.

No se cambian inventario, saldos ni hechos previos durante la migración. El POS original y los archivos de origen permanecen sin modificar.

## Verificación

Compatibilidad inicial: 30 pruebas aprobadas. El alcance ampliado de compras, migración, controlador, fórmula y formulario aprobó 58 pruebas. La suite completa final aprobó **713 pruebas**, con tres omitidas por limitaciones de enlaces simbólicos del host. Análisis sin incidencias. No se presentan las ejecuciones repetidas como casos distintos adicionales.

Se verificaron el ejemplo de 10 unidades por 25.000, edición manual por debajo de la sugerencia y PVP cero, costo total no divisible, conservación del costo FIFO hasta vender las unidades, pago desde Caja/Nequi, egresos exactos, aplicación del nuevo PVP a existencias anteriores y nuevas, historial inmutable, rollback con fallo tras ambos documentos hijos, reintentos y reapertura. La migración sintética verifica filas de una compra anterior y una solicitud pendiente v1, respaldo v14 íntegro y fallo seguro si el respaldo no puede crearse.

La migración se ensayó sobre un respaldo privado de la base activa: conserva íntegramente las filas de sus 63 tablas anteriores y los 14 registros/checksums de migración; se añade únicamente `product_price_history` y el registro de versión15. Los 173 precios vigentes de esa copia coinciden con sus referencias iniciales, sin inventar fecha efectiva histórica. La nueva estructura tiene 64 tablas. Integridad correcta y cero FK. Los datos reales no se usaron para operaciones de prueba.

Una captura sintética adicional del ejemplo, con PVP anterior3.000, sugerido3.846, elegido3.500 y total25.000 desde Nequi, fue inspeccionada. La prueba de formulario estrecho también pasó. No se afirma recorrido nativo nuevo.

## Entrega

Release Windows0.21.0+33 compilado sin overrides y publicado después del cierre confirmado por el propietario. Se creó y verificó respaldo de la base cerrada en `backups/total-purchases-20261027`, además del respaldo v14 verificado automáticamente por AppDatabase antes de migrar.

La base activa pasó a v15 con 64 tablas y173 referencias iniciales de PVP. Se compararon todas las filas anteriores de63 tablas y los14 registros/checksums previos de migración: íntegramente conservados. Solo se añadió el historial de precios y el registro v15, con reconstrucción de las restricciones de la tabla de ingresos. Integridad correcta, cero FK y escala0 preservada. Sin operaciones comerciales de prueba en datos reales ni recorrido nativo nuevo.

ZIP, acceso estable y copia versionada coinciden en sus17 archivos privados excluidos; las distribuciones anteriores se limpiaron. La app se deja cerrada. Abrir con `Iniciar Valinor Sanctum.cmd`. Ver [evidencia](evidence/total-purchases.json).
