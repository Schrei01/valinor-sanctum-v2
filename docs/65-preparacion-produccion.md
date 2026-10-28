# Preparación de una base compatible para revisión en desarrollo

El propietario autorizó el28/10/2026 tomar el archivo de producción indicado, organizar su catálogo y repartir su cartera entre las personas e importes proporcionados. La entrega sustituye únicamente la base de desarrollo, con respaldo. No modifica el origen ni la base de la edición instalada en Documentos.

## Preparación

La fuente se abrió SQLite en modo solo lectura. `VACUUM INTO` generó una copia consistente independiente dentro del proyecto; su SHA256 se comprobó contra el origen antes y después del proceso. Desde esa copia se preparó un perfil limpio Valinor/COP/0 decimales con esquema18.

Se clasificaron174 productos con proveedor y categoría. Se conservaron nombres, PVP, costos, cantidades e identificadores originales mediante el inventario de apertura y su correspondencia de IDs. La app usa los nombres canónicos **Artículo**, **Comestible**, **Evento** y **Pasadía**. El importador de aperturas ahora acepta Pasadía y las variantes plurales de estas categorías, sin mezclarlas. No cambia el esquema ni los datos de perfiles existentes.

Los productos de Pasadía quedan separados de los eventos. Solo el nombre exacto Pasadía conserva el tratamiento ilimitado que ya ofrece la app. Los eventos históricos conservan sus cantidades originales; no se recrean como eventos nuevos ni se repiten costos o premios históricos.

Las cuatro cuentas monetarias/de cartera se abrieron con sus saldos de corte, conservando el saldo negativo de reserva del origen. La cartera se distribuyó con **deuda anterior incluida en el saldo importado**, sin registrar nuevas ventas ni duplicar deuda. Los ocho titulares suman exactamente la cartera importada y no queda parte sin asignar.

Las ocho tablas antiguas se archivaron dentro de SQLite:11.420 filas, comparadas campo por campo con la copia de origen. Se conservaron152 ventas cuyo producto ya no existe y dos saldos sin fecha. Reportes mantiene las advertencias y estimaciones históricas existentes; no se inventan fechas ni importes desconocidos.

## Verificación

- Once pruebas de aperturas aprobadas, incluido un caso sintético nuevo con las cuatro categorías y el servicio ilimitado. Análisis de código limpio.
- Conciliación completa de catálogo, precios, costos, proveedores, unidades y saldos mediante los lectores de la app.
- Ensayo exclusivamente sobre una copia desechable: venta dividida, deuda al titular correcto, cobro, descuento de stock, reintento sin duplicación, abono, evento nuevo disponible, Pasadía ilimitado, ocultación de agotados y Reportes. La candidata de entrega conservó su SHA256 durante las pruebas.
- Salud de la base:69 tablas, esquema18, integridad correcta, cero violaciones FK y verificaciones de identidad y migraciones correctas.

Se verificó también el JSON de historial de Tesorería contra la huella guardada en su apertura. La primera candidata usaba una representación serializada distinta para esa huella; se regeneró antes de activar con la huella de los bytes del archivo que se entrega.

## Activación

Con la confirmación del propietario de que la app estaba cerrada, se respaldaron la base anterior, su historial de Tesorería y el selector local. La sustitución se hizo con reemplazo atómico de archivo y comprobación de huellas. El selector y la ruta de desarrollo se conservan. La entrega incluye **sanctum2.sqlite3** y **legacy-treasury.json**; ambos deben permanecer juntos para ofrecer también el historial de Tesorería.

Antes de iniciar, las69 tablas coincidían exactamente con la candidata. Después de abrir, todos sus valores se conservaron: la única adición fue la cuenta interna de gastos que la app crea normalmente al arrancar, sin asiento ni saldo. Se verificó explícitamente esa fila y que ninguna otra tabla cambiara. El archivo original y la base instalada de Documentos conservaron sus bytes.

La app queda abierta y responde en0.30.0. La lectura de accesibilidad de Catálogo confirmó existencias, categorías y proveedores. Los clics por accesibilidad fallaron por geometría y la captura nativa expiró; no se atribuye inspección visual de las otras pantallas. Sus datos se verificaron por los lectores de la app y el ensayo aislado. No se registraron operaciones comerciales de prueba en la base activada.

Los archivos, nombres, importes, clasificación individual, huellas privadas y rutas de respaldo precisas permanecen en carpetas locales ignoradas por Git. `imports/production-20261028/revision.md` contiene el informe privado completo. Solo se versionan el soporte genérico de categorías, su prueba y esta evidencia sanitizada. No se necesita un nuevo ejecutable para este cambio de datos; no se publica instalador.
