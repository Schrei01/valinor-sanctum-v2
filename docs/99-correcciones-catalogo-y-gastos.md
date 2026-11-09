# Correcciones de Catálogo y gastos — Desarrollo 0.46.0

Tesorería ofrece Arriendo, Aseo, Agua, Energía, Envíos y Otro como motivos de nuevos gastos. Los registros y solicitudes anteriores con Servicios conservan esa clasificación y siguen siendo recuperables.

Ctrl+D funciona exclusivamente en Catálogo. Abre un menú con Corregir cantidad, Corregir nombre, Corregir PVP y Corregir evento. El acceso permanece fuera de los avisos de Compras y del menú habitual. Cantidades conserva enteros positivos/negativos y recuperación existente. Nombre y PVP están disponibles para Comestibles y Artículos, incluidos productos agotados; no crean una compra, venta ni movimiento de dinero. El PVP debe ser positivo, aplica a existencias actuales y queda en el historial de precios. Las ventas y compras anteriores conservan sus snapshots.

## Eventos

El editor carga nombre, PVP de inscripción, mínimo de personas, costo fijo, fuente y componentes actuales. Puedes agregar/quitar productos físicos o cambiar sus cantidades. El costo por persona se recalcula; si hay costo fijo o componentes se exige mínimo positivo. PVP siempre debe ser mayor que cero. Pasadía, Bulk y Alquiler conservan su comportamiento especial.

Antes de guardar, Revisar cambios presenta el PVP, costo por persona, unidades que se descontarán/devolverán y costo fijo adicional. Confirmar corrección registra todo en una transacción con identidad durable. La revisión pendiente puede recuperarse al reabrir Ctrl+D; ante resultado incierto se reintenta la misma solicitud, sin duplicar sus efectos. Si cambió el ítem, la revisión o los costos, hay que descartar y preparar de nuevo.

- Más artículos consumen solo las unidades adicionales mediante FIFO. Menos artículos devuelven solo la diferencia al inventario con el costo proporcional registrado del componente, sin perder pesos en las divisiones. Devolver todas sus unidades recupera su costo total íntegro. Los lotes de devolución se separan internamente cuando hay restos de división, sin mostrarlos como operaciones diferentes al usuario.
- Aumentar el costo fijo cobra solo el aumento desde Caja/Nequi o incrementa Inversión. Reducirlo no devuelve dinero ni disminuye Inversión. Si luego vuelve a aumentar, ese nuevo aumento también se paga; el pagado acumulado conserva todos los desembolsos reales.
- La configuración de costo fijo actual determina el cálculo sugerido. El pagado acumulado determina el gasto real: una rebaja de configuración no borra un egreso anterior. Reportes conserva gastos anteriores y suma las correcciones de insumos y los desembolsos adicionales en sus fechas, sin duplicar el costo original. Los resultados de eventos respetan la fecha final del informe.
- Las inscripciones confirmadas mantienen nombre, precio, cobro y deuda originales. Las nuevas selecciones de Ventas usan el catálogo actualizado; las cuentas que ya tenían un precio acordado lo conservan.

## Compatibilidad

Migración nueva27, respaldada desde26, conserva76 tablas previas y agrega4: catalog_correction_requests, catalog_corrections, event_return_values y event_correction_payments. Solo sustituye validadores de motivos de gasto y extiende la validación de devoluciones valoradas; no modifica migraciones publicadas ni hechos originales. Agrega vistas de configuración/componentes actuales de eventos, con revisiones auditables e inmutables.

La entrega es solo Desarrollo0.46.0+80. Producción1.7.0, su instalación/ventana y los datos de Documentos se preservan. Incluye Alquiler0.45 pendiente en PR7. La nueva rama se entrega como PR para revisión; no se integra hasta conformidad del propietario y CI completo aprobado. Resultados ejecutados en docs/evidence/catalog-corrections-046.json; copias, respaldos e imágenes sintéticas en directorios privados ignorados.
