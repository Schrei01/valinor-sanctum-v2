# Auditoría de datos del proyecto original

Fecha de referencia: 18 de octubre de 2026, America/Bogota.

## Alcance y límites de la evidencia

Se revisaron por completo, mediante lectura estática, `lib/db/database_helper.dart`, los dos archivos de `lib/models/` y los seis de `lib/providers/` del original ubicado en `C:/proyectos/valinor_ludoteca`. Para comprobar los puntos de integración se leyeron también `lib/main.dart`, `lib/screens/ventas_screen.dart`, los widgets de producto y de línea de venta, y los diálogos de administración.

No se abrió ninguna base de datos, no se ejecutó Flutter, Dart, pub, un formateador ni una migración. No se modificó el proyecto original. Este documento se escribe únicamente en el repositorio nuevo autorizado. Los escenarios descritos son consecuencias del código, no resultados de pruebas en ejecución. El esquema real de la instalación existente y su historial de migraciones permanecen sin inspeccionar; pueden diferir de lo que crea el código actual.

Las referencias enlazan al original con rutas absolutas. Los números de línea corresponden a la lectura realizada para esta auditoría.

Se usa esta escala de prioridad:

- **P1 — Alta:** puede impedir una operación principal, alterar datos financieros o perder trazabilidad de ventas.
- **P2 — Media:** falta de una regla de integridad, pérdida de información operativa o riesgo concreto bajo una condición adicional.
- **P3 — Baja:** acoplamiento, manejo de recursos o deuda técnica que dificulta una evolución segura.

## 1. Ubicación, apertura y responsabilidades

[DatabaseHelper:7](C:/proyectos/valinor_ludoteca/lib/db/database_helper.dart:7) es un singleton con una conexión estática. Inicializa `sqflite_common_ffi`, obtiene el directorio de documentos del usuario y abre `valinor.db`; declara versión **13** en [DatabaseHelper:14](C:/proyectos/valinor_ludoteca/lib/db/database_helper.dart:14).

El archivo no separa creación de esquema, migraciones, repositorios de productos, operaciones de venta, movimientos financieros y consultas de reportes. No contiene transacciones explícitas para las operaciones de negocio, activación explícita de claves foráneas, restricciones `CHECK`, restricciones `UNIQUE`, índices adicionales ni una política de respaldo o recuperación. Esto describe el código observado; no acredita la configuración de una base ya existente.

[main:19](C:/proyectos/valinor_ludoteca/lib/main.dart:19) carga de forma secuencial los saldos y últimos movimientos antes de `runApp` en la línea 34. No hay manejo de error alrededor de esta inicialización: un fallo de apertura, migración o consulta puede impedir que se llegue a mostrar la aplicación. En una base recién creada el arranque puede completarse porque Caja y Nequi ya tienen filas iniciales y su primera lectura no necesita la columna `fecha`.

## 2. Inventario de tablas del esquema creado desde cero

Esta tabla refleja exclusivamente las sentencias de `onCreate`, no la inspección de una base de producción.

| Tabla | Columnas y restricciones declaradas | Estado inicial | Fuente |
| --- | --- | --- | --- |
| `products` | `id INTEGER PRIMARY KEY AUTOINCREMENT`; `name TEXT NOT NULL`; `quantity INTEGER NOT NULL`; `price REAL NOT NULL`; `purchasePrice REAL NOT NULL DEFAULT 0`; `lote TEXT NOT NULL DEFAULT ''` | Sin productos | [DB:101](C:/proyectos/valinor_ludoteca/lib/db/database_helper.dart:101) |
| `sales` | `id INTEGER PRIMARY KEY AUTOINCREMENT`; `productId INTEGER NOT NULL`; `quantity INTEGER NOT NULL`; `paymentMethod TEXT NOT NULL`; `date TEXT NOT NULL`; FK declarada de `productId` a `products.id`, sin política explícita de borrado | Sin ventas | [DB:113](C:/proyectos/valinor_ludoteca/lib/db/database_helper.dart:113) |
| `cash` | `id INTEGER PRIMARY KEY AUTOINCREMENT`; `total REAL NOT NULL` | Una fila con `167000.0` | [DB:89](C:/proyectos/valinor_ludoteca/lib/db/database_helper.dart:89) |
| `nequi` | `id INTEGER PRIMARY KEY AUTOINCREMENT`; `total REAL NOT NULL` | Una fila con `4000.0` | [DB:57](C:/proyectos/valinor_ludoteca/lib/db/database_helper.dart:57) |
| `caja_mayor` | `id INTEGER PRIMARY KEY AUTOINCREMENT`; `total REAL NOT NULL`; `fecha TEXT`, nullable | Sin filas | [DB:69](C:/proyectos/valinor_ludoteca/lib/db/database_helper.dart:69) |
| `deudas` | `id INTEGER PRIMARY KEY AUTOINCREMENT`; `total REAL NOT NULL`; `fecha TEXT`, nullable | Sin filas | [DB:79](C:/proyectos/valinor_ludoteca/lib/db/database_helper.dart:79) |
| `movimientos` | `id INTEGER PRIMARY KEY AUTOINCREMENT`; `tipo TEXT`; `cuenta TEXT`; `monto REAL`; `motivo TEXT`; `fecha TEXT`. Todos los campos salvo la PK permiten NULL | Sin movimientos | [DB:44](C:/proyectos/valinor_ludoteca/lib/db/database_helper.dart:44) |

No se crean tablas de encabezados de venta, pagos independientes, cuentas abiertas, clientes, proveedores, detalle de deudas, compras, movimientos de inventario, cierres de caja, usuarios, auditoría o respaldos. `sales` representa una línea de producto vendida, aunque su nombre sugiera una venta completa.

Las cuatro tablas financieras almacenan **fotografías sucesivas de saldo**, no movimientos contables. `movimientos` es un registro separado que no referencia esas fotografías ni una venta. `cuenta` y `paymentMethod` son texto libre en la persistencia; no existe un catálogo referenciado por identificador.

### Información que la venta no conserva

La fila de `sales` no guarda nombre del producto, precio unitario, costo unitario, importe, moneda, descuento, identificador de cuenta abierta ni identificador de comprobante. Tampoco permite identificar con certeza qué líneas integraban un mismo cobro. Compartir fecha no equivale a una relación de negocio explícita.

### Diferencias entre instalación nueva y base actualizada

Una instalación nueva en versión 13 omite `cash.fecha` y `nequi.fecha`. Una base que pasó correctamente por la migración a versión 7 tendría `cash.fecha`. No existe en este archivo una sentencia que agregue `nequi.fecha`. La migración de `sales.paymentMethod` lo agrega con valor por defecto y sin `NOT NULL`, mientras que la instalación nueva lo exige y no tiene ese valor por defecto.

También cambia la inicialización de Caja Mayor y Deudas: `onCreate` deja esas tablas vacías; `onUpgrade` inserta una fila de cero si están vacías. Sus providers interpretan ausencia de filas como saldo cero, de modo que el saldo mostrado puede coincidir aunque la historia persistida difiera.

## 3. Inventario y evaluación de migraciones

La rutina ejecuta bloques según `oldVersion`; no valida previamente qué columnas existen. La apertura actual solicita siempre versión 13. La tabla indica el destino lógico de cada condición, no garantiza que el paso llegue a completarse.

| Versión de destino | Condición | Acción observada | Evaluación |
| --- | --- | --- | --- |
| 1 / base inicial histórica | No hay una migración específica visible | El archivo solo contiene el creador del esquema actual | No se puede reconstruir el esquema histórico de v1 a partir de este archivo |
| 2 | `oldVersion < 2` | Añade `products.purchasePrice REAL NOT NULL DEFAULT 0` | No preserva costos históricos desconocidos; cero es un valor de relleno, no evidencia del costo real. [DB:145](C:/proyectos/valinor_ludoteca/lib/db/database_helper.dart:145) |
| 3 | `oldVersion < 3` | Intenta añadir `products.lote` | El literal Dart termina en `DEFAULT '''`; las comillas no producen el literal SQL vacío esperado. Por lectura estática, el SQL resultante acaba en `DEFAULT ` y es incompleto. [DB:151](C:/proyectos/valinor_ludoteca/lib/db/database_helper.dart:151) |
| 4 y 5 | No hay bloques | Ninguna acción visible | No asumir qué ocurrió en versiones históricas sin examinar evidencia adicional |
| 6 | `oldVersion < 6` | Crea `cash` si falta; si está vacía inserta `167000`; si tiene registros actualiza `id = 1` a `167000` | Puede sobrescribir un saldo existente. Si el último saldo no es `id = 1`, el valor histórico que se cambia puede no ser el que carga la aplicación. [DB:157](C:/proyectos/valinor_ludoteca/lib/db/database_helper.dart:157) |
| 7 | `oldVersion < 7` | Añade `cash.fecha` y pone la fecha actual en todas las filas | No recupera fechas reales de movimientos pasados; las reemplaza por una fecha de migración. [DB:175](C:/proyectos/valinor_ludoteca/lib/db/database_helper.dart:175) |
| 8 | `oldVersion < 8` | Llama `_createDBNequi` | Crea Nequi si falta y siempre inserta una fila de `4000`, incluso si la tabla ya existía. [DB:185](C:/proyectos/valinor_ludoteca/lib/db/database_helper.dart:185), [DB:65](C:/proyectos/valinor_ludoteca/lib/db/database_helper.dart:65) |
| 9 | `oldVersion < 9` | Actualiza `nequi.fecha` a la fecha actual | No existe el `ALTER TABLE` que agregue esa columna. Fallaría si la tabla corresponde al creador visible. [DB:190](C:/proyectos/valinor_ludoteca/lib/db/database_helper.dart:190) |
| 10 | `oldVersion < 10` | Crea `caja_mayor` | Después del bloque, cualquier upgrade comprueba esa tabla y la inicializa en cero si está vacía. [DB:196](C:/proyectos/valinor_ludoteca/lib/db/database_helper.dart:196) |
| 11 | `oldVersion < 11` | Crea `deudas` | Al final, cualquier upgrade la inicializa en cero si está vacía. [DB:210](C:/proyectos/valinor_ludoteca/lib/db/database_helper.dart:210), [DB:225](C:/proyectos/valinor_ludoteca/lib/db/database_helper.dart:225) |
| 12 | `oldVersion < 12` | Añade `sales.paymentMethod TEXT DEFAULT "Efectivo"` | Asigna Efectivo como supuesto para ventas previas; permite NULL y difiere de `onCreate`. Si una base anterior ya contiene la columna, no hay comprobación para evitar un intento duplicado. No se afirma que ese caso exista en producción. [DB:215](C:/proyectos/valinor_ludoteca/lib/db/database_helper.dart:215) |
| 13 | `oldVersion < 13` | Crea `movimientos` si falta | No genera movimientos que expliquen los saldos históricos ni las ventas previas. [DB:221](C:/proyectos/valinor_ludoteca/lib/db/database_helper.dart:221) |

### Consecuencias por origen

- Bases con `oldVersion < 3` encuentran primero la sentencia sospechosa de `lote`. No se ejecutó una prueba que capture el error exacto del motor.
- Bases con `oldVersion < 9` cuya tabla Nequi corresponda a la definición visible encuentran una actualización de una columna inexistente. El primer fallo puede ser anterior si aplica la migración de `lote`.
- Una base ya marcada como versión 13 no vuelve a recorrer `onUpgrade`: los defectos del creador no se reparan por reiniciar la aplicación.
- Una base v13 real podría haber recibido cambios manuales o proceder de otro código. No debe inferirse su estructura sin un inventario autorizado de una copia.
- El código no registra procedencia, fecha de ejecución o resultado de cada paso de migración en tablas propias. La versión por sí sola no describe las diferencias de esquema señaladas.

## 4. Modelos y reglas efectivas

### `Product`

[Product:1](C:/proyectos/valinor_ludoteca/lib/models/products.dart:1) es una estructura inmutable con identificador opcional, nombre, cantidad, precio de venta, precio de compra y lote. No valida cantidades, nombres vacíos, precios negativos ni valores no finitos. Usa `double` para dinero.

`lote` es nullable en Dart, pero `products.lote` es `NOT NULL` en el esquema actual. `toMap` siempre incluye la clave, de modo que un modelo construido con `lote: null` no utiliza automáticamente el valor por defecto SQL. Véase [Product:18](C:/proyectos/valinor_ludoteca/lib/models/products.dart:18).

`fromMap` acepta un mapa dinámico y convierte precios mediante `toDouble`; confía en los tipos de nombre y cantidad. La presencia de una clase no constituye una validación de dominio.

### `SaleLine`

[SaleLine:4](C:/proyectos/valinor_ludoteca/lib/models/saleline.dart:4) mezcla datos de negocio con un `TextEditingController` de Flutter. Conserva un `Product?`, un `int quantity`, un medio de pago nullable y el texto de cantidad.

La cantidad numérica no se actualiza en los usos encontrados: los cálculos y el registro leen `quantityController.text`. Hay dos representaciones con una sola usada de hecho. El constructor puede recibir `quantity`, pero no inicializa con ella el controlador. No hay serialización, identificador de línea ni liberación de su controlador.

### `Account` y cuentas abiertas

`Account` está definido en la pantalla de ventas, [Ventas:365](C:/proyectos/valinor_ludoteca/lib/screens/ventas_screen.dart:365), no en `models/`. Genera UUID, nombre, `FocusNode`, líneas y total. No equivale a una cuenta financiera: es una cuenta abierta de consumo.

[AccountsProvider:7](C:/proyectos/valinor_ludoteca/lib/providers/accounts_provider.dart:7) inicializa una lista en memoria con una cuenta. Sus cambios no se guardan en SQLite ni en otro almacenamiento. Cerrar el proceso pierde nombres, productos, cantidades y medios de pago de cuentas pendientes. Cambiar de pantalla no implica necesariamente perderlas, porque el provider está encima de las pantallas en `MultiProvider`.

El getter entrega la lista mutable original. Agregar o eliminar líneas y cuentas utiliza índices; no hay un estado persistido de abierta, en cobro, cerrada o anulada, ni una clave de idempotencia para registrar un cobro una sola vez. El total se recalcula desde el texto y el precio del objeto seleccionado; una cantidad inválida se interpreta como cero para mostrarlo ([AccountsProvider:74](C:/proyectos/valinor_ludoteca/lib/providers/accounts_provider.dart:74)).

### Invariantes que sí existen y límites

| Regla | Protección presente | Límite |
| --- | --- | --- |
| Campos obligatorios básicos | `NOT NULL` en productos, ventas y saldos | No establece rangos, formatos, importes positivos ni relaciones válidas por sí solo |
| No dejar stock negativo al sumar existencias | `insertOrUpdateProduct` rechaza `existing.quantity + product.quantity < 0` | Solo para un producto existente; la rama de inserción no repite esa regla. [DB:242](C:/proyectos/valinor_ludoteca/lib/db/database_helper.dart:242) |
| Descuento de stock de venta | `UPDATE ... WHERE quantity >= ?` | Si no descuenta ninguna fila, la venta ya insertada se conserva y el método devuelve su ID. [DB:306](C:/proyectos/valinor_ludoteca/lib/db/database_helper.dart:306) |
| Cantidad positiva para vender | Validación en la pantalla | El método de BD acepta enteros arbitrarios; no hay `CHECK` en tabla. [Ventas:60](C:/proyectos/valinor_ludoteca/lib/screens/ventas_screen.dart:60) |
| Medio de pago permitido | Dropdown con Efectivo y Nequi | La BD y el modelo aceptan texto libre; no hay enum de dominio ni referencia a catálogo |
| Saldo suficiente al transferir | Validación de la interfaz antes de cambiar ambos saldos | No hay transacción ni verificación equivalente en los setters de persistencia |
| Identidad de producto | Búsqueda por nombre exacto, `limit: 1` | No hay clave única; lote no forma parte de la búsqueda. [DB:125](C:/proyectos/valinor_ludoteca/lib/db/database_helper.dart:125) |

## 5. Providers y persistencia financiera

| Componente | Carga | Escritura | Observaciones |
| --- | --- | --- | --- |
| `CashProvider` | Última fila de `cash` por `id DESC`; si falta, intenta insertar cero con fecha | `agregarVenta` suma en memoria y añade fotografía; `setTotalEnCaja` reemplaza en memoria y añade fotografía | La memoria se modifica antes de confirmar la inserción. [Cash:12](C:/proyectos/valinor_ludoteca/lib/providers/cash_provider.dart:12), [Cash:37](C:/proyectos/valinor_ludoteca/lib/providers/cash_provider.dart:37) |
| `NequiProvider` | Última fila de `nequi`; si falta, intenta insertar `4000` con fecha | Igual patrón de suma y sustitución | Mismo problema de memoria y esquema. [Nequi:10](C:/proyectos/valinor_ludoteca/lib/providers/nequi_provider.dart:10), [Nequi:34](C:/proyectos/valinor_ludoteca/lib/providers/nequi_provider.dart:34) |
| `CajaMayorProvider` | Última fila de `caja_mayor`; si falta, cero solo en memoria | Suma o sustituye saldo y añade fotografía con fecha | No distingue ingresos, transferencias o ajustes. [CajaMayor:9](C:/proyectos/valinor_ludoteca/lib/providers/caja_provider.dart:9), [CajaMayor:26](C:/proyectos/valinor_ludoteca/lib/providers/caja_provider.dart:26) |
| `DeudasProvider` | Última fila de `deudas`; si falta, cero solo en memoria | Sustituye saldo y añade fotografía con fecha | No conserva deudor, vencimiento, abono ni vínculo a una venta. [Deudas:9](C:/proyectos/valinor_ludoteca/lib/providers/deudas_provider.dart:9), [Deudas:26](C:/proyectos/valinor_ludoteca/lib/providers/deudas_provider.dart:26) |
| `MovementsProvider` | Diez últimos movimientos de la BD | Inserta un movimiento y recarga diez | Publica mapas dinámicos y lista mutable. Notifica antes de escribir, sin cambiar todavía datos. [Movements:9](C:/proyectos/valinor_ludoteca/lib/providers/movements_provider.dart:9), [Movements:16](C:/proyectos/valinor_ludoteca/lib/providers/movements_provider.dart:16) |
| `AccountsProvider` | Una cuenta nueva en memoria | Sin almacenamiento | Importa `Account` desde la pantalla de ventas, que a su vez importa el provider. [Accounts:1](C:/proyectos/valinor_ludoteca/lib/providers/accounts_provider.dart:1) |

Ningún provider de saldo incorpora validación de signo o finitud, estado de guardado, error persistente, rollback o serialización de comandos. `notifyListeners()` después de una escritura exitosa no garantiza que la memoria siga representando la BD cuando la escritura falla: el campo ya se había cambiado.

### Flujo real de cobro

1. La pantalla valida cada línea usando el producto que quedó seleccionado y su cantidad de stock en memoria.
2. Inserta líneas de venta una por una; cada inserción intenta luego descontar stock.
3. Muestra éxito, limpia producto y cantidad de las líneas y pone a cero el total.
4. Recarga productos y devuelve los importes de línea calculados previamente.
5. El callback actualiza Caja o Nequi por cada línea, sin esperar sus `Future`.
6. Elimina la cuenta abierta del provider.

Las etapas están en [Ventas:44](C:/proyectos/valinor_ludoteca/lib/screens/ventas_screen.dart:44), [Ventas:92](C:/proyectos/valinor_ludoteca/lib/screens/ventas_screen.dart:92), [Ventas:108](C:/proyectos/valinor_ludoteca/lib/screens/ventas_screen.dart:108) y [Ventas:267](C:/proyectos/valinor_ludoteca/lib/screens/ventas_screen.dart:267). No forman una unidad transaccional.

### Auditoría de movimientos

La búsqueda de llamadas en `lib/` encuentra `agregarMovimiento` utilizado por el diálogo de egresos. El cobro de ventas, la transferencia y el ingreso a Caja Mayor no escriben un movimiento equivalente. Por ello, `movimientos` no es un libro completo de entradas y salidas que permita recomponer los cuatro saldos.

En el egreso primero se registra el movimiento con `await` y después se cambia el saldo sin esperar su persistencia ([Egreso:89](C:/proyectos/valinor_ludoteca/lib/screens/management/dialogs/expense_dialog.dart:89), [Egreso:99](C:/proyectos/valinor_ludoteca/lib/screens/management/dialogs/expense_dialog.dart:99)). Una transferencia actualiza dos saldos mediante llamadas independientes ([Transferencia:118](C:/proyectos/valinor_ludoteca/lib/screens/management/dialogs/tranfer_dialog.dart:118)). Agregar a Caja Mayor sustituye directamente su total ([Ingreso:40](C:/proyectos/valinor_ludoteca/lib/screens/management/dialogs/add_dialog.dart:40)).

## 6. Hallazgos priorizados y escenarios

### D01 — P1: nueva instalación incompatible con las escrituras financieras

**Evidencia:** `cash` y `nequi` carecen de `fecha` en [DB:91](C:/proyectos/valinor_ludoteca/lib/db/database_helper.dart:91) y [DB:59](C:/proyectos/valinor_ludoteca/lib/db/database_helper.dart:59). Sus inserciones incluyen esa columna en [Cash:42](C:/proyectos/valinor_ludoteca/lib/providers/cash_provider.dart:42), [Cash:55](C:/proyectos/valinor_ludoteca/lib/providers/cash_provider.dart:55), [Nequi:39](C:/proyectos/valinor_ludoteca/lib/providers/nequi_provider.dart:39) y [Nequi:51](C:/proyectos/valinor_ludoteca/lib/providers/nequi_provider.dart:51). Las consultas históricas también la utilizan en [DB:418](C:/proyectos/valinor_ludoteca/lib/db/database_helper.dart:418) y [DB:435](C:/proyectos/valinor_ludoteca/lib/db/database_helper.dart:435).

**Escenario estático:** una instalación sin BD crea versión 13; puede arrancar porque lee las filas de apertura. Al registrar un cobro, ajustar Caja/Nequi o consultar su historia, el SQL referencia una columna inexistente. En el cobro, ventas y stock pueden haberse guardado antes de fallar el saldo. No hay reparación automática mientras la versión siga en 13.

### D02 — P1: migración de lote genera SQL incompleto

**Evidencia:** [DB:153](C:/proyectos/valinor_ludoteca/lib/db/database_helper.dart:153). El código contiene `'ALTER TABLE products ADD COLUMN lote TEXT NOT NULL DEFAULT '''`. La concatenación de literales Dart no conserva las comillas necesarias para un valor SQL vacío: resulta `ALTER TABLE products ADD COLUMN lote TEXT NOT NULL DEFAULT `.

**Escenario estático:** actualización desde una base con versión menor a 3. La sentencia no aporta valor para `DEFAULT`, lo que impide completar esa ruta de actualización. Debe verificarse en una copia desechable para registrar el diagnóstico exacto del motor; no se ha hecho aquí.

### D03 — P1: migración de Nequi actualiza una columna que no crea

**Evidencia:** creación sin `fecha` en [DB:59](C:/proyectos/valinor_ludoteca/lib/db/database_helper.dart:59); migración a v8 en [DB:185](C:/proyectos/valinor_ludoteca/lib/db/database_helper.dart:185); actualización de la columna en [DB:191](C:/proyectos/valinor_ludoteca/lib/db/database_helper.dart:191). No se encontró un `ALTER TABLE nequi ADD COLUMN fecha` en `lib/`.

**Escenario estático:** una tabla Nequi creada por esa función y una actualización con `oldVersion < 9` provocan referencia a columna inexistente. Si un fallo sucede durante la apertura inicial, [main:20](C:/proyectos/valinor_ludoteca/lib/main.dart:20) no tiene una vía de recuperación antes de `runApp`.

### D04 — P1: se registra una venta aunque el descuento de inventario no ocurra

**Evidencia:** [DB:306](C:/proyectos/valinor_ludoteca/lib/db/database_helper.dart:306) inserta antes del `UPDATE` condicional de [DB:314](C:/proyectos/valinor_ludoteca/lib/db/database_helper.dart:314). No usa una transacción de negocio ni comprueba filas afectadas. La validación visual compara cada línea por separado contra `product.quantity` en [Ventas:68](C:/proyectos/valinor_ludoteca/lib/screens/ventas_screen.dart:68).

**Escenario estático:** stock 5, dos líneas del mismo producto con cantidad 4. Ambas validaciones individuales pasan. La primera deja stock 1; la segunda registra una venta de 4 pero no descuenta nada porque ya no alcanza. Los importes de ambas pueden cobrarse. Otra cuenta abierta con un objeto `Product` antiguo presenta la misma clase de desactualización.

**Consecuencia:** ventas, inventario y saldo pueden representar cantidades diferentes sin que el método comunique el error.

### D05 — P1: una cuenta de varias líneas puede quedar guardada parcialmente

**Evidencia:** bucle de escrituras con `await` por línea en [Ventas:92](C:/proyectos/valinor_ludoteca/lib/screens/ventas_screen.dart:92); no hay un encabezado, una transacción para toda la cuenta ni manejo de excepción alrededor del conjunto.

**Escenario condicionado:** si la línea 1 se guarda y falla la línea 2 por un error de almacenamiento, la primera no se revierte por este código. El usuario puede conservar la cuenta pendiente e intentar de nuevo, sin un identificador de operación que evite duplicar la línea ya registrada. El fallo de almacenamiento no se provocó en esta revisión.

### D06 — P1: venta, saldo y eliminación de cuenta se confirman por separado

**Evidencia:** éxito y limpieza en [Ventas:108](C:/proyectos/valinor_ludoteca/lib/screens/ventas_screen.dart:108); saldos sin `await` en [Ventas:279](C:/proyectos/valinor_ludoteca/lib/screens/ventas_screen.dart:279) y [Ventas:282](C:/proyectos/valinor_ludoteca/lib/screens/ventas_screen.dart:282); eliminación de cuenta en [Ventas:286](C:/proyectos/valinor_ludoteca/lib/screens/ventas_screen.dart:286). Los providers cambian memoria antes de guardar, por ejemplo [Cash:38](C:/proyectos/valinor_ludoteca/lib/providers/cash_provider.dart:38).

**Escenario estático/condicionado:** una venta se guarda y se anuncia como correcta; después falla la escritura de Caja o Nequi, por el defecto D01 o por almacenamiento. El borrador ya se limpió y la cuenta se elimina sin esperar ese resultado. El saldo en memoria puede diferir del persistido y la excepción del `Future` no es gestionada por el callback.

### D07 — P1: los reportes históricos cambian cuando cambia el producto

**Evidencia:** [DB:456](C:/proyectos/valinor_ludoteca/lib/db/database_helper.dart:456), [DB:466](C:/proyectos/valinor_ludoteca/lib/db/database_helper.dart:466) y [DB:476](C:/proyectos/valinor_ludoteca/lib/db/database_helper.dart:476) calculan ingresos y costos multiplicando la cantidad vendida por `products.price` y `products.purchasePrice` actuales. Reponer inventario reemplaza esos precios en [DB:255](C:/proyectos/valinor_ludoteca/lib/db/database_helper.dart:255).

**Escenario estático:** vender una unidad a 10.000 con costo 6.000; luego reponer el mismo nombre con precio 12.000 y costo 8.000. El reporte de aquella venta pasa a usar 12.000 y 8.000 aunque su cobro original no cambió. No es posible reconstruir precio y costo históricos exactos solo con las columnas de `sales`.

### D08 — P1: transferencias y egresos pueden persistir solo una parte de la operación

**Evidencia:** dos `_setTotal` independientes en [Transferencia:118](C:/proyectos/valinor_ludoteca/lib/screens/management/dialogs/tranfer_dialog.dart:118); movimiento del egreso antes del cambio de saldo en [Egreso:89](C:/proyectos/valinor_ludoteca/lib/screens/management/dialogs/expense_dialog.dart:89). Los setters escriben en tablas distintas sin una transacción compartida.

**Escenario condicionado:** transferir de Caja a Caja Mayor y fallar una de las inserciones. Puede quedar solo el descuento o solo el abono. En un egreso puede quedar el movimiento sin el saldo correspondiente. La ausencia de vínculo o identificador común dificulta detectar y reparar el resultado.

### D09 — P2: identidad por nombre mezcla lotes y reemplaza costos de existencias anteriores

**Evidencia:** búsqueda solo por `name` en [DB:128](C:/proyectos/valinor_ludoteca/lib/db/database_helper.dart:128), acumulación de cantidad en [DB:244](C:/proyectos/valinor_ludoteca/lib/db/database_helper.dart:244) y reemplazo de precio, costo y lote en [DB:255](C:/proyectos/valinor_ludoteca/lib/db/database_helper.dart:255). No hay `UNIQUE(name)`.

**Escenario estático:** quedan unidades del lote A; se añade el mismo nombre con lote B y otro costo. La cantidad se suma, pero todas las unidades quedan descritas por un único lote B y el último costo. Dos altas concurrentes del mismo nombre también pueden superar la comprobación previa e insertar duplicados, porque búsqueda y escritura no forman una operación única ni existe restricción de unicidad. El escenario concurrente no se ejecutó.

**Decisión de negocio pendiente:** determinar si el lote es identificador real de existencias y qué método de costo se necesita. No debe inventarse FIFO, promedio o costo último sin esa definición.

### D10 — P2: eliminación física puede borrar la visibilidad del historial de ventas

**Evidencia:** `deleteProduct` borra la fila en [DB:281](C:/proyectos/valinor_ludoteca/lib/db/database_helper.dart:281); todos los reportes de ventas realizan `JOIN products` en [DB:459](C:/proyectos/valinor_ludoteca/lib/db/database_helper.dart:459), [DB:469](C:/proyectos/valinor_ludoteca/lib/db/database_helper.dart:469) y [DB:478](C:/proyectos/valinor_ludoteca/lib/db/database_helper.dart:478). La apertura no configura explícitamente la aplicación de FK en [DB:25](C:/proyectos/valinor_ludoteca/lib/db/database_helper.dart:25).

**Escenario condicionado:** si la conexión no aplica FK y se elimina un producto vendido, sus filas de `sales` quedan sin producto y desaparecen de los totales por el `JOIN`. Si una configuración externa sí aplica FK, el borrado puede ser rechazado; el callback de [ProductList:64](C:/proyectos/valinor_ludoteca/lib/widgets/product_list_widget.dart:64) no muestra un manejo específico de ese fallo. No se comprobó el estado real de FK.

### D11 — P2: faltan reglas de integridad en la frontera de persistencia

**Evidencia:** [DB:237](C:/proyectos/valinor_ludoteca/lib/db/database_helper.dart:237), [DB:297](C:/proyectos/valinor_ludoteca/lib/db/database_helper.dart:297) y [DB:333](C:/proyectos/valinor_ludoteca/lib/db/database_helper.dart:333) confían en sus parámetros, salvo el control parcial de stock existente. Los providers de saldo aceptan cualquier `double` y no validan rangos.

**Escenarios estáticos:** insertar un producto nuevo con cantidad negativa por la API no pasa por la protección reservada a productos existentes; llamar `insertSale` con cantidad negativa puede aumentar stock; un medio de pago arbitrario puede guardarse aunque los reportes solo reconozcan los conocidos. El formulario de producto tampoco rechaza precios negativos en [ProductForm:88](C:/proyectos/valinor_ludoteca/lib/widgets/product_form_widget.dart:88).

Estas entradas no equivalen a afirmar que la interfaz normal expone todas las llamadas. Demuestran que las reglas no residen en un punto común reutilizable y son fáciles de omitir al añadir otra pantalla, importador o test.

### D12 — P2: cuentas abiertas y detalle de deudas no tienen persistencia adecuada

**Evidencia:** cuentas en memoria en [Accounts:7](C:/proyectos/valinor_ludoteca/lib/providers/accounts_provider.dart:7); datos de cuenta en [Ventas:365](C:/proyectos/valinor_ludoteca/lib/screens/ventas_screen.dart:365); tabla `deudas` solo con total y fecha en [DB:79](C:/proyectos/valinor_ludoteca/lib/db/database_helper.dart:79).

**Escenario estático:** cierre o interrupción del proceso antes de cobrar pierde cuentas pendientes. Una deuda solo puede representarse como saldo agregado: no se puede saber quién debe, por qué venta, cuánto abonó o cuándo vence a partir de esa tabla. No se infiere si el negocio desea cuentas por cobrar o por pagar; la semántica debe aclararse antes del nuevo modelo.

### D13 — P2: historia financiera incompleta y saldos iniciales ligados al código

**Evidencia:** valores fijos de apertura en [DB:66](C:/proyectos/valinor_ludoteca/lib/db/database_helper.dart:66) y [DB:98](C:/proyectos/valinor_ludoteca/lib/db/database_helper.dart:98); inserción separada de movimientos en [DB:342](C:/proyectos/valinor_ludoteca/lib/db/database_helper.dart:342); resumen por último ID en [DB:380](C:/proyectos/valinor_ludoteca/lib/db/database_helper.dart:380).

**Consecuencia:** no existe una igualdad verificable entre apertura, entradas, salidas y saldo final usando `movimientos`, porque ventas, ingresos y transferencias no escriben allí un historial completo. Los valores iniciales pueden ser intencionales para una instalación concreta, pero cualquier instalación nueva hereda esos mismos importes sin una apertura registrada por el usuario. Migrar no debe asumir que son valores universales ni reemplazar saldos reales por ellos.

### D14 — P2: migraciones pueden reescribir saldos y fechas históricas

**Evidencia:** actualización forzada del saldo `cash.id = 1` en [DB:171](C:/proyectos/valinor_ludoteca/lib/db/database_helper.dart:171); fecha actual para todas las filas en [DB:180](C:/proyectos/valinor_ludoteca/lib/db/database_helper.dart:180); inserción incondicional de apertura Nequi en [DB:66](C:/proyectos/valinor_ludoteca/lib/db/database_helper.dart:66).

**Escenario condicionado:** una base antigua ya contiene historia de caja y recorre esos pasos. Cambia un valor persistido o se agregan fechas que reflejan la migración, no el momento del saldo. Si Nequi ya existía por una variación histórica, el creador agrega una nueva fila fija que será la última leída. No se ha comprobado si alguna base real pasó por estos casos.

### D15 — P2: representación monetaria y temporal sin política explícita

**Evidencia:** `double` en [Product:5](C:/proyectos/valinor_ludoteca/lib/models/products.dart:5) y saldos; `REAL` en las tablas; `DateTime.now().toIso8601String()` en [DB:347](C:/proyectos/valinor_ludoteca/lib/db/database_helper.dart:347); intervalos SQL inclusivos con `BETWEEN` en [DB:358](C:/proyectos/valinor_ludoteca/lib/db/database_helper.dart:358) y [DB:460](C:/proyectos/valinor_ludoteca/lib/db/database_helper.dart:460).

**Límite observable:** no se declara moneda, escala, redondeo, zona horaria ni una distinción entre instante y día comercial. No se detectó ni se afirma una pérdida monetaria concreta ya ocurrida. La versión nueva debe elegir unidades enteras y una política de fechas consistente con la operación de Bogotá; el límite de un reporte por días debe convertirse explícitamente en un intervalo, no depender de horas implícitas.

### D16 — P3: modelos de negocio acoplados a Flutter y recursos sin liberar

**Evidencia:** [SaleLine:9](C:/proyectos/valinor_ludoteca/lib/models/saleline.dart:9) posee un controlador sin `dispose`; [Account:389](C:/proyectos/valinor_ludoteca/lib/screens/ventas_screen.dart:389) libera solo nombre y foco; [Accounts:40](C:/proyectos/valinor_ludoteca/lib/providers/accounts_provider.dart:40) y [Accounts:58](C:/proyectos/valinor_ludoteca/lib/providers/accounts_provider.dart:58) eliminan objetos sin liberar esos recursos. El provider importa una pantalla para obtener su modelo.

**Consecuencia:** ciclo de dependencias, dificultad para probar lógica sin UI, recursos retenidos al crear/eliminar muchas cuentas o líneas y dos fuentes de cantidad. La lista pública mutable permite alterar estado fuera de los métodos que notifican.

### D17 — P3: consultas y orden temporal sin preparación para crecimiento

**Evidencia:** no hay índices adicionales en el esquema; reportes filtran fechas y agrupan ventas en [DB:452](C:/proyectos/valinor_ludoteca/lib/db/database_helper.dart:452); saldos iniciales ordenan solo por fecha en [DB:421](C:/proyectos/valinor_ludoteca/lib/db/database_helper.dart:421); movimientos solo ofrecen los diez últimos en [DB:371](C:/proyectos/valinor_ludoteca/lib/db/database_helper.dart:371).

**Consecuencia condicionada:** con mayor volumen, estas consultas pueden requerir recorrer mucha historia. Empates de fecha no incluyen un segundo criterio como ID. No se midió rendimiento ni se justifica una optimización prematura; los índices y la paginación deben derivarse de consultas y volumen esperado en la versión nueva.

## 7. Opciones de reutilización para la versión 2.0

### Reutilización aconsejable

- **Conceptos operativos:** producto, stock disponible, cuenta abierta, línea de consumo, cobro, medios Efectivo/Nequi, cuatro agrupaciones financieras y reporte por período. Son vocabulario útil; deben formalizarse sin copiar los defectos del almacenamiento.
- **Flutter y notificación de estado:** el uso de `Provider` puede mantenerse si los controllers delegan a servicios transaccionales y no escriben tablas directamente. La auditoría no demuestra que sea necesario cambiar de gestor de estado.
- **SQLite local:** es compatible con la naturaleza de escritorio observada. Puede conservarse como tecnología con esquema nuevo, migraciones verificadas y una ruta de datos propia de 2.0. Esta propuesta no abre ni modifica el archivo original.
- **Presentación:** formatos monetarios, campos y componentes visuales pueden servir de referencia. Deben consumir modelos de dominio independientes de `TextEditingController`.
- **Lectura de legado:** consultas y mapeos actuales sirven para identificar qué datos pueden importarse desde una copia autorizada. No deben usarse para inventar precios, fechas o relaciones que nunca se guardaron.

### Reescritura aconsejable en datos

- Sustituir la API `insertSale(productId, quantity, method, date)` por un caso de uso que reciba una venta completa e idempotente y confirme encabezado, líneas, pagos, stock y movimientos financieros en una sola transacción.
- Separar `OpenTab`/cuenta de consumo de `FinancialAccount`/cuenta de dinero. Persistir borradores y estados de la cuenta para recuperar trabajo pendiente.
- Conservar en la línea vendida nombre, precio y costo aplicados en el momento. Mantener un producto archivado o una referencia histórica estable, en lugar de depender del catálogo editable para reconstruir importes pasados.
- Modelar movimientos de inventario y, si el negocio lo requiere, lotes reales. La cantidad visible puede ser una proyección o un saldo mantenido de forma transaccional; no un campo actualizado desde lecturas desprotegidas.
- Consolidar las cuatro tablas de fotografías en un catálogo de cuentas financieras y movimientos con identificadores comunes. Registrar transferencias con ambos lados y egresos/ingresos con motivo. Definir deudas como una entidad aparte si representan obligaciones o cuentas por cobrar.
- Definir un tipo monetario de unidades enteras, moneda y escala explícitas; validar signo, finitud de entradas y reglas de redondeo en la frontera de dominio.
- Incorporar restricciones de integridad equivalentes a las reglas reales, aplicar FK explícitamente y crear índices para las consultas aceptadas. No elegir una restricción única de producto sin definir antes si identifica SKU, nombre o variante/lote.
- Mantener DTO, mapeadores y repositorios en infraestructura; entidades y reglas sin imports de Flutter; controllers con estados de carga/error y actualización después de confirmar persistencia.

No se recomienda trasladar tal cual `DatabaseHelper`, los setters libres de saldo, `SaleLine` con controlador o el modelo `Account` definido dentro de la pantalla. Se pueden reutilizar sus contratos operativos como especificación de partida, no como garantía de integridad.

## 8. Límites para una futura importación del legado

1. **Precio y costo históricos:** no están en `sales`. No se deben presentar los precios actuales como importes históricos comprobados. Una importación deberá marcarlos como desconocidos, estimados o pendientes de conciliación según la decisión del negocio.
2. **Agrupación de cobros:** no existe encabezado ni identificador de cuenta en ventas. Agrupar por fecha sería una heurística y debe documentarse como tal.
3. **Lotes anteriores:** el campo se reemplaza al reponer. No se puede reconstruir por sí solo el lote de cada unidad vendida o disponible.
4. **Saldos y movimientos:** los últimos saldos pueden servir como una apertura verificada en un corte, pero `movimientos` no explica toda su formación. Se necesita conciliación separada; una suma de diferencias entre fotografías tampoco identifica por sí sola la causa de cada cambio.
5. **Fechas:** filas con fecha ausente, agregada en una migración o sin zona requieren conservar procedencia y una clasificación de calidad. No conviene asignarles silenciosamente la fecha actual.
6. **Cuentas abiertas:** no hay fuente persistida para importarlas una vez cerrado el proceso. Debe planearse un corte operativo si siguen existiendo al migrar.
7. **Datos de deudas:** la tabla conserva saldo agregado; no contiene contrapartes ni comprobantes para crear un detalle que nunca se registró.
8. **Aislamiento:** la aplicación 2.0 debe utilizar otra ruta de datos y otro proceso de importación. El nombre de archivo y directorio del legado no deben reutilizarse accidentalmente por el simple hecho de conservar el helper.

## 9. Validaciones pendientes, sin ejecutar en esta auditoría

- Inventariar, sobre una **copia** autorizada, versión, tablas, columnas, índices, aplicación de FK, filas huérfanas, valores nulos, negativos, duplicados y fechas mal formadas.
- Comparar el esquema real contra las variantes de instalación nueva y actualizada descritas aquí; conservar cualquier diferencia como evidencia.
- Probar creación vacía y rutas de migración desde fixtures representativos, incluyendo versiones menores a 3, menores a 9, 11, 12 y 13. Confirmar mensajes exactos y resultado completo de cada ruta.
- Probar una cuenta con dos líneas del mismo producto, dos cuentas que comparten stock, fallo en segunda línea, fallo al guardar saldo, doble envío de cobro, transferencia parcial y egreso parcial.
- Probar que modificar precio, costo o nombre y archivar productos no cambie reportes históricos de ventas ya confirmadas en 2.0.
- Comprobar recuperación de borradores y reconciliación de importación con conteos, saldos, procedencia y excepciones conocidas. No exigir coincidencia de beneficios históricos que el legado no puede demostrar.

Estas comprobaciones son trabajo futuro y no se presentan como realizadas. La evidencia actual es suficiente para identificar los defectos de contrato y de atomicidad, pero no para certificar el estado de la base instalada ni cuantificar daños pasados.
