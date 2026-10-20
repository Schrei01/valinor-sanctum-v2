# Incremento 07 — compras e ingresos de contado 0.7.0

**Compras** reúne el alta o reposición del producto y su entrada de inventario. Incluye nombre, precio de compra unitario, PVP unitario, proveedor, categoría Comestible/Artículo/Evento, SKU opcional y cantidad. La cuenta de pago se elige entre Efectivo y Nequi y el total se calcula automáticamente. Se retiraron referencia, vencimiento y confirmación a crédito.

## Uso

1. Entrar en **Compras**. Si corresponde, declarar desde **Saldo inicial** el dinero con el que se empieza, antes del primer movimiento de cada cuenta. No es un ajuste del saldo actual.
2. Escribir el nombre de un producto nuevo o seleccionar uno existente para reponerlo. Seleccionar/escribir proveedor y categoría; completar costo unitario, PVP unitario, SKU opcional y cantidad.
3. Elegir de qué cuenta se paga y pulsar **Ingresar producto**. La misma operación guarda producto, proveedor, existencias, costo y pago total. Exige dinero registrado suficiente.
4. Consultar **Historial de ingresos** en esa pantalla. El producto y sus existencias aparecen en Catálogo y al entrar a Ventas.

## Decisiones e integridad

Se preservan las migraciones v1–v6 y se añade v7. La base propia se respalda antes de actualizarla. Las compras y deudas anteriores permanecen como hechos históricos; este incremento no las elimina ni las paga por inferencia.

La solicitud durable captura el contenido del formulario y reserva las identidades de la recepción y de su pago. Preparar no crea productos, proveedores ni movimientos. Confirmar ejecuta catálogo/proveedor, recepción FIFO y pago total dentro de una transacción. Un fallo posterior al pago revierte también producto, dinero y stock. Las respuestas originales se recuperan por identidad y no crean otro ingreso.

La estructura publicada de recepción usa internamente una obligación y el literal `credit`; la nueva operación la liquida por completo antes de confirmar el ingreso. El enlace explícito del ingreso de contado y su saldo cero identifican el comportamiento comercial. No se reinterpretan documentos por ese literal aislado.

Reponer compara el producto con la versión que se editó; un cambio concurrente obliga a actualizar y seleccionar de nuevo. Se rechazan cambios de proveedor/categoría que alteren las capturas preparadas. Los nombres de cuentas y medios de pago se conservan en las capturas históricas. Cantidades, dinero y multiplicaciones usan enteros y comprobaciones de rango; FIFO conserva su política histórica.

El saldo inicial es una operación separada, explícita e idempotente, con una identidad única por cuenta. Debita dinero y acredita patrimonio. Se bloquea si esa cuenta ya tiene movimientos publicados; no suma un saldo actual encima de ventas ya registradas. Un resultado incierto se reintenta con la misma identidad.

## Archivos principales

- `lib/features/stock_intake/`: contrato, persistencia, saldo inicial y controlador.
- `lib/features/inventory/presentation/purchases_page.dart`: formulario único e historial de ingresos; Catálogo actualiza sus textos a ingresos y PVP.
- Adaptadores de inventario y pagos: operaciones reutilizables dentro de una transacción externa, conservando las interfaces previas.
- Esquema/migraciones y guardas de identidades en ventas, cobros y venta de mostrador.
- Integración en workspace, aplicación y punto de inicio; scripts de empaquetado.
- Pruebas de persistencia, SQL, migración, controlador e interacción y `tool/verify_stock_intake_flow.dart`.

## Verificaciones ejecutadas

El recorrido independiente con una base sintética nueva pasó **26 comprobaciones**: categorías/opciones sin dinero inventado; rechazo por fondos insuficientes; saldos declarados explícitamente; preparación sin efectos; reapertura; producto/proveedor creados juntos; 5 unidades a costo unitario 10,01 y PVP 30,00; reposición de 2 a costo 12,00 y PVP 35,00 pagada por Nequi; venta posterior de 2 con costo histórico 20,02. Quedan 5 unidades valoradas en 54,03; Efectivo 1.019,95 y Nequi 476,00. Todos los ingresos quedan completamente pagados. Moneda COP, escala 2, exclusivamente datos sintéticos. Evidencia: [stock-intake-flow.json](evidence/stock-intake-flow.json).

Las primeras pruebas dirigidas aprobaron **33 casos**: 16 de ingreso, 11 de restricciones SQL y 6 de saldo inicial. No se ingresaron datos comerciales en la base del propietario durante estas verificaciones.

La tanda de interfaz aprobó **21 pruebas**: 10 de controlador, 8 del formulario de ingresos y 3 regresiones de Catálogo. Comprueba producto nuevo/reposición, proveedor nuevo, precios/cantidad/pago, recuperación, rechazo, saldo inicial, historial y pantalla estrecha. La [vista previa de Compras](images/stock-intake.png) es un render de widgets con datos sintéticos y se inspeccionó visualmente.

La suite completa aprobó **370 pruebas y omitió 3** por permisos de enlaces simbólicos del host. Incluye tres casos nuevos de migración v6→v7: preservación de ventas/solicitudes y dinero con respaldo WAL, fallo de respaldo que deja el archivo v6 intacto, y rechazo de declaraciones v6 alteradas. El análisis estático terminó sin incidencias y se formatearon 87 archivos Dart. Se corrigieron automáticamente 40 avisos de llaves de estilo, sin modificar la lógica, y se repitieron el análisis y el recorrido independiente sobre la versión final del esquema. Las suites y builds Flutter se ejecutan secuencialmente.

~~~powershell
./scripts/dart.ps1 format --output=none --set-exit-if-changed lib test tool
./scripts/flutter.ps1 analyze --no-pub
./scripts/flutter.ps1 test --no-pub --reporter expanded --concurrency 2
./scripts/dart.ps1 run tool/verify_stock_intake_flow.dart
~~~

## Windows

La compilación sintética 0.7.0+8 terminó en 58,12 s, con defines exclusivos del perfil nuevo del verificador. Se abrió en Windows y se observaron todos los campos pedidos, cantidad inicial 1, cuenta de pago y saldo disponible, botón Ingresar producto e historial de dos ingresos pagados con Efectivo/Nequi y sus costos/PVP originales. No aparecieron referencia ni vencimiento. Sistema mostró cuatro Correcto y esquema 7. Se usaron accesibilidad y teclado; no se enviaron operaciones financieras desde la ventana nativa. La CLI creó los datos sintéticos y los formularios se ejercitaron con widgets. La ventana se cerró antes de recompilar el bundle final. Evidencia: [stock-intake-native-observations.json](evidence/stock-intake-native-observations.json).

La compilación final sin defines de Sanctum terminó en 74,56 s, con AOT diferente del bundle sintético. Se publicó en el acceso estable y se verificaron por SHA256 los 17 archivos contra el ZIP y la copia `dist/0.7.0/ValinorSanctum2`. ZIP: 14.637.650 bytes; SHA256 `0ADB8E91FA60775347BCFD9A9498C588D28AB3ED733151C08827D193BAB056B1`. No incluye bases de ejecución, perfiles sintéticos ni snapshots de depuración.

El bundle final abrió el perfil propio conservado y mostró versión 0.7.0, campos nuevos de Compras, historial de ingresos y cuatro Correcto con esquema 7 en la ruta propia de desarrollo. No se ingresaron compras, saldos ni otros datos comerciales durante esta observación; la ventana se cerró. Se creó un respaldo v6 antes de migrar y una comparación de solo lectura de las 39 tablas anteriores comprobó que todos sus registros se conservaron sin cambios. Se añadieron la migración y las categorías predeterminadas, sin inventar dinero. El hash del ZIP permaneció igual después de la prueba.

Evidencia: [apertura final](evidence/stock-intake-final-observations.json), [preservación contra respaldo v6](evidence/stock-intake-preservation.json) y [resumen del incremento](evidence/increment-07.json). No se inspeccionó el resultado de CI remoto ni se habilitó producción.

## Límites y pendientes

El costo de adquisición debe ser positivo; los regalos o ingresos totalmente gratuitos requieren un flujo específico. El saldo inicial se admite antes del primer movimiento, no como recarga posterior; aportes adicionales y transferencias quedan pendientes. Evento conserva unidades de producto en este incremento. Persisten pendientes arqueo, ajustes/reversas/devoluciones, reportes, restauración desde interfaz, usuarios, importación y producción.
