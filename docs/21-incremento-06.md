# Incremento 06 — ventas de mostrador 0.6.1

La atención en tienda necesita registrar una venta de contado desde una sola pantalla. **Ventas** muestra varias cuentas abiertas, cada una con sus líneas de producto, cantidad y forma de pago. **Registrar venta** confirma la entrega y el dinero recibido juntos. El flujo normal no pide cliente, vencimiento ni pasar después por Cobros.

## Uso

1. Entrar en **Ventas** y pulsar **Nueva cuenta**. El nombre inicial se puede cambiar.
2. Buscar y seleccionar un producto; se muestran precio y existencias. La cantidad empieza en una unidad.
3. Elegir **Efectivo** o **Nequi** en esa línea. **Agregar venta** añade otra línea a la misma cuenta; **Nueva cuenta** permite atender otra cuenta sin cerrar las anteriores.
4. Pulsar **Registrar venta** cuando se haya recibido el dinero. Se retira esa tarjeta de las cuentas abiertas y se conserva en **Últimas ventas pagadas**. Las demás cuentas permanecen disponibles.

Las cuentas y líneas seleccionadas se guardan automáticamente después de una pausa de 350 ms. El icono indica guardado pendiente, en curso o completo. Registrar espera a que se guarde la última edición. Un cierre cancelable de la app espera el guardado y se cancela si este falla; un cierre forzado del proceso puede perder los caracteres todavía sin guardar. La búsqueda sin selección no es una línea vendible y su texto no se persiste.

La mercancía debe tener existencias recibidas. Crear un producto en Catálogo todavía no crea stock. Se mantiene la recepción por Compras; la carga inicial simplificada queda pendiente.

## Integridad y compatibilidad

Se consultaron exclusivamente en lectura la pantalla de ventas, el widget de línea y el proveedor de cuentas del POS original. Se adaptó la interacción a Flutter 2.0; no se ejecutó el original ni se abrió una base productiva.

El esquema v6 añade borradores de mostrador, opciones rápidas de pago, solicitudes durables y hechos históricos por línea. Las migraciones v1–v5 conservan sus checksums, incluido v5 `fnv1a64:aaf6156fd67b9099`. Una base propia v5 con pagos e historial pendiente se migra con respaldo SQLite consistente previo, incluyendo WAL. Se conservan perfil, catálogo, operaciones y cuentas anteriores.

Los documentos existentes de venta/FIFO y cobro se componen dentro de una sola transacción. Se preparan primero una identidad principal y las identidades de sus dos operaciones internas. Si falla cualquiera, no queda una venta ni un cobro parcial. Un resultado incierto mantiene la tarjeta bloqueada para reintentar exactamente la misma solicitud al reabrir. Un rechazo conocido permite corregir después de liberar la solicitud. El pendiente de una venta de mostrador confirmada es cero.

Un producto puede aparecer en varias líneas con diferentes formas de pago, conservando el mismo precio por unidad dentro de la cuenta. Se acumulan sus unidades para comprobar stock y calcular FIFO una sola vez; se conserva el detalle de pago por línea. Una línea gratuita es posible dentro de una cuenta de total positivo. No se admiten cuentas de importe total cero.

Efectivo/Caja y Nequi son opciones locales que reutilizan catálogos compatibles o crean identidades nuevas sin dinero ni saldos de apertura. No se activan conexiones bancarias. Los nombres históricos de productos, cuentas y medios no se recalculan desde el catálogo. Si un producto cambia de nombre mientras una venta ya está preparada, se rechaza para que se revise la cuenta.

El guardado por tarjeta usa revisión optimista y una cola que conserva la petición exacta cuando su respuesta es incierta. Cambios en otra tarjeta no sobrescriben la que se está guardando. Un conflicto conocido ofrece **Recuperar cuenta guardada**, con confirmación antes de descartar la edición local; no se sobrescribe silenciosamente el contenido de otra instancia.

Por indicación expresa del propietario, **Ventas** es la única pantalla de ventas. Se retiraron el selector **Cuentas anteriores** y el montaje del formulario previo; el encabezado ya no dice **Venta rápida**. El código de persistencia anterior se conserva como componente interno y para compatibilidad de datos.

## Archivos principales

- `lib/features/quick_sales/`: dominio, adaptador SQLite, controlador de guardado por cuenta y pantalla.
- `lib/features/sales/data/sqlite_sales_store.dart` y `lib/features/collections/data/sqlite_collections_store.dart`: operaciones internas reutilizables dentro de una transacción externa. Sus interfaces anteriores permanecen disponibles.
- `lib/core/infrastructure/database/`: migración v6, restricciones de borradores, identidades y conciliación entre venta, cobro y pagos por línea.
- `lib/app/sanctum_app.dart`, `lib/main.dart` y `lib/features/workspace/`: composición, navegación al mostrador y guardado ante cierre cancelable.
- `test/integration/quick_sales_*`, `test/unit/quick_sales_controller_test.dart`, `test/widgets/quick_sales*`: inventario, dinero, recuperación, guardado e interacción.
- `tool/verify_quick_sales_flow.dart`: recorrido independiente en un perfil sintético nuevo; no admite rutas de bases existentes.

## Verificaciones ejecutadas

- Formato limpio en 76 archivos Dart y análisis estático sin incidencias.
- Suite completa final 0.6.1: **317 pruebas aprobadas y 3 omitidas** por permisos de symlinks del host. Se ejecutó con concurrencia 2; no se ejecutaron builds ni otras suites Flutter en paralelo.
- Nuevas pruebas: 17 de persistencia/operación, 8 de guardas SQL, 13 de controlador, 7 de interacción y 4 de navegación/cierre. Se comprueba que el formulario anterior no se muestra ni como alternativa cuando falta el almacén de ventas actual. Las ocho regresiones del formulario histórico se ejecutan aisladas, sin ruta desde la aplicación. Las pruebas de migración incluyen una base v5 auténtica con pagos confirmados y solicitud pendiente, su respaldo WAL y rechazo ante fallo de respaldo o historial alterado.
- Verificador independiente: **30 comprobaciones** en una base sintética nueva. Dos cuentas guardadas al reabrir; una registra el mismo producto en dos líneas, 1 unidad por Efectivo y 2 por Nequi. Venta COP 150,00, costo COP 60,01, dinero COP 50,00 y COP 100,00 respectivamente, pendiente cero. Quedan dos unidades valoradas en COP 40,00. La otra cuenta conserva su contenido y se añade una tercera en preparación para la observación nativa.
- Reintentos tras reapertura conservan documentos, costo y dinero. El historial mantiene las dos formas de pago por línea. Borradores y preparaciones no descuentan inventario. Fallos inyectados después de venta y cobro revierten ambas operaciones; solo queda la solicitud preparada para recuperar.
- Interfaz a 400 px, búsqueda por nombre/código, invalidación de selección al editar, envío del autocompletado hacia cantidad, guardado de borradores incompletos, conflictos entre revisiones, recuperación de respuestas inciertas y cierre cancelable comprobados. La [imagen del mostrador](images/quick-sales.png) es un render de widgets con datos sintéticos, inspeccionado visualmente.

~~~powershell
./scripts/dart.ps1 format --output=none --set-exit-if-changed lib test tool
./scripts/flutter.ps1 analyze
./scripts/flutter.ps1 test --reporter expanded --concurrency 2
./scripts/dart.ps1 run tool/verify_quick_sales_flow.dart
~~~

Evidencia del recorrido: [quick-sales-flow.json](evidence/quick-sales-flow.json).

## Limpieza puntual autorizada

Se identificaron exactamente dos borradores de prueba señalados por el propietario, uno abierto y otro preparado, ambos sin venta confirmada ni documentos/asientos asociados. Con la aplicación cerrada se ensayó su eliminación en una copia, se creó un respaldo SQLite consistente y se eliminaron esos dos borradores, sus dos líneas y una solicitud no confirmada. La comparación exacta de las 39 tablas comprobó que todos los demás registros permanecieron iguales, incluido el borrador de mostrador que no se pidió borrar. No se cambió el esquema ni sus guardas y las verificaciones de integridad y relaciones pasaron. Los nombres y las identidades particulares no se incluyen en la evidencia publicada: [example-drafts-cleanup.json](evidence/example-drafts-cleanup.json).

## Windows y conservación de datos

Antes de la corrección de navegación se compilaron dos bundles 0.6.0: uno exclusivo del perfil sintético (72,39 s) y otro sin defines de Sanctum (68,84 s), con AOT diferentes. En Windows se observaron dos cuentas simultáneas, forma de pago por línea, un botón Registrar venta por cuenta e historial con Efectivo y Nequi. En Sistema aparecieron cuatro Correcto y esquema 6. Las observaciones se hicieron con accesibilidad y teclado; no se registraron ventas mediante la ventana nativa. El flujo financiero lo comprobó la CLI y la interacción se probó en widgets.

El bundle 0.6.0 sin defines se publicó en la ruta estable después de que el propietario cerrara la versión anterior. Sus 17 archivos coincidieron por SHA256 con el ZIP y la copia versionada. Se abrió el perfil propio de desarrollo, se observaron cuatro Correcto y esquema 6 y se cerró la ventana. La migración creó un respaldo v5. Una comparación de solo lectura de las 34 tablas anteriores comprobó que todos sus registros seguían presentes sin cambios, incluidos perfil y catálogo, antes de la limpieza puntual solicitada después. No se ingresaron datos de negocio durante estas comprobaciones.

La publicación rechaza cualquier ejecutable del nuevo proyecto que siga abierto, incluidas copias versionadas que comparten su base propia. El ZIP no contiene bases de ejecución, perfiles sintéticos ni snapshots de depuración. El acceso de inicio continúa siendo **Iniciar Valinor Sanctum.cmd**.

Evidencia de la comprobación 0.6.0: [observación sintética](evidence/quick-sales-native-observations.json), [bundle con perfil conservado](evidence/quick-sales-final-observations.json) y [comparación con respaldo v5](evidence/quick-sales-preservation.json). La corrección 0.6.1 mantiene el esquema v6.

La compilación final **0.6.1+7**, sin defines de Sanctum, terminó en 78,27 s. Se publicó en el acceso estable y se verificaron los 17 archivos contra el ZIP y la copia `dist/0.6.1/ValinorSanctum2`. ZIP: 14.578.890 bytes, SHA256 `84D5A6BC67264EED7B2C6CB1E88732FE097A34FC153D20799917D8386A2B60E0`. Al abrirla se observaron versión 0.6.1, perfil conservado, encabezado Ventas, ausencia de ambos accesos anteriores y la otra cuenta de mostrador intacta. Se cerró la ventana. No se volvió a comprobar Sistema por interfaz en este corte; la captura de imagen nativa falló con `FrameArrived timed out`. Una comparación posterior de solo lectura de las 39 tablas confirmó que únicamente faltaban los dos borradores autorizados y sus dependencias, con integridad correcta y ninguna relación rota. El hash del ZIP permaneció igual.

Evidencia final: [pantalla única](evidence/sales-only-final-observations.json), [conservación después de abrir](evidence/sales-only-data-verification.json) y [resumen del incremento](evidence/increment-06.json).

## Límites y pendientes

Entrega de desarrollo, sin transición a producción. Continúan pendientes carga inicial simplificada de existencias, aperturas/caja, gastos, arqueos, anulaciones/devoluciones/ajustes, reportes, servicios, restauración desde interfaz, usuarios e importación. La prioridad del MVP se centra en validar primero el mostrador con el propietario. Los incrementos posteriores deben reducir los pasos de la operación frecuente y conservar el historial ya creado.
