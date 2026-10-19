# Auditoría de operación y flujos UI

## Alcance y método

Revisión estática de las pantallas de Inventario, Ventas y Administración; widgets de producto/venta; diálogos de gasto, transferencia y aporte; y providers relacionados de `C:/proyectos/valinor_ludoteca`. Se revisaron las llamadas a persistencia necesarias para seguir cada flujo.

No se ejecutó la aplicación ni se hicieron pruebas de interfaz, cobro o persistencia. No se abrieron bases de datos reales. Los defectos se deducen de las ramas y llamadas del código; los riesgos que requieren ejecución se identifican expresamente. No se modificó el proyecto original. Este documento no reproduce credenciales.

Severidades: **P1**, integridad de datos/dinero o pérdida de operación; **P2**, reglas incompletas, trazabilidad o inconsistencias funcionales; **P3**, mantenibilidad, presentación y ciclo de vida. Son prioridades de diseño de 2.0, no una medición de incidencias reales.

## Reglas funcionales observadas

### Inventario

- La pantalla tiene un formulario de ancho fijo de 300 px y un listado con buscador: [inventario_screen.dart:140](C:/proyectos/valinor_ludoteca/lib/screens/inventario_screen.dart:140).
- El producto tiene nombre, cantidad entera, precio de venta, precio de compra y lote. La UI exige todos, incluido lote; verifica que los números se puedan interpretar: [product_form_widget.dart:82](C:/proyectos/valinor_ludoteca/lib/widgets/product_form_widget.dart:82).
- El autocompletado busca por parte del nombre sin distinguir mayúsculas. Seleccionar un producto rellena precios y lote, no cantidad: [product_form_widget.dart:28](C:/proyectos/valinor_ludoteca/lib/widgets/product_form_widget.dart:28).
- Agregar un nombre ya existente suma cantidad y reemplaza precios y lote. La identidad usada por DB es la igualdad exacta del nombre: [database_helper.dart:125](C:/proyectos/valinor_ludoteca/lib/db/database_helper.dart:125), [database_helper.dart:237](C:/proyectos/valinor_ludoteca/lib/db/database_helper.dart:237).
- Ingresar cantidad negativa solicita una credencial compartida desde UI: [inventario_screen.dart:58](C:/proyectos/valinor_ludoteca/lib/screens/inventario_screen.dart:58). Para productos existentes, DB impide que la suma final sea negativa: [database_helper.dart:244](C:/proyectos/valinor_ludoteca/lib/db/database_helper.dart:244).
- Listado y búsqueda presentan solo productos con stock positivo: [database_helper.dart:268](C:/proyectos/valinor_ludoteca/lib/db/database_helper.dart:268). Se ordenan alfabéticamente y los importes se presentan en formato `es_CO` sin decimales: [product_list_widget.dart:43](C:/proyectos/valinor_ludoteca/lib/widgets/product_list_widget.dart:43).
- Eliminar requiere una confirmación ordinaria y borra físicamente por ID: [product_list_widget.dart:17](C:/proyectos/valinor_ludoteca/lib/widgets/product_list_widget.dart:17), [database_helper.dart:281](C:/proyectos/valinor_ludoteca/lib/db/database_helper.dart:281).
- No se observan SKU, código de barras, categorías, proveedores, archivo de producto, movimientos de inventario ni gestión de cantidades por lote.

### Ventas y cuentas abiertas

- La aplicación crea una cuenta inicial en memoria con una línea vacía: [accounts_provider.dart:6](C:/proyectos/valinor_ludoteca/lib/providers/accounts_provider.dart:6), [ventas_screen.dart:372](C:/proyectos/valinor_ludoteca/lib/screens/ventas_screen.dart:372).
- Se pueden abrir múltiples cuentas. Las nuevas toman el nombre `Cuenta N`, calculado con el mayor número entre nombres actuales que comienzan por ese prefijo: [accounts_provider.dart:12](C:/proyectos/valinor_ludoteca/lib/providers/accounts_provider.dart:12).
- Una cuenta tiene UUID, nombre editable, líneas y total; los objetos contienen controladores Flutter: [ventas_screen.dart:365](C:/proyectos/valinor_ludoteca/lib/screens/ventas_screen.dart:365).
- Se agregan líneas y se permite quitarlas mientras quede al menos una: [ventas_screen.dart:191](C:/proyectos/valinor_ludoteca/lib/screens/ventas_screen.dart:191), [ventas_screen.dart:247](C:/proyectos/valinor_ludoteca/lib/screens/ventas_screen.dart:247).
- Cada línea exige cantidad, producto y pago completo por Efectivo o Nequi. El autocompletado muestra stock y precio: [sale_line_widget.dart:31](C:/proyectos/valinor_ludoteca/lib/widgets/sale_line_widget.dart:31), [sale_line_widget.dart:44](C:/proyectos/valinor_ludoteca/lib/widgets/sale_line_widget.dart:44), [sale_line_widget.dart:104](C:/proyectos/valinor_ludoteca/lib/widgets/sale_line_widget.dart:104).
- Total de línea/cuenta = cantidad por precio del objeto seleccionado: [ventas_screen.dart:195](C:/proyectos/valinor_ludoteca/lib/screens/ventas_screen.dart:195), [accounts_provider.dart:74](C:/proyectos/valinor_ludoteca/lib/providers/accounts_provider.dart:74).
- Registrar verifica por línea: producto seleccionado, cantidad entera mayor que cero, cantidad no superior al stock del objeto y medio de pago: [ventas_screen.dart:44](C:/proyectos/valinor_ludoteca/lib/screens/ventas_screen.dart:44).
- Todas las líneas reciben la misma fecha del dispositivo y se guardan individualmente: [ventas_screen.dart:87](C:/proyectos/valinor_ludoteca/lib/screens/ventas_screen.dart:87).
- Luego se informa éxito, se limpian datos, se recargan productos, se solicitan incrementos de saldos por medio de pago y se elimina la cuenta: [ventas_screen.dart:108](C:/proyectos/valinor_ludoteca/lib/screens/ventas_screen.dart:108), [ventas_screen.dart:266](C:/proyectos/valinor_ludoteca/lib/screens/ventas_screen.dart:266).
- El icono de eliminar cuenta descarta inmediatamente su contenido: [ventas_screen.dart:179](C:/proyectos/valinor_ludoteca/lib/screens/ventas_screen.dart:179).
- Las cuentas abiertas no se guardan ni reservan existencias. No hay cierre parcial, abonos, deuda por cliente, descuentos, pagos repartidos por monto, cambio, devolución, anulación o comprobante en estos flujos.
- No hay cabecera de venta ni vínculo con la cuenta/nombre. Cada fila `sales` conserva producto, cantidad, pago y fecha: [database_helper.dart:113](C:/proyectos/valinor_ludoteca/lib/db/database_helper.dart:113).

### Administración y tesorería

- Se muestran Caja, Nequi, Caja Mayor y Deudas: [cash_summary_widget.dart:14](C:/proyectos/valinor_ludoteca/lib/screens/management/widgets/cash_summary_widget.dart:14).
- Total General suma Caja, Nequi y Caja Mayor; excluye Deudas: [total_card_widget.dart:13](C:/proyectos/valinor_ludoteca/lib/screens/management/widgets/total_card_widget.dart:13). La gráfica incluye los cuatro valores: [graphics_panel_widget.dart:15](C:/proyectos/valinor_ludoteca/lib/screens/management/widgets/graphics_panel_widget.dart:15).
- Hay acciones Transferir, Descontar y Agregar: [action_panel_widget.dart:16](C:/proyectos/valinor_ludoteca/lib/screens/management/widgets/action_panel_widget.dart:16).
- Transferir permite cualquier combinación de las cuatro cuentas; exige origen/destino distintos, monto positivo y fondos suficientes en origen: [tranfer_dialog.dart:13](C:/proyectos/valinor_ludoteca/lib/screens/management/dialogs/tranfer_dialog.dart:13), [tranfer_dialog.dart:61](C:/proyectos/valinor_ludoteca/lib/screens/management/dialogs/tranfer_dialog.dart:61), [tranfer_dialog.dart:110](C:/proyectos/valinor_ludoteca/lib/screens/management/dialogs/tranfer_dialog.dart:110).
- Descontar exige cuenta, monto positivo y motivo. Las categorías son Arriendo, Agua, Energía, Comestibles, Tienda, Host, Implementos y Aseo: [expense_dialog.dart:13](C:/proyectos/valinor_ludoteca/lib/screens/management/dialogs/expense_dialog.dart:13), [expense_dialog.dart:74](C:/proyectos/valinor_ludoteca/lib/screens/management/dialogs/expense_dialog.dart:74).
- El gasto registra primero un movimiento `egreso` y luego resta el saldo: [expense_dialog.dart:89](C:/proyectos/valinor_ludoteca/lib/screens/management/dialogs/expense_dialog.dart:89).
- Agregar solo incrementa Caja Mayor y exige un monto positivo: [add_dialog.dart:28](C:/proyectos/valinor_ludoteca/lib/screens/management/dialogs/add_dialog.dart:28).
- El historial presenta los últimos diez movimientos, sin filtros, búsqueda o paginación: [database_helper.dart:368](C:/proyectos/valinor_ludoteca/lib/db/database_helper.dart:368), [historic_panel_widget.dart:64](C:/proyectos/valinor_ludoteca/lib/screens/management/widgets/historic_panel_widget.dart:64).
- Los providers guardan fotografías sucesivas del saldo total, no partidas monetarias relacionadas: [cash_provider.dart:37](C:/proyectos/valinor_ludoteca/lib/providers/cash_provider.dart:37), [nequi_provider.dart:34](C:/proyectos/valinor_ludoteca/lib/providers/nequi_provider.dart:34), [caja_provider.dart:38](C:/proyectos/valinor_ludoteca/lib/providers/caja_provider.dart:38), [deudas_provider.dart:26](C:/proyectos/valinor_ludoteca/lib/providers/deudas_provider.dart:26).

## Hallazgos

### OP-01 · P1 · Venta sin descuento completo de existencias

Con stock 5, dos líneas del mismo producto con cantidades 4 y 4 pasan la validación individual. La inserción guarda primero la venta y después ejecuta el descuento condicionado a stock suficiente, sin comprobar filas actualizadas. La segunda línea puede quedar vendida sin descontarse. También puede ocurrir con objetos de producto seleccionados antes en otras cuentas.

Evidencia: [ventas_screen.dart:47](C:/proyectos/valinor_ludoteca/lib/screens/ventas_screen.dart:47), [database_helper.dart:306](C:/proyectos/valinor_ludoteca/lib/db/database_helper.dart:306). Para 2.0: agregar demanda por producto, revalidar dentro de una transacción y rechazar íntegramente si no alcanza.

### OP-02 · P1 · Cobro parcial e imposible de reintentar con seguridad

Las líneas se insertan secuencialmente, cada venta y descuento por separado; el dinero se actualiza después. Si falla una línea intermedia, las anteriores permanecen. Reintentar toda la cuenta puede duplicarlas.

Evidencia: [ventas_screen.dart:92](C:/proyectos/valinor_ludoteca/lib/screens/ventas_screen.dart:92), [database_helper.dart:306](C:/proyectos/valinor_ludoteca/lib/db/database_helper.dart:306). Para 2.0: operación transaccional única y clave de idempotencia.

### OP-03 · P1 · Éxito y eliminación antes de confirmar el dinero

Se informa éxito y se limpian líneas antes de aumentar los medios de pago. Las llamadas a `agregarVenta` no se esperan; después se elimina la cuenta. Si falla la escritura del saldo, ya no queda la cuenta visible para resolver la operación. Los providers además cambian memoria antes de persistir.

Evidencia: [ventas_screen.dart:108](C:/proyectos/valinor_ludoteca/lib/screens/ventas_screen.dart:108), [ventas_screen.dart:277](C:/proyectos/valinor_ludoteca/lib/screens/ventas_screen.dart:277), [cash_provider.dart:37](C:/proyectos/valinor_ludoteca/lib/providers/cash_provider.dart:37), [nequi_provider.dart:34](C:/proyectos/valinor_ludoteca/lib/providers/nequi_provider.dart:34). Para 2.0: confirmar efectos persistidos antes de cerrar la cuenta.

### OP-04 · P1 · Registro repetido durante una operación pendiente

No hay estado de guardado, bloqueo de cuenta ni deshabilitación del botón. Un doble clic o una interacción mientras el handler espera puede volver a registrar o cambiar índices de cuentas. Es un riesgo inferido del código asincrónico; no fue reproducido en interfaz.

Evidencia: [ventas_screen.dart:266](C:/proyectos/valinor_ludoteca/lib/screens/ventas_screen.dart:266). Para 2.0: estado de operación e identificación por ID estable, además de idempotencia en servicio.

### OP-05 · P1 · Pérdida de cuentas abiertas

Solo existe una lista en memoria; cerrar/reiniciar no puede recuperar consumos. El icono eliminar también descarta inmediatamente sin confirmación.

Evidencia: [accounts_provider.dart:6](C:/proyectos/valinor_ludoteca/lib/providers/accounts_provider.dart:6), [ventas_screen.dart:179](C:/proyectos/valinor_ludoteca/lib/screens/ventas_screen.dart:179). Para 2.0: guardar cuentas y líneas automáticamente, con estados y cierre/cancelación explícitos.

### OP-06 · P1 · Texto de producto y producto cobrado pueden divergir

Tras seleccionar A, escribir otro nombre sin seleccionar una opción no limpia `line.product`; el precio y la venta siguen usando A. El campo visible permite editar, pero solo `onSelected` modifica el producto de la línea.

Evidencia: [sale_line_widget.dart:56](C:/proyectos/valinor_ludoteca/lib/widgets/sale_line_widget.dart:56), [sale_line_widget.dart:66](C:/proyectos/valinor_ludoteca/lib/widgets/sale_line_widget.dart:66). Para 2.0: invalidar selección al editar y exigir producto identificado antes de cobrar.

### OP-07 · P1 · Egresos con saldo negativo o efecto incompleto

Se valida monto positivo, pero no fondos. El movimiento se guarda antes de restar un saldo mediante una llamada no esperada. Un gasto superior a fondos deja saldo negativo; una falla posterior puede dejar movimiento sin saldo correspondiente.

Evidencia: [expense_dialog.dart:74](C:/proyectos/valinor_ludoteca/lib/screens/management/dialogs/expense_dialog.dart:74), [expense_dialog.dart:89](C:/proyectos/valinor_ludoteca/lib/screens/management/dialogs/expense_dialog.dart:89), [expense_dialog.dart:99](C:/proyectos/valinor_ludoteca/lib/screens/management/dialogs/expense_dialog.dart:99). Para 2.0: definir política de fondos por tipo de cuenta y registrar gasto/partida en una transacción.

### OP-08 · P1 · Transferencias sin atomicidad ni historial

Se llaman dos setters sin esperar resultados, sin partida de transferencia o vínculo entre ambos lados. Si solo persiste uno, aparece o desaparece dinero. El diálogo se cierra incluso cuando la función rechaza por fondos insuficientes.

Evidencia: [tranfer_dialog.dart:73](C:/proyectos/valinor_ludoteca/lib/screens/management/dialogs/tranfer_dialog.dart:73), [tranfer_dialog.dart:110](C:/proyectos/valinor_ludoteca/lib/screens/management/dialogs/tranfer_dialog.dart:110), [tranfer_dialog.dart:117](C:/proyectos/valinor_ludoteca/lib/screens/management/dialogs/tranfer_dialog.dart:117), [tranfer_dialog.dart:137](C:/proyectos/valinor_ludoteca/lib/screens/management/dialogs/tranfer_dialog.dart:137). Para 2.0: una transferencia con dos partidas y confirmación conjunta.

### OP-09 · P1 · Aportes sin trazabilidad

Agregar a Caja Mayor solo cambia un total. No registra movimiento, motivo o aportante; no espera persistencia y muestra éxito. No permite distinguir aporte de capital, corrección e ingreso operativo.

Evidencia: [add_dialog.dart:39](C:/proyectos/valinor_ludoteca/lib/screens/management/dialogs/add_dialog.dart:39). Para 2.0: documento de aporte, contrapartida y comprobación antes de confirmar.

### OP-10 · P1 · Autorización limitada a una condición de UI

La credencial compartida está embebida en el código y solo protege ingreso de cantidad negativa en pantalla. El parámetro `password` del helper no se utiliza. No se observan usuarios, roles, actor o autorización de Administración, eliminación, precios y movimientos monetarios. No debe copiarse la credencial a la nueva versión.

Evidencia: [inventario_screen.dart:58](C:/proyectos/valinor_ludoteca/lib/screens/inventario_screen.dart:58), [inventario_screen.dart:94](C:/proyectos/valinor_ludoteca/lib/screens/inventario_screen.dart:94), [database_helper.dart:237](C:/proyectos/valinor_ludoteca/lib/db/database_helper.dart:237), [main.dart:84](C:/proyectos/valinor_ludoteca/lib/main.dart:84), [main.dart:120](C:/proyectos/valinor_ludoteca/lib/main.dart:120). Para 2.0: permisos coherentes con el alcance acordado y auditoría de actor.

### OP-11 · P1 · Alta nueva con stock negativo

La UI permite continuar con cantidad negativa tras comprobar la credencial. DB solo protege el resultado negativo cuando el nombre ya existe; la rama nueva inserta directamente. El producto puede nacer negativo y quedar oculto del listado.

Evidencia: [inventario_screen.dart:94](C:/proyectos/valinor_ludoteca/lib/screens/inventario_screen.dart:94), [database_helper.dart:242](C:/proyectos/valinor_ludoteca/lib/db/database_helper.dart:242), [database_helper.dart:262](C:/proyectos/valinor_ludoteca/lib/db/database_helper.dart:262). Para 2.0: invariantes de inventario en dominio/DB y ajustes como operaciones explícitas.

### OP-12 · P1/P2 · Validación y representación monetaria incompletas

El formulario acepta precios cero/negativos; solo comprueba que se interpreten como `double`. Los diálogos comparan monto con cero sin verificar explícitamente finitud o precisión. Se usan `double`/`REAL`, se aceptan decimales y se presentan importes sin ellos. Falta definir escala y parser para captura colombiana. La posibilidad de entrada de valores no finitos requiere verificación adicional del formato de entrada y librería; no se probó en ejecución.

Evidencia: [product_form_widget.dart:82](C:/proyectos/valinor_ludoteca/lib/widgets/product_form_widget.dart:82), [add_dialog.dart:28](C:/proyectos/valinor_ludoteca/lib/screens/management/dialogs/add_dialog.dart:28), [expense_dialog.dart:74](C:/proyectos/valinor_ludoteca/lib/screens/management/dialogs/expense_dialog.dart:74), [tranfer_dialog.dart:61](C:/proyectos/valinor_ludoteca/lib/screens/management/dialogs/tranfer_dialog.dart:61), [database_helper.dart:107](C:/proyectos/valinor_ludoteca/lib/db/database_helper.dart:107). Para 2.0: importes exactos, reglas de precios y validación finita/localizada.

### OP-13 · P2 · Reposición reemplaza lote y costo previo

Cada entrada del mismo nombre suma unidades a una única fila y reemplaza precios y lote. No hay costo/fecha/cantidad por entrada ni consumo de lotes, por lo que no puede rastrearse qué existencias corresponden a cada compra.

Evidencia: [database_helper.dart:244](C:/proyectos/valinor_ludoteca/lib/db/database_helper.dart:244). Para 2.0: separar catálogo, entradas, lotes y método de valoración acordado.

### OP-14 · P2 · Agotados ocultos y sugerencias desactualizadas

El listado oculta stock cero/negativo. El `Future` usado para autocompletar se crea solo al iniciar y no se reemplaza al agregar, así que puede omitir productos recién creados hasta recrear la pantalla. La recarga del listado también ignora la búsqueda activa.

Evidencia: [database_helper.dart:268](C:/proyectos/valinor_ludoteca/lib/db/database_helper.dart:268), [inventario_screen.dart:31](C:/proyectos/valinor_ludoteca/lib/screens/inventario_screen.dart:31), [inventario_screen.dart:37](C:/proyectos/valinor_ludoteca/lib/screens/inventario_screen.dart:37), [inventario_screen.dart:108](C:/proyectos/valinor_ludoteca/lib/screens/inventario_screen.dart:108). Para 2.0: catálogo consultable con filtros y estado reactivo compartido.

### OP-15 · P2 · Identidad inconsistente del producto

La UI busca sin distinguir mayúsculas, pero DB identifica por igualdad exacta del nombre y no declara restricción única. Nombres visualmente similares pueden representar productos distintos. El upsert además hace lectura y escritura separadas.

Evidencia: [product_form_widget.dart:33](C:/proyectos/valinor_ludoteca/lib/widgets/product_form_widget.dart:33), [database_helper.dart:103](C:/proyectos/valinor_ludoteca/lib/db/database_helper.dart:103), [database_helper.dart:128](C:/proyectos/valinor_ludoteca/lib/db/database_helper.dart:128), [database_helper.dart:240](C:/proyectos/valinor_ludoteca/lib/db/database_helper.dart:240). Para 2.0: IDs estables y reglas de unicidad/normalización explícitas.

### OP-16 · P2 · Borrado físico sin baja auditada

Eliminar borra la fila del producto por ID, sin razón ni archivo. No existe baja con trazabilidad. El efecto sobre ventas/reportes debe evaluarse junto con los joins y las restricciones de persistencia.

Evidencia: [product_list_widget.dart:64](C:/proyectos/valinor_ludoteca/lib/widgets/product_list_widget.dart:64), [database_helper.dart:281](C:/proyectos/valinor_ludoteca/lib/db/database_helper.dart:281). Para 2.0: archivar catálogo y registrar pérdidas/bajas con movimiento.

### OP-17 · P2 · Semántica de Deudas sin definir

Se permite usar Deudas como origen/destino de transferencias y como cuenta a descontar, sin contraparte, vencimiento o abonos. Total General la excluye, mientras la distribución la incluye. El código no permite concluir si representa cuentas por cobrar, pasivos o préstamo interno.

Evidencia: [tranfer_dialog.dart:13](C:/proyectos/valinor_ludoteca/lib/screens/management/dialogs/tranfer_dialog.dart:13), [expense_dialog.dart:108](C:/proyectos/valinor_ludoteca/lib/screens/management/dialogs/expense_dialog.dart:108), [total_card_widget.dart:17](C:/proyectos/valinor_ludoteca/lib/screens/management/widgets/total_card_widget.dart:17), [graphics_panel_widget.dart:20](C:/proyectos/valinor_ludoteca/lib/screens/management/widgets/graphics_panel_widget.dart:20). Para 2.0: resolver significado de negocio antes de migrar o implementar.

### OP-18 · P2 · Historial insuficiente para conciliar

En estos flujos solo los gastos crean movimientos; ventas, transferencias y aportes no. El movimiento genérico no tiene origen/destino, actor ni referencia al documento. Mostrar diez filas no permite reconstruir saldos.

Evidencia: [database_helper.dart:44](C:/proyectos/valinor_ludoteca/lib/db/database_helper.dart:44), [database_helper.dart:368](C:/proyectos/valinor_ludoteca/lib/db/database_helper.dart:368), [expense_dialog.dart:89](C:/proyectos/valinor_ludoteca/lib/screens/management/dialogs/expense_dialog.dart:89). Para 2.0: libro completo relacionado con operaciones y filtros/paginación.

### OP-19 · P2 · Distribución admite valores no comparables

Los saldos pueden ser negativos por gastos y se pasan directamente al gráfico circular. Los porcentajes incluyen Deudas y se calculan sobre la suma total de cuatro cuentas. La representación puede resultar inválida o engañosa; no se afirma un fallo concreto de `fl_chart` sin ejecución.

Evidencia: [graphics_panel_widget.dart:100](C:/proyectos/valinor_ludoteca/lib/screens/management/widgets/graphics_panel_widget.dart:100), [graphics_panel_widget.dart:120](C:/proyectos/valinor_ludoteca/lib/screens/management/widgets/graphics_panel_widget.dart:120). Para 2.0: métricas y gráficos compatibles con signos y significado contable.

### OP-20 · P2/P3 · Dominio acoplado a UI y estado duplicado

Provider importa la clase Account desde una pantalla; Account/SaleLine contienen controladores y foco Flutter. `SaleLine.quantity` no es la cantidad usada por los cálculos, que leen texto del controller. El provider expone su lista mutable directamente.

Evidencia: [accounts_provider.dart:3](C:/proyectos/valinor_ludoteca/lib/providers/accounts_provider.dart:3), [accounts_provider.dart:9](C:/proyectos/valinor_ludoteca/lib/providers/accounts_provider.dart:9), [accounts_provider.dart:74](C:/proyectos/valinor_ludoteca/lib/providers/accounts_provider.dart:74), [saleline.dart:4](C:/proyectos/valinor_ludoteca/lib/models/saleline.dart:4), [ventas_screen.dart:365](C:/proyectos/valinor_ludoteca/lib/screens/ventas_screen.dart:365). Para 2.0: entidades independientes de widgets y una fuente de verdad por campo.

### OP-21 · P3 · Ciclo de vida de controladores y filas

El formulario agrega listeners durante build; retirar cuentas no llama a `dispose`, y el método de Account no recorre sus líneas. Inventario no libera sus controladores. Las filas de venta no tienen keys propias; tras quitar una línea podría conservarse estado interno de autocompletado/dropdown de otra. Este último efecto requiere prueba de interfaz.

Evidencia: [product_form_widget.dart:40](C:/proyectos/valinor_ludoteca/lib/widgets/product_form_widget.dart:40), [accounts_provider.dart:38](C:/proyectos/valinor_ludoteca/lib/providers/accounts_provider.dart:38), [ventas_screen.dart:191](C:/proyectos/valinor_ludoteca/lib/screens/ventas_screen.dart:191), [ventas_screen.dart:389](C:/proyectos/valinor_ludoteca/lib/screens/ventas_screen.dart:389), [inventario_screen.dart:17](C:/proyectos/valinor_ludoteca/lib/screens/inventario_screen.dart:17). Para 2.0: estado UI con propietario y liberación claros, IDs por línea.

### OP-22 · P3 · Errores y adaptación visual incompletos

Venta, carga y diálogos administrativos no ofrecen recuperación operativa ante fallos. Varias mutaciones no se esperan y no tienen estado de carga/error/reintento. Inventario captura una excepción y la muestra técnicamente. Anchos fijos y filas extensas exigen validación con ventanas pequeñas; no se realizó QA visual.

Evidencia: [ventas_screen.dart:35](C:/proyectos/valinor_ludoteca/lib/screens/ventas_screen.dart:35), [ventas_screen.dart:44](C:/proyectos/valinor_ludoteca/lib/screens/ventas_screen.dart:44), [inventario_screen.dart:107](C:/proyectos/valinor_ludoteca/lib/screens/inventario_screen.dart:107), [inventario_screen.dart:145](C:/proyectos/valinor_ludoteca/lib/screens/inventario_screen.dart:145), [management_screen.dart:43](C:/proyectos/valinor_ludoteca/lib/screens/management/management_screen.dart:43). Para 2.0: estados de operación, mensajes accionables y diseño adaptable.

## Matriz de reutilización

Conservar se refiere a comportamiento/identidad; no autoriza copiar implementaciones defectuosas.

| Componente o concepto | Decisión | Justificación |
|---|---|---|
| Marca Valinor Sanctum, logo y vocabulario conocido | Conservar | Identidad y familiaridad del operador. |
| Inventario, Ventas, Reportes, Administración | Adaptar | Mantener tareas conocidas y reorganizar navegación/permisos. |
| Búsqueda y autocompletado de productos | Adaptar | Útil; ligar selección a ID y limpiar al editar. |
| Nombre, precios, cantidad y lote | Adaptar | Separar catálogo, existencias, entradas y lotes. |
| Reposición sumando unidades | Conservar regla y reescribir | Generar movimiento y preservar costos con atomicidad. |
| Cuentas abiertas nombradas y múltiples líneas | Conservar regla y reescribir | Guardar automáticamente, recuperar y cerrar explícitamente. |
| Efectivo y Nequi | Adaptar | Catálogo de medios y pagos por montos separados de productos. |
| Totales y formato colombiano | Conservar intención y reescribir cálculo | Importes exactos y escala consistente. |
| Tarjetas de saldos | Adaptar | Valores derivados de operaciones confirmadas. |
| Gastos con categorías | Adaptar | Categorías configurables, motivo y documento. |
| Transferencias | Reescribir | Dos partidas enlazadas, atomicidad e historial. |
| Agregar a Caja Mayor | Reescribir | Aporte documentado y distinguible de ingreso operativo. |
| DatabaseHelper y setters directos de total | Reescribir | Evitar escrituras separadas y múltiples fuentes de verdad. |
| AccountsProvider, Account y SaleLine | Reescribir | Dominio independiente de UI con IDs y persistencia. |
| Credencial compartida incrustada | Reemplazar | Modelo de permisos y credenciales administradas según alcance. |
| Eliminación física del producto | Reemplazar | Archivo/baja y trazabilidad. |
| Historial de movimientos | Reescribir | Libro completo con actor, referencias y filtros. |
| Gráfica de distribución | Adaptar | Métricas comparables y signos contables correctos. |

## Capacidades nuevas para diseñar

- Servicios de aplicación transaccionales para cobro, reposición, gasto, transferencia y aporte.
- Persistencia automática de cuentas y líneas abiertas con recuperación tras reinicio.
- Cabecera de venta, líneas con instantáneas de nombre/precio/costo y pagos separados.
- Movimientos de inventario, entradas y bajas justificadas; lotes según necesidad validada.
- Libro monetario con partidas enlazadas y saldos derivados o verificables.
- Catálogos de cuentas, categorías y medios de pago.
- Identificación estable de operaciones y reintentos idempotentes.
- Anulaciones mediante reversos, conservando historia y referencias.
- Auditoría de actor, fecha, operación y motivo; permisos por acción.
- Cierre, arqueo y conciliación de caja con diferencias documentadas.
- Migración que preserve originales y marque registros ambiguos para revisión.

La política de reservas de inventario de cuentas abiertas, el significado de Deudas, el método de valoración, la escala monetaria y el alcance de permisos son decisiones de negocio pendientes; no deben inferirse de los defectos del sistema actual.
