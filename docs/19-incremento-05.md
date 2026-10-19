# Incremento 05 — pagos a proveedores 0.5.0

El módulo **Pagos** aplica abonos o pagos completos a compras a crédito ya recibidas. Permite repartir el importe entre cuentas y medios locales. Cada cuenta debe estar activa, disponible y tener dinero registrado suficiente; todas las partes de una cuenta se comprueban juntas.

## Comportamiento y decisiones

La configuración de cuentas y medios se comparte con Cobros. Crear una cuenta no inventa una apertura: el saldo se reconstruye del libro. En este alcance los fondos provienen de cobros registrados. Pagos registra dinero ya entregado al proveedor; no conecta con bancos ni ejecuta transferencias externas.

La confirmación debita proveedores por pagar y acredita las cuentas monetarias. Documento, partes, liquidación de deuda y asiento se confirman en una sola transacción. No se registra otra compra, gasto, ingreso, costo ni movimiento de inventario. Compras muestra el total pagado y pendiente; Cobros muestra también la reducción del dinero por estos pagos.

La solicitud exacta queda preparada antes del efecto comercial. Cerrar/reabrir conserva sus partes e identidad. El reintento devuelve el resultado original, incluido el pendiente de ese momento. Un error de almacenamiento conserva la solicitud preparada; solo un rechazo determinista se puede descartar para corregir. Preparar no reserva fondos: una solicitud posterior puede consumir el dinero y provocar un rechazo al confirmar la primera.

Se conservan snapshots de compra/proveedor, cuentas y medios. Se rechazan pagos anteriores a la compra, al último pago de esa obligación o al último movimiento confirmado de cada cuenta usada. Dinero y agregados usan enteros/BigInt. Las restricciones SQL restan importes de presupuestos acotados y recorren saldos enteros para evitar redondeo y desbordamiento de sumas monetarias. Cada saldo cronológico intermedio debe caber en int64; un historial que incumpla ese límite se rechaza de forma conservadora, aunque su saldo final vuelva a estar dentro del rango.

La navegación estrecha distribuye los siete destinos en dos filas. La barra lateral permite desplazar los destinos en ventanas de menor altura. Ambas conservan el formulario durante la sesión. Al recuperar con «Actualizar» un cobro o pago ya confirmado tras una respuesta incierta, el formulario limpia el importe anterior; la operación queda visible en el historial.

## Archivos principales

- `lib/features/supplier_payments/`: dominio, controlador, adaptador SQLite y pantalla nueva.
- `lib/core/infrastructure/database/schema.dart` y `app_database.dart`: esquema v5, restricciones e incorporación a la migración respaldada.
- `lib/features/inventory/`: proyección pagado/pendiente de compras y reserva global de identificadores. Ventas y Cobros también respetan las identidades de solicitudes de pago.
- `lib/app/sanctum_app.dart`, `lib/main.dart`, `lib/features/workspace/`: composición y navegación.
- `lib/features/collections/presentation/collections_page.dart`: limpieza del formulario al recuperar una confirmación.
- `test/integration/supplier_payments_*`, `test/unit/supplier_payments_controller_test.dart`, `test/widgets/supplier_payments_test.dart`: deuda, fondos, atomicidad, recuperación e interfaz. Pruebas de migración ampliadas y regresión de Cobros.
- `tool/verify_supplier_payments_flow.dart`: recorrido independiente con una base sintética nueva; rechaza argumentos/rutas existentes.

## Migración

El esquema v5 añade `supplier_payment_requests`, `supplier_payments`, `supplier_payment_parts` y `payable_settlements`. Las migraciones v1–v4 conservan sus statements y checksums. La migración v4 tiene checksum fijo `fnv1a64:b669041fbf59266d`.

Las pruebas construyen una base v4 auténtica mediante SQL de esa versión, con venta, cobro, dinero y solicitud pendiente. Verifican la conservación de todas las filas históricas, el contenido WAL en el respaldo y la actualización a v5. También comprueban que un fallo de respaldo o historial alterado impide migrar sin resetear ni degradar datos.

## Verificaciones ejecutadas

- Formato: 65 archivos Dart, sin cambios pendientes. Análisis estático: sin incidencias.
- Suite completa: **265 pruebas aprobadas y 3 omitidas** por falta de permiso del host para crear symlinks. Incluye las regresiones de recuperación de Cobros y Pagos. El render opcional de Pagos también pasó y su imagen se inspeccionó visualmente.
- Flujo independiente: **36 comprobaciones aprobadas** sobre una base sintética nueva. Compra de COP 100,00; venta/cobro de COP 150,00 para obtener fondos; abono de COP 40,00; cierre/reapertura con pendiente COP 60,00; pago restante por dos cuentas. Deuda final cero, caja COP 30,00 y cuenta móvil COP 20,00.
- Stock final: una unidad valorada en COP 33,33. Venta y costo permanecen COP 150,00 y COP 66,67. Reintentos conservan documentos/respuestas y no duplican salidas de dinero ni liquidaciones. Los nombres históricos se conservan tras renombrar catálogos.
- SQL: saldos insuficientes, cuenta/medio inactivos, dinero no disponible, fondos con asiento sin confirmar, intervalo entre documento y asiento, sumas históricas superiores a int64, partes excesivas y reutilización de identidades rechazados sin efectos parciales. No se usa dinero de un asiento todavía sin confirmar como fuente de pago.

Evidencia reproducible: [flujo sintético](evidence/supplier-payments-flow.json) e [imagen de widgets](images/supplier-payments-credit.png). La imagen es un render de widgets con datos sintéticos; no es una captura de Windows ni una operación manual en una base real.

~~~powershell
./scripts/dart.ps1 format --output=none --set-exit-if-changed lib test tool
./scripts/flutter.ps1 analyze
./scripts/flutter.ps1 test --reporter expanded
./scripts/dart.ps1 run tool/verify_supplier_payments_flow.dart
./scripts/flutter.ps1 test test/widgets/supplier_payments_test.dart --dart-define=SANCTUM_CAPTURE_SUPPLIER_PAYMENTS_PREVIEW=true --plain-name 'partial and final receipt use the exact remaining balance'
~~~
## Windows y entrega local

Se compiló primero un ejecutable release vinculado solo al perfil sintético del verificador (60,4 s). Por accesibilidad y teclado se observaron pagos de 40 + 60, compra pagada con pendiente cero, caja 30, cuenta móvil 20 y los cuatro indicadores Correcto en esquema 5. Los registros se crearon por CLI; los formularios se ejercitaron en widgets. La captura de imagen de Windows no se utilizó. Se cerró esa ventana.

La compilación final sin defines de Sanctum tomó 64,4 s y tiene un AOT distinto. Se publicó el bundle completo, se extrajo la copia versionada y se compararon los 17 hashes de archivo entre ZIP, acceso estable y copia versionada. No contiene bases, perfiles sintéticos ni artefactos de depuración.

| Artefacto | Ruta dentro del proyecto |
|---|---|
| Inicio habitual | `Iniciar Valinor Sanctum.cmd` |
| Bundle vigente | `dist/ValinorSanctum2/valinor_sanctum_2.exe` |
| Copia versionada | `dist/0.5.0/ValinorSanctum2/valinor_sanctum_2.exe` |
| ZIP | `dist/valinor-sanctum-2-0.5.0-windows-x64.zip` |

Versión del ejecutable: **0.5.0+5**. ZIP: **14.530.845 bytes**, SHA-256 `9B756E60A43D6695AC77E7CAB48B716B1C062927BD4C18DB0C4742D11606881D`.

El lanzador habitual abrió el bundle final, mostró la configuración inicial vacía y cuatro Correcto con esquema 5. Actualizó exclusivamente la base propia de desarrollo y creó el respaldo previo `sanctum2.v4.1792445513594736-38040d8a.sqlite3`. No se ingresaron datos de negocio y la ventana quedó cerrada. El hash del ZIP permaneció igual después de esta prueba. El publicador conserva el bundle anterior dentro de `tmp/local-bundles`.

Evidencia: [resumen del incremento](evidence/increment-05.json), [observación nativa sintética](evidence/supplier-payments-native-observations.json) y [arranque final](evidence/supplier-payments-final-observations.json).

## Límites y siguiente trabajo

Continúa siendo una entrega de desarrollo con datos sintéticos y almacenamiento exclusivo de 2.0. El POS original y las bases productivas no se abrieron ni modificaron. No se ha autorizado transición a producción ni se ha inspeccionado un resultado de CI remoto.

Los formularios sin preparar viven en memoria; las solicitudes preparadas sí se recuperan. Las compras conservan el límite de reintento en memoria del incremento 02. Quedan pendientes aperturas, gastos/transferencias/capital, arqueos, ajustes/reversas/devoluciones, restauración desde interfaz, usuarios, importación y reportes. El siguiente incremento propuesto es apertura de saldos y movimientos de tesorería, antes de completar arqueos y recuperación operativa.
