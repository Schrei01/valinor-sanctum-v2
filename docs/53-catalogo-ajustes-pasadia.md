# Catálogo: estimado de inventario, Ctrl+D y Pasadía — 0.23.0

## Solicitud y alcance

27/10/2026: mostrar a la derecha el total de unidades × PVP del catálogo; Ctrl+D solo en Catálogo para descontar unidades hasta cero; ocultar productos físicos agotados; Pasadía fuera de Compras y siempre vendible sin límite, conservando sus cantidades vendidas en Reportes.

El propietario eligió **solo «Pasadía»**. «Pasadía 2», «PASADIA TALLER STAR» y «pasadia taller tarot» mantienen su clasificación y comportamiento anteriores.

## Uso

- El recuadro muestra el estimado a PVP de todos los productos físicos con existencias, incluidos los archivados que ya mostraba el catálogo. No cambia al buscar, filtrar ni cambiar de página. Excluye servicios y eventos sin stock propio; usa enteros exactos aun si la suma supera un entero SQLite.
- En Catálogo, pulsa **Ctrl+D**, busca un producto por nombre/SKU, selecciónalo y escribe **unidades a descontar**, no el saldo final. La vista previa indica cuántas quedarán. El motivo es opcional. Pulsa **Descontar unidades**.
- Se rechazan cantidades vacías, fraccionarias, negativas, cero o superiores a las existencias. Puede descontarse todo el saldo. Un producto físico agotado deja de mostrarse y el estimado se actualiza.
- No se genera una venta, una deuda ni un movimiento de Caja/Nequi. El costo FIFO de las unidades retiradas pasa de Inventario a Ajustes de inventario; por eso una merma es un gasto contable sin salida de dinero.
- Las solicitudes se guardan antes de confirmar. Ante respuesta incierta, «Reintentar mismo descuento» recupera la misma operación sin repetir unidades. Una solicitud no registrada puede descartarse para corregirla; no se borran descuentos confirmados.
- Ctrl+D funciona al entrar en Catálogo y mientras se usa su buscador; no actúa en otras secciones ni abre diálogos adicionales sobre un modal.

## Pasadía y conservación

Se conserva el identificador, PVP e historial del producto existente. `catalog_services` lo identifica como servicio ilimitado; no se fabrican productos, eventos o ventas. Sus cantidades de apertura se conservan como hechos históricos, pero no limitan ventas futuras ni se incluyen en el estimado físico. La conversión exige que no exista costo físico pendiente, evitando esconder valor de inventario.

Pasadía se excluye del selector de Compras y no se permite ingresarlo como nueva mercancía. Ventas registra precio, importe, pago y cantidad en las tablas normales de ventas; no consume lotes ni repite costos. Reportes muestra esas ventas e inscripciones con sus cantidades.

## Persistencia y verificación

Migración aditiva v15→v16, sin modificar migraciones/checksums v1–v15. Añade cuatro tablas: `catalog_services`, `stock_adjustment_requests`, `stock_adjustments` y `stock_adjustment_allocations` (68 en total). Amplía las vistas/guardas de consumo FIFO para compartir existencias entre ventas, eventos y ajustes, preservando sus reglas de costo, orden cronológico y atomicidad. Los registros de ajustes y sus asientos son inmutables. No hay ajuste positivo ni reversa en este incremento.

Archivos principales: esquema/migrador, modelo y almacenes de inventario/ventas/compras, diálogo y presentación de Catálogo, atajo del contenedor de la app y pruebas de migración, transacciones e interfaz. También se sincroniza el pie de versión con 0.23.0.

Suite completa: **739 aprobadas**, tres omitidas por enlaces simbólicos de Windows; análisis sin incidencias. Los 17 casos nuevos cubren agotamiento, costos FIFO y costo cero, aperturas, consumo posterior por ventas/eventos, reintentos, solicitudes concurrentes, rollback, cronología, clasificación exacta, cantidades de Pasadía en Reportes, migración/respaldo, alcance del atajo, filtros/páginas y sumas grandes. Un render sintético adicional produjo tres imágenes inspeccionadas (catálogo amplio, menú de descuento y catálogo estrecho).

La copia real privada migró a v16: todas las filas/definiciones de las 64 tablas anteriores y los 15 registros de migración se conservaron; una clasificación de servicio, ningún ajuste creado, integridad correcta y cero FK. Se comprobó disponibilidad ilimitada en Ventas y exclusión de Compras. Resultados de publicación, respaldo cerrado y conservación de la base activa: `docs/evidence/catalog-stock.json`.

Publicado y verificado: ejecutable 0.23.0+36, pie 0.23.0; ZIP/estable/versionada idénticos en sus 17 archivos y sin datos privados, anteriores limpiados. App abierta y proceso respondiendo. La base activa migró con respaldo manual y automático v15; conserva las 64 tablas previas y todos sus registros, 15 migraciones originales, una clasificación de servicio y ningún ajuste creado, integridad correcta y cero FK. Conservación repetida tras iniciar la app. No se recorrió la GUI nativa ni se realizaron descuentos comerciales reales.
