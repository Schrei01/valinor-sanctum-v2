# Diagnóstico técnico del POS original

Fecha: 18 de octubre de 2026 (Bogotá). Revisión de referencia: b94861326bcd9936a9515c104897703cb4f65347.

## Alcance y método

Auditoría estática del código fuente y configuración. Se inspeccionaron los 31 archivos Dart de lib, el test disponible, dependencias declaradas y resueltas, construcción Windows, instalador y metadatos de plataformas. Los informes de [persistencia](02-auditoria-datos.md) y [operación](03-auditoria-operacion.md) detallan reglas y ubicaciones.

No se ejecutó el original, no se abrió una base de datos real, no se inspeccionaron datos del negocio y no se ejecutaron migraciones ni comandos de restauración. Los defectos se sustentan en rutas de código; no se presentan como pruebas de ejecución. Se registró un manifiesto SHA-256 del árbol, incluido .git, para verificar la conservación de contenido.

## Arquitectura real

Aplicación Flutter Desktop con una ventana, navegación inferior y cuatro secciones. El arranque carga cinco providers persistentes antes de runApp; las cuentas abiertas se crean en memoria. Existe separación por carpetas, pero las responsabilidades se mezclan: pantallas coordinan escrituras, providers acceden directamente a SQLite y Account está definido dentro de la pantalla de ventas.

~~~text
lib/main.dart              arranque, inyección y navegación
lib/screens/               inventario, ventas, reportes, administración
lib/screens/reports/       controller y componentes de reportes
lib/screens/management/    diálogos de gastos/transferencias/aportes y paneles
lib/providers/             seis ChangeNotifier; saldos, movimientos y cuentas
lib/models/                Product y SaleLine; este último depende de Flutter
lib/widgets/               formularios, listas y líneas de venta
lib/db/database_helper.dart  singleton, esquema, migraciones, CRUD y consultas
assets/                    logo
test/                      una prueba de plantilla
.github/workflows/         construcción y publicación del instalador
Output/                    instalador .exe versionado
~~~

Flujo real de venta: widgets y controllers mutables → validación por línea en pantalla → inserción individual de sales → descuento condicional de products → incrementos asincrónicos de saldos → eliminación de cuenta en memoria. No hay una transacción única, cabecera de venta, documento de cobro ni registro completo de partidas financieras.

## Stack y construcción

| Elemento | Observación local |
|---|---|
| Lenguaje/UI | Flutter/Dart; pubspec solicita Dart ^3.8.1 |
| Restricciones resueltas | pubspec.lock indica Dart >=3.9.0-0 <4.0.0 y Flutter >=3.27.0; no equivalen a SDK instalado |
| CI | Flutter 3.35.2 configurado para Windows |
| SQLite | sqflite_common_ffi 2.3.6; transitivas sqflite_common 2.5.6 y sqlite3 2.9.0 |
| Estado/inyección | provider 6.1.5 resuelto |
| Rutas/datos | path 1.9.1; path_provider 2.1.5 |
| Formato | intl 0.18.1; formatos monetarios es_CO |
| Gráficos | fl_chart 0.68.0 |
| Otras | uuid 4.5.1; google_fonts 6.3.0 declarado, sin uso encontrado en lib |
| Calidad | flutter_lints 5.0.0 y un widget_test de contador |
| Distribución | Inno Setup; ejecutable existente de unos 10,4 MiB |

No se evaluó actualización de paquetes ni se cambió resolución de dependencias. Flutter y Dart no se encuentran en PATH; no se ejecutaron analyze, test o build. La carpeta tiene plantillas de Android/iOS/web/Linux/macOS/Windows, pero eso no demuestra soporte funcional de todos esos destinos: la persistencia está orientada a SQLite FFI y la distribución configurada es Windows.

La identidad de producto sigue utilizando nombres de plantilla com.example en plataformas. El .iss contiene una ruta absoluta de otra máquina y el workflow referencia path/to/your_script.iss y YourInstaller.exe. La etapa de publicación no está lista para reproducirse desde este checkout. No se ejecutó el instalador ni se verificó su correspondencia con el código.

## Inventario funcional

| Capacidad | Situación observada | Tratamiento 2.0 |
|---|---|---|
| Catálogo y reposición | Nombre, cantidad, precio, costo y lote textual; reposición por nombre suma stock | Conservar flujo, separar entradas e identidad |
| Búsqueda | Coincidencias parciales y autocomplete; agotados ocultos | Adaptar selección por ID y mostrar agotados |
| Ajustes y eliminación | Cantidad negativa con control de UI; borrado físico | Reimplementar ajustes con motivo y archivo |
| Ventas de productos | Varias líneas y método por línea | Conservar operación; documentos y cobros separados |
| Cuentas abiertas | Nombre, UUID y líneas; solo en memoria | Reimplementar persistencia y recuperación |
| Tesorería | Caja, Nequi, Caja Mayor y Deudas como totales sucesivos | Reimplementar como cuentas y libro trazable |
| Gastos | Egreso con motivo de lista fija y descuento de saldo | Conservar intención; categorías configurables |
| Transferencias | Dos cambios de saldo independientes | Reimplementar atómicamente con dos partidas |
| Aportes | Incremento de Caja Mayor sin origen documentado | Reimplementar aportes/retiros diferenciados |
| Reportes | Rango con hora, unidades, ventas, costos calculados y pagos por método | Conservar preguntas; rehacer consultas |
| Historial | Diez movimientos recientes; principalmente egresos | Ampliar a trazabilidad íntegra |
| Usuarios/permisos | Sin usuarios ni roles; una credencial incrustada para ajustes | Sustituir control de UI; no copiar credencial |
| Compras/proveedores | No identificados como entidades | Nuevos |
| Servicios/eventos/torneos/pasadías | No identificados como entidades | Nuevos |
| CxC/CxP detalladas | No existen; Deudas es un total ambiguo | Nuevas, sujetas a clasificación por contraparte |
| Devoluciones/anulaciones/arqueos | No identificados | Nuevos |
| Recomendaciones/escenarios/objetivos | No identificados | Nuevos y configurables |
| Exportación/backups/importador | No identificados en código | Nuevos |

## Riesgos prioritarios

Prioridad P1 = posible pérdida o distorsión operativa/financiera; P2 = integridad analítica y mantenibilidad importante; P3 = calidad de interfaz y desarrollo. Son prioridades de este diseño, no incidentes de producción confirmados.

| ID | Prioridad | Hallazgo y consecuencia |
|---|---|---|
| R01 | P1 | cash y nequi se crean sin fecha, aunque escrituras y consultas la necesitan; instalaciones nuevas pueden fallar al registrar saldos/reportes |
| R02 | P1 | Migraciones tienen rutas SQL inconsistentes; fecha de Nequi no se agrega y hay ALTER con valor DEFAULT incompleto |
| R03 | P1 | Venta se inserta antes del descuento de stock; no se verifica cantidad de filas ni se confirma todo junto |
| R04 | P1 | Validación separada de líneas repetidas o cuentas con stock desactualizado permite vender sobre disponibilidad |
| R05 | P1 | Saldos se modifican sin esperar confirmación; UI elimina cuenta y puede anunciar éxito antes de persistir dinero |
| R06 | P1 | Cuentas abiertas se pierden al reiniciar y pueden descartarse sin confirmación |
| R07 | P1 | Gastos, transferencias y aportes carecen de confirmación atómica y trazabilidad suficiente |
| R08 | P1 | Nombre escrito en autocomplete puede diferir del producto previamente seleccionado y cobrado |
| R09 | P1/P2 | No hay autorizaciones reales; credencial compartida de inventario está en código y no se valida en DB |
| R10 | P2 | Reportes multiplican ventas históricas por precio/costo actual; cambiar catálogo reescribe resultados pasados |
| R11 | P2 | Borrado de producto y JOIN interno pueden hacer desaparecer ventas de reportes |
| R12 | P2 | Saldos iniciales del negocio están codificados; no hay declaración de apertura ni origen |
| R13 | P2 | Deudas se trata como cuenta transferible sin distinguir activo/pasivo; no admite análisis fiable de obligaciones |
| R14 | P2 | Dinero REAL/double, entradas no finitas/precios negativos sin control suficiente y ausencia de precisión explícita |
| R15 | P2 | Histórico monetario parcial impide reconstruir saldos y conciliar caja |
| R16 | P2 | README/test son plantillas; CI no corre pruebas y contiene rutas de ejemplo; instalador depende de otra máquina |

Evidencias representativas: [esquema y migraciones](C:/proyectos/valinor_ludoteca/lib/db/database_helper.dart:57), [registro de venta](C:/proyectos/valinor_ludoteca/lib/db/database_helper.dart:306), [actualización de saldos](C:/proyectos/valinor_ludoteca/lib/screens/ventas_screen.dart:267), [reporte con precios actuales](C:/proyectos/valinor_ludoteca/lib/db/database_helper.dart:452), [prueba disponible](C:/proyectos/valinor_ludoteca/test/widget_test.dart:14).

## Semántica de reportes

El rango de fechas incluye hora elegida por el operador. No se debe clasificar automáticamente como error la selección de horas: el producto futuro ofrecerá períodos completos con límites explícitos y selección horaria cuando corresponda.

El controller calcula totalGanancias a partir de costo de catálogo, pero TotalsSection no lo muestra. ReportPieChart etiqueta Ganancia a ventas menos egresos, sin costo de mercancía, limita pérdidas a cero y coloca ventas, egresos y ese resultado como partes de un mismo total. Esa gráfica no representa una composición financiera válida. Debe reemplazarse por indicadores separados y puente de resultados, conservando la pregunta comercial.

loadReport carece de try/finally; una excepción puede dejar loading activo. El botón puede lanzar consultas superpuestas y actualizar con un rango anterior. No hay contrato de calidad de datos, cobertura de costos ni distinción entre sin datos, cero y error.

## Reutilización proporcionada

| Componente | Decisión | Qué se aprovecha |
|---|---|---|
| Marca, logo y etiquetas | Conservar funcionalmente | Identidad conocida; copiar activo solo durante implementación autorizada |
| Pantallas principales | Adaptar | Organización reconocible, navegación y tareas habituales |
| Formularios/listas/autocomplete | Adaptar partes de presentación | Estructura visual y formato; corregir ID, estados y validaciones |
| Cards y selector de fechas | Adaptar | Presentación desacoplada del origen de saldos y rangos |
| Gráficas | Adaptar componentes visuales | Reemplazar datos y semántica; no reutilizar cálculos incorrectos |
| Provider/ChangeNotifier | Conservar como herramienta | Inyección y estado UI; sin reglas financieras ni SQL en widgets |
| Modelos Product/SaleLine/Account | Reimplementar modelo | Rescatar campos y conceptos; quitar controllers/foco del dominio |
| DatabaseHelper, setters de totales | Reimplementar | Rescatar diccionario y compatibilidad de lectura; no copiar migraciones |
| SQL de reportes | Reimplementar | Conservar preguntas; snapshots y fuentes transaccionales nuevas |
| Prueba de contador | Reemplazar | No cubre el producto actual |
| Scripts Windows | Rehacer configuración | Conservar elección de distribución; rutas relativas y nueva identidad |

No se propone trasladar toda la aplicación ni descartarla en bloque. Las piezas puramente visuales podrán adaptarse con revisión y pruebas; la confiabilidad transaccional exige un núcleo nuevo.

## Límites de lo que sabemos

No se conoce el esquema efectivo, integridad, versión ni volumen de la base productiva. Tampoco se sabe si el instalador existente corresponde a esta revisión. La auditoría no demuestra pérdidas reales ni evalúa cómo opera hoy el propietario fuera del software. Antes de migrar habrá que resolver Deudas, saldos de apertura, costos faltantes, significado de cuentas abiertas y capacidad de reconstruir el histórico.

Las decisiones propuestas, el esquema preliminar, la matriz de preguntas, la importación futura y los incrementos están en los documentos 04 a 08. Ningún componente ejecutable se ha construido en esta fase.
