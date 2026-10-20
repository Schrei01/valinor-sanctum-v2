# Inventario inicial y catálogo con existencias — 0.9.0

El propietario pidió habilitar en Ventas el inventario de su copia, confirmó como reales los costos cero consultados y aclaró que los registros anteriores de 2.0 eran pruebas que deben conservarse aparte. La entrega crea un espacio independiente `valinor`; no mezcla ni borra el espacio `development` previo.

## Datos y uso

La copia actual tiene `proveedor` y `categoria`, y ya no tiene `lote`. La extracción admite ambas variantes y conserva el JSON v1 anterior; el formato v2 incluye proveedor/categoría. Se leen únicamente los productos, siempre en modo de lectura. El importador comprueba el SHA256 del mismo buffer que convierte a objetos antes de abrir el perfil destino.

La carga inicial crea catálogo, proveedores y cantidades en un perfil limpio. Se conservan todos los productos, incluidos los agotados, para permitir reposiciones posteriores desde Compras. Categorías de origen reconocidas: `producto` → Artículo, `comestibles` → Comestible y Evento → Evento. No se deduce un SKU ni se inventa un lote. Las cantidades, PVP y costos se concilian contra el corte privado. Los importes COP/2 del snapshot pasan a la escala del perfil solo si la conversión es exacta; no se truncan fracciones.

Catálogo muestra exclusivamente cantidades mayores que cero antes de aplicar filtros, búsqueda y paginación. Esto rige tanto para datos operativos como para una copia de consulta opcional. Un producto sin posición de stock se considera sin existencias para esa pantalla. Los agotados siguen en los datos y pueden reponerse desde Compras. Los filtros de la copia usan sus propios textos de categoría/proveedor; los de la app usan las relaciones operativas.

Ventas usa el inventario inicial junto con compras futuras. Una venta entrega, descuenta stock/costo y cobra de forma atómica como antes. Un costo cero confirmado se mantiene en cero y no crea gastos ficticios.

## Contabilidad y persistencia

Esquema v8 aditivo: `inventory_openings`, `inventory_opening_items` e `inventory_opening_allocations`, con vistas de lectura compartidas. Las migraciones v1–v7 permanecen intactas; una base anterior necesita respaldo verificado antes de actualizarse. La apertura existe una vez por perfil y exige catálogo/operaciones vacíos. Se conservan procedencia, hashes, identificación de la fila original, cantidades, precios, costos y confirmación de costo cero.

La apertura debita Inventario y acredita Patrimonio de apertura por el costo declarado. No crea compra, obligación, pago ni movimiento de dinero. Si el valor completo es cero, admite un asiento de apertura sin líneas monetarias mediante una excepción limitada a ese tipo de documento. No se flexibiliza el equilibrio del resto del diario.

La carga completa, incluido el perfil si se crea, es una transacción exclusiva. Una identidad de comando repetida con el mismo contenido recupera el resultado persistido; cualquier cambio de contenido se rechaza. Una segunda apertura con otro comando también se rechaza. No se emparejan productos por similitud de nombre ni se sobreescriben hechos anteriores.

FIFO consume primero las capas de apertura del producto y después sus compras posteriores. Las asignaciones entre ambos orígenes se validan juntas, con límites de cantidad/costo y orden. Las salidas de venta se restan una sola vez. Se rechazan ventas o recepciones anteriores al corte inicial del producto, incluidos productos agotados en ese corte. Los hechos y asientos publicados son inmutables.

## Espacios locales

El selector privado `data/development/active-workspace.json` elige el perfil al iniciar el bundle normal. Solo contiene versión de formato e ID de perfil, dentro de las mismas restricciones de rutas y nombres de StoragePaths. No mueve archivos ni importa nada durante el arranque. Una selección inválida falla de forma visible; los entornos de prueba y las configuraciones explícitas mediante defines la ignoran.

El perfil anterior queda en `data/development/development`; el nuevo está en `data/development/valinor`. La extracción privada para esta carga está en `data/development/imports/reference-inventory.json`. No se instala como copia de consulta en el perfil operativo, por lo que Catálogo muestra directamente el inventario vendible. Bases, selector, snapshots, cifras y nombres reales quedan fuera de Git y ZIP.

Efectivo y Nequi empiezan sin saldos importados. Si corresponde declarar dinero inicial, se hace en Compras antes del primer movimiento de cada cuenta. La apertura de inventario no consume ese dinero. No se importan ventas ni movimientos monetarios de la copia.

Las herramientas de extracción/importación son locales de administración. No sustituyen un flujo general de migraciones, ajustes, reversas o sincronización con el POS anterior. El POS original permanece sin abrir ni modificar.

## Verificación de esta entrega

- Suite completa: 428 pruebas aprobadas y tres omitidas porque el host no puede crear los enlaces que necesitan esas pruebas. Incluye migración/respaldo v7→v8, guardas de apertura e inmutabilidad, atomicidad/reintento, conversión de escala, costo cero, venta/cobro y FIFO mixto, selector de perfil y filtros de existencias.
- Análisis estático sin incidencias; 101 archivos Dart formateados, comprobación final sin cambios. Comparación ejecutable de las siete migraciones publicadas contra HEAD anterior: todos los checksums iguales.
- Revisión independiente final sin hallazgos pendientes; se reforzaron la verificación del hash del mismo buffer leído y la exclusión del selector ante defines explícitos.
- Carga real conciliada por identificador de origen: nombres, cantidades, PVP, costos, categorías y proveedores coinciden. Una apertura, asiento Inventario/Patrimonio exacto, sin compras, pagos, deudas ni ventas creadas por la carga. La huella de la copia de origen permanece igual.
- Comparación de lectura de las 42 tablas del espacio anterior antes de cargar y después de abrir el nuevo bundle: todos sus registros iguales, esquema v7 conservado. Respaldo verificado del perfil nuevo antes de su primera venta, con sus 45 tablas iguales al original.

El bundle Windows final 0.9.0+12, sin defines de Sanctum, compiló en 66,22 s. Se publicó en el acceso estable y se verificaron sus 17 archivos contra ZIP y copia `dist/0.9.0/ValinorSanctum2`. El ZIP tiene 14.643.828 bytes, SHA256 `385B8093788D7C7D9A1D1C6A7ECE0CCAD34778AA9E9671A3CD4B688AD0389155`, sin bases, snapshots ni selector privados.

La apertura nativa confirmó versión, catálogo operativo con el número correcto de productos con existencias, filtros Categoría/Proveedor y ausencia de agotados/controles de modificación. Ventas abrió con Nueva cuenta y sin error de carga. Se observó por accesibilidad y teclado; no se registraron ventas ni borradores de prueba y no se capturaron imágenes o nombres/precios reales para documentación. La app se dejó abierta en Ventas para el propietario. Al verificar, la base nueva estaba íntegra, con cero violaciones de claves foráneas y Efectivo/Nequi preparados sin saldo; los cambios posteriores que haga el usuario quedan fuera de esa comprobación.

La evidencia de verificaciones y entrega se conserva en [inventory-opening.json](evidence/inventory-opening.json); las conciliaciones de datos reales permanecen en archivos privados locales.
