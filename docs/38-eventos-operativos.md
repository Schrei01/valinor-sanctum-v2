# Eventos operativos — 0.15.0+22

Implementación solicitada el 21/10/2026, America/Bogota, a partir de [los requerimientos acordados](37-requerimientos-eventos.md). Esquema v12; almacenamiento independiente del POS original.

## Uso

1. Abre **Eventos** y escribe el nombre que quieres encontrar en Ventas. La categoría siempre será **Evento**.
2. Indica el mínimo de personas, que sirve para calcular el PU y no limita las inscripciones.
3. Si existe un costo fijo, escribe el valor y elige **Caja** o **Nequi**. Se exige saldo suficiente.
4. Opcionalmente agrega varios productos del Catálogo y sus cantidades, por ejemplo premios. Se utilizan sus costos FIFO de inventario, nunca sus PVP.
5. Introduce el **PVP / inscripción** que cobrarás. Revisa los costos y pulsa **Crear evento**.
6. En **Ventas**, selecciona el evento, cantidad de inscripciones y Efectivo, Transferencia o Deudas como en cualquier línea. Puedes mezclar eventos y mercancía en una cuenta.

Si hay costo fijo positivo o al menos un producto, se exige mínimo mayor que cero, aunque los productos tengan costo real cero. Sin costo fijo ni productos se admite mínimo cero y se guarda PU cero. El PVP es independiente y en este incremento debe ser positivo, conforme al flujo de ventas vigente.

El PU es `(costo fijo + costo FIFO de productos) / mínimo`. Se redondea a la precisión del perfil con mitades hacia arriba, usando enteros y BigInt. Se guardan los costos totales originales exactos; el redondeo del PU no modifica el inventario ni los gastos.

## Dinero e inventario

Crear registra de forma atómica la ficha, el artículo de Catálogo, las salidas FIFO y el asiento del costo total. Debita Costos de eventos y acredita Inventario por los productos usados y Caja/Nequi por el costo fijo. Un evento sin costos conserva un documento y asiento sin líneas monetarias. No crea compras, ventas o deudas ficticias.

Las inscripciones se guardan en `sales` / `sale_lines`; el precio de la línea representa el PVP efectivamente cobrado. Las líneas de eventos tienen costo comercial cero y no generan `sale_outflows`: los costos ya quedaron registrados al crear. Las líneas físicas conservan su costeo FIFO habitual. Los cobros, abonos y las ventas a Deudas siguen sus reglas anteriores.

El resultado futuro puede calcularse sumando las líneas propias del evento y restando su costo original una sola vez. PVP − PU es un margen estimado según el mínimo; no vuelve a contabilizarse como gasto por inscripción. No se añade un reporte ni otra tabla de inscripciones.

## Guardado y disponibilidad

La preparación de creación persiste antes de confirmar. Las solicitudes pendientes aparecen en Eventos con **Reintentar creación** y **Descartar solicitud**. Se conservan la entrada exacta, la identidad, fecha y cotización; se vuelven a validar fondos, existencias y costos al confirmar. Si cambió el costo, se requiere descartar la solicitud y revisarla antes de crear otra. Repetir la misma confirmación recupera su resultado sin repetir descuentos. Ante un resultado incierto y una lectura fallida, el formulario permanece bloqueado para verificar/reintentar la misma solicitud.

El propietario confirmó que **Desactivar** aplica a todos los eventos. Está disponible desde Catálogo y la ficha creada en Eventos, con confirmación explicativa. Retira el evento de Catálogo y Ventas, conserva su ficha y ventas anteriores y no devuelve dinero ni productos. Las fichas desactivadas siguen visibles en el historial de Eventos. No hay acciones nuevas para mercancía física.

Los eventos activos aparecen en Catálogo aunque no tengan unidades físicas propias. Unidades y Proveedor muestran No aplica. Los productos físicos agotados mantienen su exclusión. Compras excluye los eventos creados y continúa ofreciendo solo Comestible y Artículo para nuevos ingresos.

## Almacenamiento y conservación

La migración v12 añade `event_requests`, `events`, `event_products` y `event_cost_allocations`. La asociación estable `events.product_id` distingue los servicios de los artículos físicos sin reconstruir la tabla histórica `catalog_items`. Añade vistas de uso compartido de capas y adapta las validaciones SQL de FIFO/ventas; las once migraciones publicadas conservan sus nombres y checksums.

El adaptador está en `lib/features/events/data/sqlite_events_store.dart`; dominio, controlador y presentación viven en el mismo módulo. Catálogo, Ventas, Compras y Tesorería consultan su asociación y movimientos. Los costos y consumos confirmados son inmutables, las identidades de comandos están reservadas globalmente y se rechazan movimientos retroactivos incompatibles.

Antes de actualizar la base propia se conserva un respaldo privado y se ensaya la migración en otra copia. La base original y la copia de producción no se utilizan ni se modifican en este incremento. Bases, respaldos y snapshots privados quedan fuera de Git y del ZIP.

## Límites

No incluye edición de eventos creados, reactivación, reintegros/anulaciones, eventos gratuitos, recurrencia automática, cupos, padrón nominal, emparejamientos ni reportes nuevos. Para otra realización con nuevos costos se puede crear otro registro con nombre identificable. La desactivación conserva los costos anteriores.

## Verificación

- Suite completa: **626 aprobadas, 3 omitidas por enlaces del host, cero fallos**. Después se añadió un caso específico de premios exclusivamente de costo cero, aprobado en la revisión enfocada final: 627 casos de aplicación distintos aprobados entre ejecuciones.
- Revisión enfocada final: **32 aprobadas**, de las cuales 31 son de aplicación y una genera la vista sintética. Cubre creación sin costos, mínimo, varios insumos, fondos, FIFO de compras/apertura/costo cero, ventas mixtas pagadas o fiadas, reintentos, fallo transaccional, reserva de identidades, inmutabilidad, desactivación, navegación y formulario estrecho.
- Análisis limpio y formato verificado en los **25 Dart modificados/nuevos**. Revisión local del código y las validaciones SQL; no se realizó una revisión por otro agente.
- Ensayo y migración real: **las 49 tablas anteriores conservan todos sus registros**, las cuatro nuevas están vacías y solo se agrega la fila de migración. Respaldo manual y automático conciliados, integridad correcta y cero violaciones de claves foráneas. Sin importar inventario o saldos otra vez ni registrar operaciones de prueba en el perfil activo.
- Windows release sin overrides, compilado en 66,01 segundos. ZIP y copias estable/versionada coinciden en sus 17 archivos y excluyen datos privados. Entrega publicada en `dist/ValinorSanctum2` y `dist/0.15.0/ValinorSanctum2`.
- Formulario inspeccionado en una imagen sintética. El primer intento de captura temporal quedó esperando las fuentes del arnés; se corrigió su carga y se repitió con éxito. La aplicación final se abrió y migró la base propia, pero el control nativo devolvió un identificador de ventana obsoleto también en recuperación. No se afirma recorrido nativo de formularios ni captura nativa; la ventana quedó abierta para el propietario.

Evidencia técnica sin datos privados: [events-operations.json](evidence/events-operations.json). El POS original no se ejecutó ni modificó por el agente.
