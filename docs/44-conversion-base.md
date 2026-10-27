# Base convertida — 0.18.0, esquema v14

El propietario autorizó convertir los datos de `Valinor - Copia` a una `sanctum2.sqlite3` compatible y sustituir la base activa con respaldo y conciliación. La fuente se conserva intacta. La conversión parte de una copia consistente de la base operativa propia, por lo que conserva productos, existencias, identificadores, configuraciones, solicitudes y movimientos registrados desde las aperturas originales.

## Datos conservados

- Las ocho tablas de origen se conservan completas en `legacy_source_rows`, con tabla, identificador y JSON de cada fila, junto al esquema de origen y huellas en `legacy_conversions`. No se incluyen datos reales en Git ni en el ZIP.
- Los cuatro historiales de saldos se convierten a enteros monetarios exactos en `legacy_balance_history`, sin redondeo. Las fechas originales se conservan junto a su interpretación UTC; las fechas sin zona se interpretan como Bogotá.
- Los saldos con fecha idéntica se ordenan por identificador de origen; el mayor es el último. Se conservan las fracciones de segundo. Los saldos sin fecha permanecen archivados y no se les asigna una fecha inventada.
- Las ventas de origen carecen de precio y costo históricos; algunas se refieren a productos que fueron eliminados. Todas se archivan con sus campos originales. No se convierten en nuevas ventas operativas ni se les atribuye el precio actual del catálogo.
- El inventario y los saldos ya importados no se vuelven a ingresar. Las últimas filas de saldos y todos los productos de apertura deben conciliar exactamente con la fuente antes de aceptar la conversión. Las filas operativas existentes no se modifican.

## Compatibilidad y consulta

La migración v14 añade tres tablas, un índice y protecciones de inmutabilidad. Las migraciones v1–v13 conservan su contenido y sus verificaciones. El importador escribe en una sola transacción y sella el archivo histórico al completar las ocho tablas y los saldos. Los reintentos de la misma fuente recuperan el resultado; otra fuente o una importación incompleta se rechazan.

Reportes consulta el último saldo histórico anterior a cada extremo cuando ese extremo precede a la apertura operativa. Desde la apertura usa exclusivamente el libro de Sanctum 2.0. Nunca suma el saldo histórico a la apertura, ni vuelve a descontar inventario por ventas anteriores. Así pueden consultarse fechas anteriores sin depender de abrir el archivo fuente. Sin un saldo fechado previo, se conserva **Sin información**.

La pantalla mantiene fecha → hora AM/PM y únicamente los saldos iniciales y finales de Caja y Nequi. Identifica cuándo usa el historial convertido.

## Herramienta

`tool/convert_legacy_database.dart` exige `--source`, `--base`, `--output` y `--apply`. Abre la base propia de origen en modo solo lectura y usa `VACUUM INTO` para obtener una copia consistente, incluyendo páginas confirmadas del WAL. La salida debe ser nueva y quedar dentro del proyecto; la herramienta nunca activa una base ni sobrescribe un archivo existente. Migra solo la candidata, importa, concilia y comprueba integridad. Rechaza fuentes con auxiliares SQLite activos, tablas inesperadas, fechas inválidas, pérdida de precisión o procedencia distinta de las aperturas.

La sustitución de la base activa es un paso posterior, con todas las ventanas de la aplicación cerradas, respaldo verificado y comprobación de que no cambió desde la preparación. Debe usarse la aplicación 0.18.0 o posterior, compatible con esquema14.

## Verificación y entrega

Se incorporaron 11.155 filas de las ocho tablas: 173 productos, 4.305 ventas, 5.938 saldos y el resto de movimientos. Se preservaron las 152 ventas cuyo producto no existe y los dos saldos sin fecha. Todas las filas archivadas se compararon campo por campo con la fuente. Las filas anteriores de las 60 tablas propias permanecen iguales, con la única adición esperada de la migración14 a su historial de esquema.

La ejecución de fundación aprobó 67 casos de base de datos/Reportes; la migración específica v13→v14 aprobó su caso adicional. La ejecución final enfocada aprobó 39 casos: seis de conversión, 16 del lector de Reportes, nueve de controladores/fechas, siete de formulario y uno de navegación. La prueba de venta posterior se repitió además retirando la fuente sintética de su ruta, con éxito: la base convertida funciona por sí sola. Una captura sintética pasó y se inspeccionó. No se repitió la suite completa. Hubo errores de preparación del fixture nuevo (tipo y motivo de transferencia), corregidos antes de la ejecución final; no se atribuye éxito a esas ejecuciones fallidas.

Análisis final limpio y 15 Dart con formato revisado. Se comprobaron reintentos, sellado inmutable, rechazo de fuente distinta, fechas duplicadas/fracciones, conservación de saldos desconocidos, rollback de una inserción fallida, no duplicación de dinero/inventario y venta nueva operativa. Ocho rangos reales de la candidata se contrastaron con cálculos independientes de las tablas de origen y el libro nativo, incluyendo una fecha anterior a la apertura, su solapamiento y fechas posteriores; todos coincidieron. La lectura se repitió sobre la ruta activa con salud completa correcta.

Se publicó 0.18.0+27 sin overrides, con esquema14. ZIP, estable y versión extraída coinciden en 17 archivos y excluyen datos privados. Las entregas 0.17.2 anteriores se eliminaron mediante la política de retención. No se afirma un nuevo recorrido de UI nativa; formulario y aviso se comprobaron en widgets e imagen sintética.

Con la app cerrada y ambas fuentes sin cambios desde la preparación, se copió la candidata validada y se sustituyó `data/development/valinor/sanctum2.sqlite3`. El archivo original activo quedó preservado en `backups/legacy-conversion-20261026/active-before-replacement.sqlite3`; existe además el respaldo consistente `before.sqlite3`. Ambos se verificaron contra las 60 tablas previas. La salida compatible se conserva también en `imports/converted-valinor-20261026/sanctum2.sqlite3`, privada y fuera de Git. El selector sigue apuntando al mismo perfil `valinor`.

Tras activar: esquema14, integridad correcta, cero FK, archivo activo idéntico por SHA-256 a la candidata validada, ocho reportes leídos y reintento idempotente sin operaciones nuevas. Los documentos operativos anteriores y sus saldos permanecen; la fuente original conserva su SHA-256. La aplicación queda cerrada para que el propietario abra el acceso habitual. Ver [evidencia](evidence/legacy-conversion.json).
