# Modelo financiero, inventario y contratos transaccionales propuestos

Estado: diseño aprobado por el propietario el 18 de octubre de 2026. Este es el modelo preliminar completo; su aprobación no significa que todas las tablas o reglas estén implementadas. La fundación v1 y sus límites se describen en [incremento 01](10-incremento-01.md).

## 1. Alcance proporcional al negocio

Se propone una aplicación local para un equipo de escritorio, con SQLite como base de datos y una sola cola de escritura. Los documentos comerciales conservan el detalle de la operación; un libro interno de asientos balanceados registra sus efectos financieros. El usuario opera ventas, compras, pagos, gastos y transferencias, sin necesitar una pantalla de contabilidad general.

El libro evita mantener cifras independientes para «Caja», «Nequi» y «Deudas». Cada saldo se obtiene de movimientos identificables y reversibles. Las proyecciones para consultas y gráficos se pueden reconstruir desde documentos y movimientos; no constituyen otra fuente editable de saldos.

No se propone contabilidad fiscal completa ni se presupone un régimen tributario. La definición comercial de precios e impuestos debe acordarse antes de implementar ventas: cualquier importe separado como impuesto debe quedar fuera del ingreso propio. Una cifra desconocida no se convierte automáticamente en cero.

La primera versión opera con una moneda y una escala monetaria por instalación. No requiere nube, servidor, inteligencia artificial generativa, sincronización ni servicios externos.

## 2. Reglas que deben sostener todas las operaciones

1. Registrar venta, costo histórico, salida de inventario, obligación y cobro inmediato es una sola unidad transaccional. Si falla una parte, no queda ninguna de sus escrituras.
2. Una venta reconoce una entrega o prestación; un cobro reconoce dinero recibido. Pueden ocurrir en fechas distintas.
3. Comprar inventario incorpora un activo; el costo de mercancía vendida se reconoce cuando sale por una venta. Pagar al proveedor no vuelve a reconocer ese costo.
4. El costo y el precio de una venta confirmada son históricos e inmutables. Editar el catálogo no modifica documentos anteriores.
5. Las transferencias internas no son ventas ni gastos. Los aportes y retiros del propietario no forman parte del resultado operativo.
6. Los documentos confirmados no se eliminan. Se corrigen con devoluciones, notas o reversas vinculadas al original.
7. Las existencias no pueden ser negativas. Una reserva reduce disponibilidad, pero no existencia física ni valor del inventario.
8. Cualquier cobro o pago aplicado a una obligación respeta su saldo. Un excedente requiere registrarse explícitamente como anticipo; nunca desaparece ni crea un saldo negativo sin explicar.
9. Cada asiento tiene, como mínimo, dos líneas y cumple `suma(debe) = suma(haber)`, en la misma moneda.
10. Un comando repetido con la misma clave y contenido devuelve el resultado anterior. La misma clave con contenido diferente se rechaza.
11. Los importes desconocidos, estimados, reconstruidos y documentados se distinguen. El valor cero solo significa cero cuando existe evidencia suficiente.
12. Todas las métricas indican período, criterio, unidad y calidad de sus datos. Los períodos financieros no se mezclan con fechas de cobro.

## 3. Dinero, cantidades y fechas

### 3.1 Dinero entero

Todos los importes monetarios se almacenan en `INTEGER`, en la unidad mínima de la moneda configurada. Por ejemplo técnico, con escala 2, un importe de 12 345,67 se representa mediante `1234567`. No es un objetivo económico ni un dato del negocio.

La moneda y su escala quedan fijadas antes del primer documento; cambiarlas exige una conversión explícita, no editar una preferencia. La entrada se convierte directamente desde texto decimal a entero, sin pasar por `double`. También los descuentos porcentuales se representan mediante una escala declarada, no mediante aproximaciones binarias.

Las multiplicaciones y distribuciones se hacen con aritmética entera y control de desbordamiento. Los intermedios que lo requieran usan `BigInt` en Dart antes de comprobar que el resultado cabe en el rango admitido por SQLite. No se delega en una suma o multiplicación SQL que pueda desbordar y convertirse en REAL.

Cada regla declara el nivel y modo de redondeo. Propuesta: redondear una sola vez por línea al menor importe monetario y distribuir diferencias de un descuento global por restos mayores, con desempate por posición estable. El total del documento debe ser exactamente la suma de sus líneas. El redondeo de efectivo, si se necesita, constituye una diferencia explícita; no cambia silenciosamente el precio ni el margen.

SQLite explica que los valores REAL son aproximaciones y que los enteros dentro de su rango son exactos. Esta es la razón técnica para evitar REAL en dinero: [Floating Point Numbers](https://www.sqlite.org/floatingpoint.html).

### 3.2 Cantidades

- Productos de inventario: unidades enteras en el alcance inicial.
- Servicios: cantidad entera con `quantity_scale` explícita. Por ejemplo, una duración puede expresarse en minutos enteros; no es necesario inventar existencias para un servicio.
- Las líneas conservan unidad y escala históricas. No se permite sumar cantidades de unidades incompatibles.
- Una futura venta de productos fraccionables exige decidir previamente su unidad y escala; no se introduce de forma implícita.

### 3.3 Fechas

Se conservan `occurred_at_utc` (hecho), `recorded_at_utc` (registro), `business_date` y zona horaria del negocio. La fecha de vencimiento es un campo distinto. Los filtros usan intervalos semiabiertos: inicio incluido y final excluido.

El orden de costeo utiliza una secuencia de inventario persistida. En la primera versión no se permite insertar una compra con fecha efectiva anterior a salidas ya confirmadas para recalcular costos en secreto. Una corrección tardía se registra ahora, referencia el hecho original y expone la diferencia; un recosteo histórico sería una operación separada y controlada.

## 4. Inventario y costos FIFO por capas

### 4.1 Entrada de inventario

Una compra recibida crea una capa por producto y costo de adquisición. La capa conserva cantidad inicial, costo total, fecha, proveedor/documento y lote comercial cuando exista. El texto de lote comercial y la capa contable son conceptos diferentes: un lote puede ingresar a costos distintos.

El costo total incluye descuentos de compra y costos atribuibles cuya distribución se haya aprobado; la suma distribuida debe coincidir exactamente con el documento. No se deduce un costo de una lista de precios actual. Los impuestos recuperables, si el perfil del negocio los utiliza, no se mezclan con el costo del inventario.

En el primer incremento de compras, confirmar una compra significa mercancía recibida y costo final conocido. Pedidos, recepciones parciales, facturas posteriores y diferencias entre recepción y factura son ampliaciones separadas. No se simulan mediante cambios directos de existencias.

### 4.2 Salida y costo histórico

Una salida toma primero las capas disponibles de menor secuencia FIFO. Cada consumo conserva capa, cantidad y costo asignado. La línea de venta conserva su costo total histórico y la calidad de ese costo; un reporte nunca vuelve a consultar `purchasePrice` del catálogo para reconstruirlo.

Para distribuir un costo total entero `T` entre `Q` unidades sin pérdida, el costo del tramo de unidades `[a, b)` de una capa se define como:

`costo(a,b) = floor(b × T / Q) − floor(a × T / Q)`

`a` y `b` son límites consecutivos de consumo, con `0 ≤ a < b ≤ Q`. Las operaciones usan enteros de precisión suficiente. Los tramos de toda la capa suman exactamente `T`, con independencia de si una venta consume una o varias unidades.

Ejemplo sintético: una capa de 3 unidades cuesta 1 001 unidades monetarias mínimas. Sus tramos unitarios cuestan 333, 334 y 334; vender las tres unidades reconoce 1 001, sin residuo. Esto no exige que todos los artículos de la capa tengan un precio unitario entero idéntico.

### 4.3 Devoluciones, daños y conteos

- Una devolución vendible crea una entrada vinculada al consumo original y conserva el costo devuelto; no utiliza el costo actual de compra. La distribución de devoluciones parciales usa tramos estables del consumo original y no devuelve un costo mayor al reconocido.
- La capa de devolución registra tanto la fecha de retorno como la antigüedad de adquisición original. Su posición FIFO se define explícitamente al implementar; propuesta inicial: entrada operativa actual con antigüedad original preservada para análisis.
- Un artículo devuelto dañado se clasifica como no vendible o pérdida. No aumenta automáticamente el stock vendible.
- Un conteo físico genera un ajuste firmado con motivo y documento; no sustituye el saldo. Una merma disminuye inventario y registra pérdida; un aporte de mercancía del propietario se clasifica como capital, no como venta.
- El stock publicado es `suma(inventory_movements.quantity_delta)`. Una caché de saldo debe poder reconstruirse y reconciliarse con esa suma.

### 4.4 Datos históricos incompletos

Una capa histórica puede tener costo `unknown`; esto es diferente de una capa gratis con costo cero documentado. El sistema puede conservar sus cantidades, pero no afirmar su valoración completa. Una venta de esas unidades conserva costo desconocido y genera una advertencia de cobertura.

Los asientos monetarios solo contienen importes determinados. Si falta el costo, no se inventa el asiento de costo: se registra la incidencia vinculada a la venta y se bloquea la presentación de ganancia completa para ese alcance. Puede mostrarse costo conocido y margen de los documentos completos, identificando la parte excluida. Una estimación opcional se presenta por separado y con su método.

## 5. Ventas, cuentas abiertas, crédito y cobros

### 5.1 Cuenta abierta

Una `tab` es una agrupación operativa persistente, identificada por nombre o referencia. Sus líneas todavía no entregadas son borradores; pueden reservar stock. Al confirmar una entrega o consumo se crea una venta inmutable y se descuenta inventario, aunque el cliente pague después.

Esto permite servir durante una sesión sin perder el estado al cerrar la aplicación y sin esperar al cobro para registrar mercancía consumida. La cuenta puede agrupar varias entregas/ventas y pagos parciales.

Una cuenta abierta temporal no equivale a conceder crédito indefinido. El cierre requiere saldo cero o una conversión explícita a crédito con cliente identificado y vencimiento. El importe ya entregado y no cobrado existe como cuenta por cobrar, aunque la cuenta permanezca abierta.

### 5.2 Venta y pago separados

La venta contiene cantidades, descripciones, categorías, precios, descuentos e importes históricos. Si la clasificación actual del catálogo cambia, los informes históricos conservan su clasificación original; un informe que reclasifique usa una opción claramente identificada.

Convención del esquema: `gross_minor` y `unit_price_minor` representan importes de ingreso propio antes de descuento, excluidos impuestos separados; `net_revenue_minor = gross_minor − discount_minor` y `payable_minor = net_revenue_minor + tax_minor`. Una entrada de precio con impuesto incluido se normaliza mediante una regla explícita y conserva la evidencia del desglose. `tax_minor = 0` requiere un tratamiento definido; NULL significa desglose desconocido y no admite confirmar una venta nativa como ingreso exacto. Las ventas históricas sin ese desglose permanecen observaciones legadas hasta contar con evidencia suficiente.

Toda venta nativa confirmada del alcance inicial exige un importe total por pagar positivo y genera una obligación por cobrar. Una venta de contado genera también el pago y su aplicación, dentro de la misma transacción. Así se usa una única regla para contado, pago dividido, pago parcial y crédito, sin reconocer ingreso dos veces. Se permiten líneas gratuitas dentro de una venta de total positivo; una bonificación completamente gratuita requiere un flujo específico de entrega/consumo autorizado y queda fuera del primer alcance de ventas, en vez de generar obligaciones o pagos ficticios de cero.

Un pago puede tener partes en efectivo y en una cuenta digital, con sus métodos de pago. `cash_account` representa dónde está el dinero; `payment_method` representa cómo se recibió. Dos métodos pueden liquidar a la misma cuenta, y una misma denominación comercial puede corresponder a cuentas diferentes.

El importe entregado y el cambio se conservan como datos de operación. El movimiento de caja es el importe neto aceptado. Una comisión se registra como gasto o costo financiero separado y relacionado con el pago; no se pierde al reducir el ingreso de ventas.

### 5.3 Anticipos y sobrepagos

Cobrar antes de entregar mercancía o prestar un servicio crea un anticipo del cliente, no una venta. Al entregar se reconoce la venta y se aplica el anticipo contra la cuenta por cobrar, sin nuevo movimiento de caja.

El pago aplicado no puede superar el pendiente de la obligación. Si el operador acepta un excedente, debe confirmar su clasificación como anticipo del cliente. Los anticipos se pueden aplicar o reembolsar; no se convierten automáticamente en ingresos.

### 5.4 Cancelaciones y devoluciones

- Un borrador no entregado puede cancelarse y libera sus reservas; no genera reversas financieras porque no fue contabilizado.
- Una venta confirmada se corrige mediante un documento vinculado. La parte pendiente reduce la cuenta por cobrar; la parte ya cobrada crea una obligación de reembolso o saldo a favor explícito.
- El reembolso es un pago de salida separado, que extingue esa obligación. Emitir una devolución no demuestra por sí solo que el dinero salió de caja.
- La devolución física y la devolución de dinero se distinguen. Solo se restituye inventario cuando la mercancía efectivamente vuelve y se clasifica.
- Se impide devolver cantidad o importe por encima de lo vendido, aplicar dos veces la misma reversa o reembolsar por encima del saldo autorizado.
- Una reversa de cobro vuelve a abrir el pendiente correspondiente; no elimina la venta. La trazabilidad del pago original permanece.

Los informes suman los importes firmados de originales y correcciones por su fecha efectiva. No eliminan del pasado una venta porque su estado actual sea «revertida», ni suman además una reversa que ya neutralizaron al filtrar.

## 6. Asientos internos y ejemplos de flujo

Las siguientes cifras son datos sintéticos para explicar reglas, expresados en una unidad monetaria común. No son saldos iniciales, metas ni recomendaciones económicas.

| Operación | Debe | Haber | Efecto relevante |
| --- | --- | --- | --- |
| Compra recibida a crédito por 60 | Inventario 60 | Proveedores por pagar 60 | Aumenta stock; todavía no hay costo vendido ni egreso de dinero |
| Pago de esa compra | Proveedores por pagar 60 | Cuenta de dinero 60 | Disminuye caja y la obligación; no repite el costo |
| Venta entregada por 100, costo histórico 60 | Clientes por cobrar 100; CMV 60 | Ventas 100; Inventario 60 | Reconoce venta y margen bruto 40 |
| Cobro parcial de 40 | Cuenta de dinero 40 | Clientes por cobrar 40 | Caja +40 y pendiente 60; ingreso de ventas adicional cero |
| Cobro restante posterior | Cuenta de dinero 60 | Clientes por cobrar 60 | Cancela la deuda sin cambiar el período de la venta |
| Anticipo de cliente por 30 | Cuenta de dinero 30 | Anticipos de clientes 30 | Hay cobro, pero aún no ingreso por ventas |
| Aplicación de anticipo | Anticipos de clientes 30 | Clientes por cobrar 30 | Reduce ambos pendientes, sin volver a cobrar |
| Gasto operativo devengado por 20 | Gasto operativo 20 | Obligación por pagar 20 | Reconoce gasto aunque se pague después |
| Transferencia interna por 25 | Cuenta destino 25 | Cuenta origen 25 | Saldo consolidado y resultado no cambian |
| Aporte del propietario por 50 | Cuenta de dinero 50 | Aportes de capital 50 | Aumenta liquidez, sin venta ni utilidad |
| Retiro del propietario por 10 | Retiros de capital 10 | Cuenta de dinero 10 | Reduce liquidez, sin gasto operativo |

Ejemplo de devolución completa de la venta anterior cuando solo se habían cobrado 40: la nota carga devoluciones de ventas por 100 y abona clientes por cobrar por 60 y reembolsos a clientes por pagar por 40. Si toda la mercancía vuelve vendible, carga inventario por 60 y abona CMV por 60. El pago posterior de los 40 carga reembolsos por pagar y abona caja. Si una parte no retorna, no se restituye su inventario y se documenta el tratamiento de su costo.

El asiento balanceado es necesario, pero no suficiente: también deben conciliar cantidades, costos, documentos, pagos y obligaciones. Se evitan cuentas genéricas de ajuste que oculten diferencias sin motivo.

## 7. Servicios, pasadías y eventos

Un servicio se reconoce al prestarse. Una inscripción cobrada antes de un torneo es anticipo hasta la entrega de la prestación definida. El sistema necesita registrar la fecha de cumplimiento; la fecha del pago por sí sola no permite atribuir ingresos al evento correcto.

Para el alcance inicial se propone cumplimiento completo por prestación. Los pases de varias visitas, bonos y reconocimiento parcial requieren una política adicional de unidades pendientes; no se declaran vendidos y consumidos de manera simultánea por defecto.

El costo directo puede provenir de:

- Mercancía consumida o entregada como parte del servicio, con salida de inventario y costo histórico.
- Un servicio externo o premio adquirido para un evento, registrado como costo directo y relacionado con el evento.
- Una asignación explícita de un costo compartido, con base de reparto y distribución exacta de restos.

Un gasto se clasifica una sola vez: directo de servicio/evento u operativo. Relacionar un gasto con un evento no autoriza restarlo nuevamente del resultado general. Los premios que salen del stock se costean mediante movimiento de inventario; no se registran además como otra compra consumida.

Un vínculo directo de gasto a un evento o servicio equivale a asignar el 100 % a ese destino. Si se utilizan filas de reparto, estas sustituyen ese vínculo para el cálculo; no se suma la fuente una vez por su etiqueta y otra por su asignación. El costo histórico de una línea de producto conserva su salida de inventario. Los costos externos de un servicio registrados posteriormente mantienen su documento y fecha propios; no reescriben ese snapshot ni transforman una ausencia previa de costo en un cero definitivo.

La rentabilidad de un evento es su ingreso reconocido neto menos sus costos directos registrados. Si no se conocen todos, el resultado se etiqueta como parcial. Los gastos generales solo se distribuyen en una vista separada y con una base visible; no se presenta una asignación arbitraria como costo directo real.

## 8. Esquema preliminar concreto

Es un esquema conceptual con tipos y restricciones para aprobar; no es una migración lista para ejecutar. Se omiten índices secundarios repetitivos y columnas de presentación para facilitar la revisión.

### 8.1 Convenciones de integridad

- `ID` significa `TEXT PRIMARY KEY NOT NULL`, con identificador generado por la aplicación.
- `FK` significa referencia real con `ON DELETE RESTRICT` para historia confirmada. Los catálogos se desactivan con `is_active`; no se eliminan si tienen movimientos.
- `MONEY` significa `INTEGER` con comprobación de tipo entero y límites explícitos del dominio. Un importe desconocido solo admite NULL en campos expresamente diseñados para ello.
- Cantidades y escalas usan comprobación de tipo entero. Toda entrada exige campos obligatorios, rangos y estado válido.
- Fechas se serializan con un único formato. Estados usan `CHECK` con valores enumerados; no textos libres.
- Los borradores son editables; confirmar congela sus datos comerciales. Los cambios de estado administrativos no reescriben sus importes.
- Los invariantes entre varias filas se verifican en el servicio de aplicación dentro de la misma transacción, con restricciones SQL complementarias. Un `CHECK` de una fila no puede garantizar por sí solo el balance de todo el asiento.

### 8.2 Base y libro financiero

| Tabla | Columnas mínimas, claves y restricciones |
| --- | --- |
| `app_profile` | `id INTEGER PK CHECK(id=1)`, `currency_code TEXT NOT NULL`, `money_scale INTEGER NOT NULL CHECK(0..6)`, `business_timezone TEXT NOT NULL`, `profile_id TEXT UNIQUE NOT NULL`. Sin saldos iniciales predeterminados. |
| `command_log` | `id ID`, `command_type TEXT NOT NULL`, `payload_hash TEXT NOT NULL`, `actor_id FK→actors NOT NULL`, `authorization_policy_version TEXT NOT NULL`, `response_version INTEGER NOT NULL`, `response_json TEXT NOT NULL`, `committed_at_utc TEXT NOT NULL`. Respuesta inmutable con IDs, importes y saldos al commit; un reintento no consulta saldos actuales para simular la respuesta anterior. Solo se conserva el comando junto con sus resultados confirmados; un fallo revierte también su registro. |
| `business_documents` | `id ID`, `command_id FK→command_log`, `command_sequence INTEGER NOT NULL`, `actor_id FK→actors NOT NULL`, `type TEXT NOT NULL`, `status TEXT CHECK(draft,posted,reversed)`, `occurred_at_utc TEXT`, `business_date TEXT`, `recorded_at_utc TEXT NOT NULL`, `original_document_id FK→business_documents NULL`, `reason TEXT NULL`, `source_kind TEXT CHECK(native,legacy,synthetic)`, `date_quality TEXT CHECK(documented,reconstructed,unknown)`, `UNIQUE(command_id,command_sequence)`. Un documento posted exige fechas y moneda definida por perfil; el actor coincide con el comando que lo confirma. |
| `ledger_accounts` | `id ID`, `code TEXT UNIQUE NOT NULL`, `name TEXT NOT NULL`, `class TEXT CHECK(asset,liability,equity,revenue,cost,expense)`, `role TEXT NOT NULL`, `is_active INTEGER CHECK(0,1)`. Catálogo interno reducido, con roles para inventario, clientes, proveedores, anticipos, ventas, devoluciones, CMV, costos directos, gastos y capital. |
| `journal_entries` | `id ID`, `document_id FK→business_documents UNIQUE NOT NULL`, `posted_at_utc TEXT NOT NULL`, `reversal_of_id FK→journal_entries NULL`, `cost_completeness TEXT CHECK(complete,partial,unknown,not_applicable)`. Un documento financiero confirmado tiene exactamente un asiento; un borrador no tiene ninguno. |
| `journal_lines` | `id ID`, `entry_id FK→journal_entries`, `sequence INTEGER NOT NULL`, `account_id FK→ledger_accounts`, `debit_minor MONEY NOT NULL CHECK(>=0)`, `credit_minor MONEY NOT NULL CHECK(>=0)`, `CHECK(exactamente uno de debe/haber >0)`, `UNIQUE(entry_id,sequence)`. Todos los importes son de la moneda del perfil. |
| `cash_accounts` | `id ID`, `ledger_account_id FK→ledger_accounts UNIQUE NOT NULL`, `name TEXT NOT NULL`, `kind TEXT CHECK(cash,bank,mobile,clearing)`, `is_available INTEGER CHECK(0,1)`, `is_active INTEGER CHECK(0,1)`. Fondos en tránsito pueden ser activos sin considerarse caja disponible. |
| `payment_methods` | `id ID`, `code TEXT UNIQUE NOT NULL`, `name TEXT NOT NULL`, `is_active INTEGER CHECK(0,1)`. No contiene saldo. |
| `counterparties` | `id ID`, `name TEXT NOT NULL`, `is_customer INTEGER CHECK(0,1)`, `is_supplier INTEGER CHECK(0,1)`, `is_active INTEGER CHECK(0,1)`. Identificación y contacto son opcionales según función; no se inventan clientes para datos históricos. |

### 8.3 Catálogo, documentos e inventario

| Tabla | Columnas mínimas, claves y restricciones |
| --- | --- |
| `categories` | `id ID`, `name TEXT NOT NULL`, `is_active INTEGER CHECK(0,1)`. |
| `catalog_items` | `id ID`, `sku TEXT NULL UNIQUE`, `name TEXT NOT NULL`, `kind TEXT CHECK(product,service)`, `category_id FK→categories NULL`, `unit_code TEXT NOT NULL`, `quantity_scale INTEGER CHECK(0..6)`, `list_price_minor MONEY CHECK(>=0)`, `reorder_point INTEGER NULL CHECK(>=0)`, `is_active INTEGER CHECK(0,1)`. Producto exige escala 0 inicialmente. El costo de compra actual, si se muestra, es informativo y no sustituye capas. |
| `tabs` | `id ID`, `label TEXT NOT NULL`, `customer_id FK→counterparties NULL`, `opened_at_utc TEXT NOT NULL`, `closed_at_utc TEXT NULL`, `status TEXT CHECK(open,closed,cancelled)`. Cerrar exige conciliación del pendiente o conversión explícita a crédito. |
| `tab_lines` | `id ID`, `tab_id FK→tabs`, `item_id FK→catalog_items`, `quantity_minor INTEGER CHECK(>0)`, `quantity_scale INTEGER NOT NULL`, `state TEXT CHECK(draft,reserved,delivered,cancelled)`, `delivered_sale_line_id FK→sale_lines NULL UNIQUE`. Solo se edita antes de delivered. |
| `stock_reservations` | `id ID`, `tab_line_id FK→tab_lines UNIQUE`, `product_id FK→catalog_items`, `quantity INTEGER CHECK(>0)`, `state TEXT CHECK(active,consumed,released)`. Activación comprueba disponibilidad bajo transacción; la reserva no crea ingreso ni salida física. |
| `sales` | `document_id PK/FK→business_documents`, `customer_id FK→counterparties NULL`, `tab_id FK→tabs NULL`, `terms TEXT CHECK(immediate,tab,credit)`, `due_date TEXT NULL`, `gross_minor MONEY CHECK(>=0)`, `discount_minor MONEY CHECK(0..gross)`, `net_revenue_minor MONEY CHECK(>=0)`, `tax_minor MONEY NULL CHECK(>=0)`, `payable_minor MONEY CHECK(>0)`, `price_quality TEXT CHECK(documented,reconstructed,unknown)`. Crédito exige cliente y vencimiento; importes deben conciliar con líneas y tratamiento tributario aprobado. |
| `sale_lines` | `id ID`, `sale_id FK→sales.document_id`, `sequence INTEGER NOT NULL`, `item_id FK→catalog_items`, `name_snapshot TEXT`, `category_id_snapshot TEXT NULL`, `category_name_snapshot TEXT NULL`, `unit_snapshot TEXT`, `quantity_minor INTEGER CHECK(>0)`, `quantity_scale INTEGER NOT NULL`, `unit_price_minor MONEY CHECK(>=0)`, `gross_minor MONEY`, `discount_minor MONEY`, `net_revenue_minor MONEY`, `tax_minor MONEY NULL`, `historical_cost_minor MONEY NULL`, `cost_quality TEXT CHECK(documented,estimated,reconstructed,unknown,not_applicable)`, `event_id FK→events NULL`, `UNIQUE(sale_id,sequence)`. Descuento no supera bruto; costo NULL no se transforma en cero. |
| `purchases` | `document_id PK/FK→business_documents`, `supplier_id FK→counterparties`, `supplier_reference TEXT NULL`, `received_at_utc TEXT NOT NULL`, `payable_minor MONEY CHECK(>0)`, `terms TEXT CHECK(immediate,credit)`, `due_date TEXT NULL`. La referencia de proveedor admite repetición legítima; control de duplicados combina proveedor, referencia y evidencia. |
| `purchase_lines` | `id ID`, `purchase_id FK→purchases.document_id`, `sequence INTEGER NOT NULL`, `product_id FK→catalog_items`, `quantity INTEGER CHECK(>0)`, `commercial_batch TEXT NULL`, `acquisition_total_minor MONEY CHECK(>=0)`, `cost_quality TEXT CHECK(documented,estimated,unknown)`, `UNIQUE(purchase_id,sequence)`. Compra nativa confirmada del alcance inicial exige costo documentado. |
| `inventory_movements` | `id ID`, `document_id FK→business_documents`, `sequence INTEGER NOT NULL`, `stock_sequence INTEGER UNIQUE NOT NULL`, `product_id FK→catalog_items`, `kind TEXT CHECK(purchase,sale,return,service_use,waste,count_adjustment,opening,capital)`, `quantity_delta INTEGER NOT NULL CHECK(!=0)`, `value_delta_minor MONEY NULL`, `sale_line_id FK→sale_lines NULL`, `purchase_line_id FK→purchase_lines NULL`, `reversal_of_id FK→inventory_movements NULL`, `reason TEXT NULL`, `UNIQUE(document_id,sequence)`. Tipo y signo son coherentes; solo productos tienen stock. |
| `cost_layers` | `id ID`, `inbound_movement_id FK→inventory_movements UNIQUE`, `product_id FK→catalog_items`, `initial_quantity INTEGER CHECK(>0)`, `total_cost_minor MONEY NULL CHECK(>=0)`, `cost_quality TEXT CHECK(documented,estimated,reconstructed,unknown)`, `fifo_sequence INTEGER UNIQUE NOT NULL`, `acquired_at_utc TEXT NULL`, `original_layer_id FK→cost_layers NULL`, `commercial_batch TEXT NULL`. Con unknown el costo es NULL; documented exige importe. Saldo de capa es una proyección reconciliable. |
| `cost_allocations` | `id ID`, `outbound_movement_id FK→inventory_movements`, `layer_id FK→cost_layers`, `unit_start INTEGER CHECK(>=0)`, `unit_end INTEGER CHECK(>unit_start)`, `quantity INTEGER CHECK(=unit_end-unit_start)`, `cost_minor MONEY NULL CHECK(>=0)`, `source_allocation_id FK→cost_allocations NULL`, `UNIQUE(outbound_movement_id,layer_id,unit_start)`. No se solapan tramos consumidos de una capa ni se supera su cantidad. Retornos referencian los tramos originales y crean capa de entrada. |
| `sales_returns` | `document_id PK/FK→business_documents`, `original_sale_id FK→sales.document_id`, `reason TEXT NOT NULL`, `net_revenue_reversal_minor MONEY CHECK(>=0)`, `tax_reversal_minor MONEY CHECK(>=0)`, `payable_reversal_minor MONEY CHECK(>=0)`. Totales iguales a la suma de líneas; no elimina la venta original. |
| `sales_return_lines` | `id ID`, `return_id FK→sales_returns.document_id`, `sale_line_id FK→sale_lines`, `quantity_minor INTEGER CHECK(>0)`, `gross_reversal_minor MONEY CHECK(>=0)`, `discount_reversal_minor MONEY CHECK(>=0)`, `revenue_reversal_minor MONEY CHECK(>=0)`, `tax_reversal_minor MONEY CHECK(>=0)`, `cost_reversal_minor MONEY NULL`, `stock_disposition TEXT CHECK(restock,damaged,not_returned,service)`. Reversión neta = bruto devuelto - descuento devuelto; total acumulado por componente no supera el original. Distribución parcial conserva importes y tratamiento tributario históricos, con restos deterministas. |
| `returned_cost_allocations` | `id ID`, `return_line_id FK→sales_return_lines`, `original_allocation_id FK→cost_allocations`, `original_unit_start INTEGER CHECK(>=0)`, `original_unit_end INTEGER CHECK(>original_unit_start)`, `cost_minor MONEY NULL`, `returned_layer_id FK→cost_layers NULL`. Los tramos devueltos no se solapan ni exceden el tramo original; cada capa de retorno concilia con los tramos que la originan. |

`category_id_snapshot` conserva la identidad histórica como texto, no obliga a reconsultar una categoría que el catálogo pudiera cambiar. Los nombres snapshot permiten explicar documentos incluso después de desactivar artículos.

### 8.4 Obligaciones, pagos y gastos

| Tabla | Columnas mínimas, claves y restricciones |
| --- | --- |
| `obligations` | `id ID`, `origin_document_id FK→business_documents`, `sequence INTEGER NOT NULL`, `counterparty_id FK→counterparties NULL`, `tab_id FK→tabs NULL`, `kind TEXT CHECK(sale_receivable,supplier_payable,expense_payable,customer_advance,customer_refund,supplier_advance,opening_receivable,opening_payable)`, `control_account_id FK→ledger_accounts`, `initial_minor MONEY CHECK(>0)`, `issued_at_utc TEXT NOT NULL`, `due_date TEXT NULL`, `UNIQUE(origin_document_id,sequence)`. La naturaleza determina si es activo o pasivo; saldo se deriva, no se sobreescribe. |
| `payments` | `document_id PK/FK→business_documents`, `direction TEXT CHECK(in,out)`, `counterparty_id FK→counterparties NULL`, `total_minor MONEY CHECK(>0)`, `reference TEXT NULL`, `reversal_of_payment_id FK→payments.document_id NULL`. Total = suma de partes y se explica íntegramente mediante aplicaciones o anticipos explícitos. |
| `payment_parts` | `id ID`, `payment_id FK→payments.document_id`, `sequence INTEGER NOT NULL`, `cash_account_id FK→cash_accounts`, `payment_method_id FK→payment_methods`, `amount_minor MONEY CHECK(>0)`, `tendered_minor MONEY NULL`, `change_minor MONEY NULL CHECK(>=0)`, `UNIQUE(payment_id,sequence)`. Cuando hay entregado/cambio: entregado − cambio = importe aceptado. |
| `settlements` | `id ID`, `document_id FK→business_documents`, `obligation_id FK→obligations`, `sequence INTEGER NOT NULL`, `payment_id FK→payments.document_id NULL`, `amount_signed_minor MONEY CHECK(!=0)`, `reversal_of_id FK→settlements NULL`, `UNIQUE(document_id,sequence)`. Positivo extingue saldo; negativo revierte una aplicación previa. El origen puede ser pago, nota o aplicación de anticipo. No representa dinero por sí mismo. |
| `expense_categories` | `id ID`, `name TEXT NOT NULL`, `cost_class TEXT CHECK(operating,direct_service,direct_event)`, `ledger_account_id FK→ledger_accounts`, `is_active INTEGER CHECK(0,1)`. No incluye compras de inventario, transferencias ni capital. |
| `expenses` | `document_id PK/FK→business_documents`, `supplier_id FK→counterparties NULL`, `category_id FK→expense_categories`, `recognized_date TEXT NOT NULL`, `amount_minor MONEY CHECK(>0)`, `description TEXT NOT NULL`, `event_id FK→events NULL`, `service_sale_line_id FK→sale_lines NULL`, `quality TEXT CHECK(documented,estimated,unknown)`. Gasto confirmado requiere importe conocido; clase directa exige vínculo o una asignación explícita. |
| `fund_transfers` | `document_id PK/FK→business_documents`, `from_account_id FK→cash_accounts`, `to_account_id FK→cash_accounts`, `amount_minor MONEY CHECK(>0)`, `CHECK(from_account_id != to_account_id)`. Las comisiones son gastos relacionados, no diferencia oculta entre origen y destino. |
| `capital_movements` | `document_id PK/FK→business_documents`, `kind TEXT CHECK(contribution,withdrawal)`, `cash_account_id FK→cash_accounts NULL`, `amount_minor MONEY CHECK(>0)`, `description TEXT NOT NULL`. Aporte/retiro en mercancía referencia movimientos de inventario y no se finge efectivo. |

`saldo_obligación = initial_minor − suma(settlements.amount_signed_minor)`. Al aplicar un anticipo existente a una venta se crean dos aplicaciones vinculadas al mismo documento: una reduce el anticipo y otra reduce la cuenta por cobrar. El asiento carga el pasivo de anticipo y abona clientes por cobrar; no se crea pago nuevo.

Cada aplicación valida la naturaleza de obligación, contraparte, importe y asiento. No se aceptan aplicaciones negativas arbitrarias, pagos a una venta de otra persona sin una reasignación explícita, ni diferencias sin clasificar. La suma de obligaciones por cuenta de control debe reconciliar con el saldo del libro para el mismo alcance.

### 8.5 Servicios, eventos, caja y calidad

| Tabla | Columnas mínimas, claves y restricciones |
| --- | --- |
| `events` | `id ID`, `name TEXT NOT NULL`, `kind TEXT CHECK(event,tournament,day_pass)`, `starts_at_utc TEXT NOT NULL`, `ends_at_utc TEXT NULL`, `status TEXT CHECK(planned,completed,cancelled)`. Cancelar evento no borra cobros ni gastos vinculados. |
| `service_fulfillments` | `id ID`, `sale_line_id FK→sale_lines`, `event_id FK→events NULL`, `fulfilled_at_utc TEXT NOT NULL`, `quantity_minor INTEGER CHECK(>0)`, `quantity_scale INTEGER NOT NULL`, `reference TEXT NULL`. No se confirma más prestación que la vendida/contratada. En el alcance inicial la venta se confirma con cumplimiento total. |
| `direct_cost_allocations` | `id ID`, `expense_document_id FK→expenses.document_id`, `service_sale_line_id FK→sale_lines NULL`, `event_id FK→events NULL`, `amount_minor MONEY CHECK(>0)`, `allocation_basis TEXT NOT NULL`, `CHECK(exactamente un destino)`. Suma asignada no supera gasto; el mismo costo no se añade además a gastos operativos. |
| `cash_sessions` | `id ID`, `cash_account_id FK→cash_accounts`, `opened_at_utc TEXT`, `closed_at_utc TEXT NULL`, `opening_count_minor MONEY CHECK(>=0)`, `closing_count_minor MONEY NULL CHECK(>=0)`, `status TEXT CHECK(open,closed)`. Índice único parcial propuesto para una sesión abierta por caja. |
| `cash_reconciliations` | `document_id PK/FK→business_documents`, `session_id FK→cash_sessions`, `expected_minor MONEY`, `counted_minor MONEY CHECK(>=0)`, `difference_minor MONEY`, `reason TEXT NOT NULL`, `CHECK(difference=counted−expected)`. Registrar conteo no cambia el libro; reconocer ajuste de diferencia es una operación explícita relacionada. |
| `data_quality_issues` | `id ID`, `document_id FK→business_documents NULL`, `sale_line_id FK→sale_lines NULL`, `layer_id FK→cost_layers NULL`, `issue_code TEXT NOT NULL`, `field_name TEXT NOT NULL`, `quality TEXT CHECK(missing,estimated,reconstructed,conflicting)`, `description TEXT NOT NULL`, `resolved_by_document_id FK→business_documents NULL`. Una incidencia identifica un objeto/ámbito concreto y su procedencia. |

### 8.6 Compatibilidad e historia legada

El modo preferido para el original consiste en conservar sus registros incompletos como observaciones legadas y establecer existencias y saldos iniciales mediante aperturas verificadas en una fecha de corte. No se contabilizan otra vez las ventas anteriores contra ese stock ni se suman todos los snapshots antiguos de caja.

| Tabla | Columnas mínimas, claves y restricciones |
| --- | --- |
| `import_runs` | `id ID`, `source_namespace TEXT NOT NULL`, `backup_sha256 TEXT NOT NULL`, `source_schema_version INTEGER NULL`, `mode TEXT CHECK(archive_and_opening,evidenced_history)`, `cutoff_business_date TEXT NULL`, `started_at_utc TEXT NOT NULL`, `finished_at_utc TEXT NULL`, `status TEXT CHECK(preview,running,succeeded,failed,reverted)`, `control_summary_json TEXT NULL`. El hash identifica el archivo, no reemplaza la identidad estable del origen. |
| `legacy_observations` | `id ID`, `run_id FK→import_runs`, `source_namespace TEXT NOT NULL`, `source_entity TEXT NOT NULL`, `source_key TEXT NOT NULL`, `payload_json TEXT NOT NULL`, `payload_sha256 TEXT NOT NULL`, `quality TEXT CHECK(partial,reconstructed,conflicting,documented)`, `limitations_json TEXT NOT NULL`, `UNIQUE(source_namespace,source_entity,source_key)`. Payload con campos comerciales seleccionados y validados; no copia secretos ni un volcado indiscriminado. No genera asiento por existir. |
| `import_id_map` | `id ID`, `first_run_id FK→import_runs`, `source_namespace TEXT NOT NULL`, `source_entity TEXT NOT NULL`, `source_key TEXT NOT NULL`, `source_payload_sha256 TEXT NOT NULL`, `target_document_id FK→business_documents NULL`, `target_item_id FK→catalog_items NULL`, `target_counterparty_id FK→counterparties NULL`, `target_observation_id FK→legacy_observations NULL`, `CHECK(exactamente un destino)`, `UNIQUE(source_namespace,source_entity,source_key)`. La identidad compartida entre respaldos impide recrear el mismo hecho por cambiar el archivo. |
| `import_issues` | `id ID`, `run_id FK→import_runs`, `source_entity TEXT NULL`, `source_key TEXT NULL`, `severity TEXT CHECK(info,warning,error)`, `issue_code TEXT NOT NULL`, `description TEXT NOT NULL`, `resolution_document_id FK→business_documents NULL`. Las diferencias y exclusiones permanecen auditables. |

`source_namespace` identifica el origen y su linaje estable; no se obtiene de la fecha del respaldo ni de un hash que cambie en cada copia. Si un registro con la misma identidad tiene contenido distinto, se genera conflicto para revisión, no una segunda transacción ni una actualización histórica silenciosa. Si se detecta reutilización de claves tras reinicializar una base, debe resolverse la identidad de origen antes de importar.

Las aperturas llevan documentos explícitos y controles de unicidad por origen, tipo y objeto de apertura; la fecha diferente de un respaldo no habilita otra apertura sobre las mismas existencias o saldos ya incorporados. La reconstrucción contable histórica solo procede si existe evidencia suficiente de precios, costos, relaciones y cobros. Un precio actual nunca se presenta como precio histórico.

El diseño de importación se desarrolla aparte; estas tablas son propuestas para una fase posterior. No se agregan importadores ni se abren bases de producción en esta etapa.

### 8.7 Identidad, análisis y planificación

Estas entidades también son propuestas incrementales; no obligan a construir ahora todos sus formularios.

| Tabla | Columnas mínimas, claves y restricciones |
| --- | --- |
| `actors` | `id ID`, `display_name TEXT NOT NULL`, `kind TEXT CHECK(person,system,synthetic)`, `is_active INTEGER CHECK(0,1)`. Propietario y operadores reales son person; importaciones identifican además al responsable que las autorizó. Actores synthetic solo en perfiles de prueba. No se inventa el actor histórico legado: se conserva como desconocido en la observación. |
| `local_credentials` | `actor_id PK/FK→actors`, `verifier TEXT NOT NULL`, `scheme TEXT NOT NULL`, `parameters_json TEXT NOT NULL`. Verificación mediante biblioteca adecuada que se validará al implementar; nunca contraseña en claro, valor predeterminado ni credencial del original. No incluir secretos en auditoría/respuestas. |
| `roles` | `id ID`, `code TEXT UNIQUE NOT NULL`, `name TEXT NOT NULL`. Catálogo inicial propuesto propietario/operador. |
| `actor_roles` | `actor_id FK→actors`, `role_id FK→roles`, `PRIMARY KEY(actor_id,role_id)`. |
| `role_permissions` | `role_id FK→roles`, `permission_code TEXT NOT NULL`, `PRIMARY KEY(role_id,permission_code)`. Códigos definidos en aplicación; autorización en cada caso de uso. |
| `audit_events` | `id ID`, `actor_id FK→actors NULL`, `occurred_at_utc TEXT NOT NULL`, `action TEXT NOT NULL`, `subject_id TEXT NULL`, `command_id FK→command_log NULL`, `outcome TEXT CHECK(allowed,denied,failed)`, `policy_version TEXT`, `reason TEXT NULL`. Los éxitos sensibles se confirman con la operación. Denegaciones/fallos se registran sin afirmar que hubo movimiento; campos sin credenciales ni payload sensible. |
| `analysis_rule_configs` | `id ID`, `rule_code TEXT NOT NULL`, `rule_version TEXT NOT NULL`, `parameters_json TEXT NOT NULL`, `configured_by FK→actors`, `is_enabled INTEGER CHECK(0,1)`. Sin umbrales económicos ocultos; conservar versiones usadas por evaluaciones. |
| `analysis_findings` | `id ID`, `rule_config_id FK→analysis_rule_configs`, `period_start_utc TEXT`, `period_end_utc TEXT`, `evaluated_at_utc TEXT`, `evidence_json TEXT`, `criterion_json TEXT`, `suggested_action TEXT`, `limitations_json TEXT`, `status TEXT CHECK(new,seen,dismissed,resolved)`. Guardar resultados no modifica hechos. |
| `scenarios` | `id ID`, `name TEXT`, `period_start TEXT`, `period_end TEXT`, `model_version TEXT`, `base_reference_json TEXT`, `assumptions_json TEXT`, `results_json TEXT`, `created_by FK→actors`. Supuestos y resultados hipotéticos separados de documentos operativos. |
| `budgets` | `id ID`, `name TEXT`, `period_start TEXT`, `period_end TEXT`, `items_json TEXT`, `created_by FK→actors`. Partidas con métrica, clase, unidad y valor ingresados por usuario; sin presupuesto predeterminado. |
| `goals` | `id ID`, `metric_code TEXT`, `target_value_scaled INTEGER`, `value_scale INTEGER`, `unit TEXT`, `period_start TEXT`, `period_end TEXT`, `criterion_json TEXT`, `created_by FK→actors`, `is_active INTEGER CHECK(0,1)`. Cero filas es un estado normal; ningún objetivo económico se crea automáticamente. |

Las columnas JSON son contratos validados y versionados de configuración/evidencia, no una alternativa a normalizar importes, movimientos y relaciones transaccionales. No se necesita una extensión JSON para contabilizar operaciones ni una dependencia externa para ejecutar reglas.

## 9. Contratos de aplicación y consultas

### 9.1 Escritura de comandos

Operaciones previstas: `PostSale`, `ReceivePurchase`, `CollectPayment`, `PayObligation`, `RecordAdvance`, `ApplyAdvance`, `PostExpense`, `TransferFunds`, `RecordCapitalMovement`, `ReturnSale`, `ReversePayment`, `AdjustInventory`, `FulfillService` y `CloseCashSession`.

Cada comando recibe identificador de idempotencia, instante/fecha efectiva, referencias y datos de operación. Devuelve identificadores confirmados, importes y saldos relevantes o un error de dominio. No expone la conexión SQLite a widgets ni acepta que la pantalla determine el asiento final.

Secuencia común:

1. Validar formato, moneda, unidades y autorización local de la acción, cuando existan roles.
2. Abrir transacción con el ejecutor de base de datos; consultar idempotencia y volver a leer los datos necesarios bajo esa transacción.
3. Validar stock/disponibilidad, saldos, estados, descuentos, límites de devolución y calidad de costos.
4. Crear documentos inmutables, movimientos/capas, obligaciones/aplicaciones y asientos, usando exclusivamente el mismo ejecutor transaccional.
5. Verificar totales, balance, cantidades y conciliaciones del comando.
6. Registrar su resultado idempotente y confirmar. Actualizar la interfaz solo después del commit.

El registro de un fallo no debe convertir un intento fallido en un comando aplicado. Un fallo a mitad de escritura revierte todo; un reinicio tras commit con respuesta perdida permite recuperar el resultado mediante la clave.

SQLite ofrece atomicidad de todas las modificaciones incluidas en una transacción: [SQLite Is Transactional](https://www.sqlite.org/transactional.html). Las claves foráneas deben activarse y verificarse por conexión antes de iniciar las operaciones: [SQLite Foreign Key Support](https://www.sqlite.org/foreignkeys.html).

### 9.2 CQRS ligero

Se separan comandos y consultas mediante interfaces locales, sin bus distribuido, event sourcing general ni infraestructura adicional.

- Saldos de cuentas y resultado financiero: `journal_entries` + `journal_lines`, con clasificación de cuentas y calidad del documento origen.
- Ventas por producto/categoría: `sale_lines` + devoluciones vinculadas y snapshots; los totales deben conciliar con el ingreso del libro.
- Existencias: `inventory_movements`; valoración: capas y asignaciones históricas restantes.
- Pendientes: `obligations` + `settlements`, conciliados con cuentas de control.
- Cobros por medio: `payments` + `payment_parts`, conciliados con caja. Nunca se agrupa el total de una venta una vez por cada pago parcial.
- Eventos: líneas y costos etiquetados/asignados, conciliados con los mismos documentos financieros.

Cada consulta retorna importe/valor, unidad, período, método, cobertura, exclusiones y advertencias pertinentes. Un DTO de reporte puede distinguir `complete`, `partial`, `estimated` y `unavailable`; una limitación no se representa con el número cero.

## 10. Definiciones mínimas para reportes fiables

| Indicador | Fuente y fórmula | Límite que debe exponerse |
| --- | --- | --- |
| Ventas brutas | Importe histórico antes de descuentos de ventas entregadas del período | No incluye borradores ni anticipos |
| Ventas netas | Ingreso propio bruto − descuentos − devoluciones; impuestos separados cuando apliquen | Sin precio histórico o tratamiento de impuestos suficiente no se afirma una cifra completa |
| Cobros recibidos | Entradas confirmadas por pagos; reembolsos y anticipos se separan por clase | Puede corresponder a ventas de otros períodos |
| CMV | Costos históricos de salidas de mercancía vendida − costos restituidos por devoluciones | Mostrar cobertura por unidades, líneas y ventas cuyo costo es completo |
| Costos directos de servicios | Consumos y gastos directos vinculados a prestaciones/eventos | Costo faltante o reparto estimado impide margen exacto |
| Ganancia bruta | Ventas netas − CMV − costos directos de servicios | Si el costo está incompleto, mostrar subtotal conocido y parte excluida |
| Resultado operativo | Ganancia bruta − gastos operativos reconocidos | No se confunde con saldo de caja; clases no capturadas se declaran |
| Compras de inventario | Adquisiciones recibidas del período, por documentos y capas | No se restan otra vez del resultado después del CMV |
| Flujo de dinero | Entradas − salidas de cuentas de dinero, separadas por operación, inversión/capital y transferencias | Transferencias se eliminan en consolidado; un anticipo entra en flujo sin ser venta |
| Valor de inventario | Suma de costo remanente de capas documentadas | Cantidades de costo desconocido se muestran aparte; precio de venta no es valor contable |
| Rotación a costo | CMV del período ÷ inventario promedio a costo del mismo período | Preferir promedio diario por movimientos; sin historia completa no fabricar denominador |
| Días de inventario | Días del período ÷ rotación, cuando ambos son válidos y rotación >0 | No interpretar stock sin ventas como cero días |
| Stock sin movimiento | Existencia actual + fecha de última venta confirmada; antigüedad adicional por capas | Fecha de última venta y edad del inventario no son equivalentes |
| Obligaciones por vencer | Saldos pendientes por contraparte, vencimiento y naturaleza | Un agregado histórico «deudas» sin detalle no permite inventar vencimientos |
| Fondos para nuevas compras | Dinero liquidado disponible − obligaciones dentro del horizonte − reservas definidas | Es una proyección condicionada; sin obligaciones/reservas completas se muestra saldo observado |
| Descuadre de caja | Conteo físico − saldo esperado del libro para cuenta/sesión | Aún no es un gasto ni ajuste hasta clasificarlo |

La cobertura no es solo un porcentaje de filas: se informan unidades, ventas monetarias afectadas y el importe de costo conocido cuando estén disponibles. No se extrapola automáticamente el margen de ventas completas a las incompletas.

## 11. Planificación y metas opcionales

Los escenarios se almacenan en tablas separadas de los registros reales y nunca generan asientos, cobros ni stock. Una meta define métrica, valor elegido por el usuario, moneda/unidad, período y criterio de seguimiento; puede no existir ninguna meta.

Un escenario conserva supuestos, procedencia de los datos base, horizonte y versión del modelo. Puede comparar ventas, costos variables, gastos fijos, necesidades de inventario y caja, pero etiqueta todos sus resultados como proyecciones.

Por ejemplo, el ingreso necesario para un beneficio elegido puede calcularse como `(beneficio_objetivo + gastos_fijos) / margen_de_contribución` únicamente si la distinción fijo/variable es válida y el margen de contribución es positivo. Un margen bruto histórico no se sustituye automáticamente por margen de contribución. Sin esos datos, el cálculo está no disponible o requiere supuestos explícitos.

La inversión adicional en inventario requiere demanda por producto, costos, stock, plazo de reposición y cobertura deseada. No se obtiene multiplicando ventas totales por una cifra fija inventada.

## 12. Entrega incremental del esquema

1. **Fundación transaccional:** perfil, comandos, documentos, cuentas, libro y restricciones; apertura vacía o saldos explícitos de prueba; pruebas de dinero, redondeo, idempotencia y reversa.
2. **Productos y compras:** catálogo, categorías, proveedores, capas y movimientos; conteos y ajustes trazables. Compras recibidas completas con costos documentados.
3. **Ventas y dinero:** ventas/líneas, obligaciones, pagos/partes/aplicaciones, cuentas y métodos; contado dividido y costo FIFO en una transacción.
4. **Operación pendiente:** cuentas abiertas persistidas, reservas, crédito, anticipos y devoluciones parciales, con sus pruebas de sobreaplicación.
5. **Gastos y control:** gastos clasificados, capital, transferencias, sesiones y conciliaciones de caja.
6. **Servicios y eventos:** cumplimiento, costos directos y asignaciones; anticipo y cumplimiento separados.
7. **Consultas y análisis:** vistas/read models reconstruibles y control de cobertura, con reconciliación entre detalle comercial y libro.
8. **Compatibilidad y planificación:** procedencia histórica, importación de respaldos solo después de validación; escenarios y objetivos independientes.

Las tablas futuras no obligan a incorporar ahora todos los formularios o políticas. Las migraciones internas de la nueva aplicación se verifican desde una base vacía y desde cada versión soportada, usando únicamente bases sintéticas independientes.

## 13. Pruebas importantes y criterios de aceptación

### Unitarias de dominio

- Conversión decimal exacta, límites, dinero negativo no permitido en comandos de cobro ordinario y desbordamiento de intermedios.
- Descuentos y redondeos: totales exactos y distribución determinista de restos.
- FIFO con varias capas; una capa cuyo costo no es divisible por su cantidad se agota con costo total exacto.
- Misma capa consumida en fragmentos diferentes produce el mismo costo acumulado para los mismos tramos.
- Cambio del precio/costo del catálogo no altera una venta confirmada.
- Devolución parcial sucesiva conserva costo histórico y no supera cantidad o importe original.
- Costo desconocido, cero documentado y estimado tienen resultados de calidad diferentes.
- Venta a crédito, pago parcial y anticipo aplicado no duplican ingresos.
- Transferencia y movimientos de capital no modifican resultado operativo.
- Compra, pago al proveedor y posterior venta reconocen costo una sola vez.
- Servicio/evento: anticipo no es ingreso; costo directo no vuelve a restarse como gasto operativo.

### Integración sobre SQLite aislado

- Error inyectado después de venta, stock, pago o asiento deja todas las tablas como antes del comando.
- Dos intentos por la última unidad: solo uno confirma; no queda venta sin salida ni stock negativo.
- Repetir una clave tras commit devuelve los mismos identificadores; contenido diferente con la misma clave se rechaza.
- Sobrepago, aplicación a obligación incompatible, devolución excesiva, doble reembolso y doble reversa se rechazan sin efectos parciales.
- Reinicio de aplicación conserva cuentas abiertas, reservas, entregas y pagos parciales.
- Claves foráneas activas, referencias inválidas rechazadas y catálogo utilizado protegido contra borrado.
- Comprobación de integridad referencial y conciliación de libro, inventario, capas, obligaciones y medios de pago.
- Cierre con diferencia de caja conserva conteo y discrepancia; solo una operación posterior aprobada registra ajuste.
- Fechas de venta, cobro, devolución y límite de día generan períodos correctos en la zona del negocio.
- Un reporte que incluye una reversa suma original y reversa una sola vez; los cambios actuales de catálogo no alteran comparaciones históricas.
- Base histórica sintética incompleta devuelve cobertura/limitaciones y nunca margen completo inventado.

### Consultas y controles de reconciliación

- Por asiento y consolidado: debe = haber.
- Por producto: saldo de movimientos = unidades remanentes de capas; reservas activas no superan existencia vendible y disponible = existencia vendible - reservas activas >= 0. Consumir una reserva respeta las reservas ajenas y cambia estado con la salida en la misma transacción.
- Por salida: cantidad y costo de asignaciones = movimiento y costo histórico de la línea cuando completo.
- Por venta: líneas = cabecera; ingreso comercial neto = ingreso del libro para idéntico período/clasificación.
- Por cuenta de dinero: pagos y movimientos específicos concilian con el libro, sin repetir ventas.
- Por cuenta de clientes/proveedores/anticipos: sumatoria de pendientes = cuenta de control.
- Por evento: costos asignados no superan sus fuentes, ni se contabilizan dos veces en el resultado consolidado.

Estas son pruebas propuestas. No se han ejecutado ni se afirma que el nuevo sistema ya las cumpla.

## 14. Fuentes técnicas verificadas

- [SQLite Is Transactional](https://www.sqlite.org/transactional.html): fundamenta la unidad atómica de cada operación.
- [SQLite Foreign Key Support](https://www.sqlite.org/foreignkeys.html): activación y comprobación explícita por conexión antes de transacciones.
- [Floating Point Numbers](https://www.sqlite.org/floatingpoint.html): diferencia entre enteros exactos y números REAL aproximados.
- [SQLite Backup API](https://www.sqlite.org/backup.html): ofrece un mecanismo para obtener una instantánea consistente; su disponibilidad concreta en la biblioteca Dart debe verificarse antes de implementar respaldos. La estrategia de migración/backup se documenta por separado.

El orden de reconocimiento y las clasificaciones descritas aquí son decisiones de diseño gerencial propuestas para este producto. Las fuentes técnicas no sustituyen la definición de políticas comerciales ni acreditan un régimen contable o tributario particular.
