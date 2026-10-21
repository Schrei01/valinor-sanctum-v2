# Requerimientos de la sección Eventos

Fecha del levantamiento: **21 de octubre de 2026**, America/Bogota.

Estado: consolidación del diseño conversado. La entrega vigente **0.14.0+21**, esquema v11, contiene la sección Eventos vacía y retira Evento de las opciones de nuevas Compras. La creación, el costeo y la venta de eventos descritos aquí todavía no están implementados.

Este documento distingue los acuerdos del propietario, las restricciones de integridad del sistema y las propuestas pendientes de decisión. Documentarlo no implica implementar ahora operaciones nuevas.

## 1. Objetivo y alcance acordado

Crear desde Eventos los conceptos que se venderán como inscripciones: pasadías, torneos, ligas y otros nombres que defina el propietario. Cada concepto aparecerá en Catálogo y estará disponible en Ventas.

**RF-01. Categoría única.** Todos los registros creados en esta sección tendrán tipo/categoría **Evento**, asignada automáticamente. No habrá selector de tipos Pasadía/Torneo/Liga; esa distinción se expresa en el nombre, por ejemplo «Liga Magic».

**RF-02. Origen de creación.** Se crean desde Eventos. Compras mantiene su función de ingreso de mercancía y continúa sin ofrecer Evento como categoría. No se reclasifican ni eliminan productos históricos automáticamente.

**RF-03. Disponibilidad comercial.** El evento tiene su propio artículo asociado en Catálogo, con categoría Evento, y se elige desde Ventas. La inscripción es un servicio sin existencias propias; la disponibilidad del evento no depende de un saldo físico de unidades. La exclusión de productos físicos agotados en Catálogo se conserva.

## 2. Datos de la ficha

| Dato | Regla acordada |
| --- | --- |
| Nombre | Identifica lo que aparecerá en Catálogo y Ventas. |
| Tipo/categoría | Evento, automático. |
| Mínimo de personas | Entero que admite 0 únicamente cuando no hay costo fijo ni productos utilizados. Es la base del cálculo del PU. |
| Costo fijo | Opcional; admite 0. |
| Cuenta del costo fijo | Caja o Nequi; se exige si el costo fijo es mayor que 0. |
| Productos utilizados | Lista opcional con varios productos del catálogo y sus cantidades. |
| PU | Costo calculado por inscripción. Se guarda en 0 cuando no corresponde un cálculo. |
| PVP | Precio de inscripción que introduce el propietario y que se usará como precio de venta. La política de PVP 0 está pendiente. |

**RF-04. Varios productos.** La ficha permite agregar más de un producto y especificar su cantidad. La selección sirve para premiación u otros usos del evento. Deben conservarse el detalle de productos, cantidades y costos utilizados.

**RF-05. Costo fijo y cuenta.** Al registrar un costo fijo positivo se elige de dónde sale el dinero: Caja o Nequi. Se conserva la convención vigente: Compras, Tesorería y este selector usan Nequi; en Ventas, el medio correspondiente se muestra como Transferencia.

## 3. Mínimo de personas, PU y PVP

**RF-06. Mínimo obligatorio cuando existen costos o productos.**

```text
requiere_mínimo = costo_fijo > 0 O hay_productos_seleccionados

si requiere_mínimo:
    mínimo_personas debe ser un entero mayor que 0
```

Seleccionar un producto exige el mínimo aunque ese producto tenga costo conocido de 0. Si falta el mínimo requerido, el evento no se crea ni se descuenta dinero o inventario.

**RF-07. Cálculo del PU.**

```text
costo_productos = costo de inventario de todas las cantidades utilizadas
costo_total_evento = costo_fijo + costo_productos
PU = costo_total_evento / mínimo_personas
```

Se calcula cuando hay costo fijo o productos seleccionados y existe un mínimo válido. Cuando no hay costo fijo ni productos, se guarda PU 0 y no se presenta una sugerencia de costo por inscripción. En ese caso el mínimo puede ser 0. Un costo real conocido de 0 debe conservarse como tal.

El criterio técnico de costeo es utilizar el costo de inventario de los productos consumidos conforme al costeo vigente de la app. El PVP de esos productos no se utiliza para calcular este costo. El redondeo del cociente se debe definir antes de implementar; los importes totales originales se conservan exactamente.

**RF-08. PVP independiente.** El propietario introduce el PVP de la inscripción. PU 0 no obliga a tener PVP 0. La aclaración PU/PVP sustituye la interpretación inicial que trataba el resultado del cálculo como el precio que se cobraría.

La fórmula **PVP − PU** permite analizar un margen estimado por inscripción, calculado con el mínimo previsto. El costo total registrado del evento se conserva para evaluar después el resultado con las ventas reales.

El mínimo se ha definido como base del cálculo. No se ha solicitado un cupo máximo ni una limitación de venta basada en ese número.

## 4. Efectos de crear un evento

**RF-09. Descuentos inmediatos al crear.** Al confirmar la creación:

1. Se guarda la ficha y su artículo de Catálogo.
2. Se descuentan del inventario las cantidades de los productos utilizados.
3. Se descuenta el costo fijo de Caja o Nequi, según la selección.
4. Se conservan el costo total, su detalle, el mínimo y el PU calculado de esa creación.

Elegir productos o escribir valores en un formulario aún sin confirmar no ejecuta estos descuentos.

**RF-10. Validación y atomicidad.** La creación y sus efectos se confirman juntos. Se validan cantidades, existencias, importes y saldo suficiente de la cuenta elegida. Si una validación o parte de la operación falla, no quedan un evento creado o descuentos parciales.

Como restricción técnica existente, las solicitudes que generan efectos comerciales deben ser recuperables e idempotentes: reintentar una creación no debe repetir el artículo, el evento, la salida de inventario o el gasto. Los hechos financieros e inventario confirmados conservan su trazabilidad e inmutabilidad.

## 5. Venta de inscripciones y reutilización de registros

**RF-11. Venta desde el flujo existente.** Las inscripciones se registran desde Ventas con los medios vigentes: Efectivo, Transferencia o Deudas. Se conservan las reglas actuales de cliente para Deudas y de cobros posteriores.

Vender una inscripción no vuelve a descontar los productos utilizados, el costo fijo ni el costo representado por el PU. Esos efectos ya ocurrieron al crear el evento.

**RF-12. Reutilizar las tablas de ventas.** Se aprovechan los registros existentes:

- `sales`: cabecera de la venta.
- `sale_lines`: artículo, cantidad, precio cobrado y total de cada línea.
- Los cobros y cuentas por cobrar continúan en sus estructuras vigentes.

Cada evento debe poder relacionarse de forma estable con su artículo de Catálogo. El enlace existente `sale_lines.product_id` permite localizar sus ventas; el detalle técnico de la ficha del evento se definirá al implementar.

No se requiere otra tabla que duplique las inscripciones vendidas. El número de inscripciones se obtiene sumando las cantidades de las líneas del evento, y el importe vendido sumando sus totales. Una misma venta puede contener otros eventos o productos: no debe atribuirse toda la cabecera `sales` a un solo evento.

En el esquema actual, `sale_lines.unit_price_minor` representa el **PVP efectivamente cobrado**, no el PU de costo de esta ficha. Los nombres, precios y costos históricos deben permanecer conservados aunque cambie una configuración posterior.

**RF-13. Datos para cuentas futuras.** Debe quedar información suficiente para calcular:

```text
margen estimado por inscripción = PVP − PU
resultado del evento = total vendido en sus inscripciones − costo total registrado del evento
```

El resultado usa sus costos originales una sola vez. No se ha pedido todavía construir una pantalla nueva de reportes ni un padrón nominal de asistentes.

## 6. Disponibilidad y desactivación

**RF-14. Necesidad de retirar eventos.** El propietario planteó una acción **Desactivar** en Catálogo para que los eventos no permanezcan disponibles indefinidamente. La consulta original mencionó los que no tuvieran cálculo de PU.

Se propuso extender la acción a todos los eventos, conservar el historial y separar su disponibilidad de su precio. También se propusieron un filtro de inactivos y la reactivación. **El alcance de esas propuestas requiere confirmación**; no se deben tratar como una autorización ya cerrada.

La desactivación no debe borrar hechos comerciales ni representar por sí sola una devolución de los productos o del dinero utilizados al crear el evento.

## 7. Decisiones pendientes

| ID | Decisión pendiente | Propuesta discutida o implicación |
| --- | --- | --- |
| P-01 | Alcance de Desactivar y de los inactivos | Aplicarlo a todos los eventos; filtro de inactivos y reactivación. Falta confirmar. |
| P-02 | Edición después de crear | Se propuso permitir cambiar PVP y mantener protegidos los costos confirmados. Definir también nombre y mínimo. Los hechos ya contabilizados no se reescriben. |
| P-03 | Correcciones y cancelaciones | Definir cómo registrar un error y cualquier devolución real de dinero o productos. Desactivar no implica reintegrarlos. |
| P-04 | PVP 0 | Confirmar si se permiten inscripciones gratuitas y cómo registrarlas. La venta actual exige un total positivo, por lo que un evento gratuito necesita una decisión de flujo. |
| P-05 | Redondeo del PU | Definir el redondeo a la precisión del perfil cuando la división no sea exacta. Conservar el costo total original y evitar cálculos monetarios en `double`. |
| P-06 | Nuevas realizaciones | Se propuso crear un evento distinto para otra realización con nuevos costos, y que reactivar no repita descuentos. Falta confirmar el tratamiento de eventos recurrentes. |
| P-07 | Informes de cobrado/deuda por evento | Se propusieron como información futura. Si hay ventas mixtas y abonos posteriores, definir la imputación de esos abonos antes de atribuirlos a un evento concreto. |

Estas decisiones no impiden documentar el alcance confirmado. Deben resolverse según afecten la implementación que se autorice.

## 8. Criterios de aceptación del alcance acordado

1. Crear «Liga Magic» asigna Evento automáticamente, sin selector de subtipos, y lo vincula con Catálogo y Ventas.
2. Con costo fijo 0 y sin productos se admite mínimo 0, se guarda PU 0 y el PVP se introduce por separado.
3. Con costo fijo positivo, mínimo 0 impide crear y conserva íntegros el dinero y las existencias.
4. Con al menos un producto, mínimo 0 impide crear, incluso si el producto tiene costo conocido de 0.
5. Con mínimo válido, el PU se obtiene del costo fijo y del costo de todas las cantidades seleccionadas.
6. Un costo fijo positivo requiere elegir Caja o Nequi y disponer de saldo suficiente.
7. Se pueden utilizar varios productos; una cantidad sin existencias suficientes impide confirmar toda la operación.
8. Crear descuenta todos los productos y el costo fijo una sola vez, conservando el detalle de costos.
9. Un reintento recupera el resultado de la misma creación sin repetir efectos.
10. El evento aparece en Catálogo aunque no tenga existencias físicas propias; los productos físicos agotados mantienen su tratamiento actual.
11. Vender varias inscripciones conserva cantidades y PVP real en `sale_lines` sin volver a consumir premios ni descontar el costo fijo.
12. Una venta con inscripciones y otros artículos permite obtener los importes del evento desde sus líneas, sin duplicar registros de inscripción ni sumar importes ajenos.
13. Compras mantiene Evento fuera de sus opciones nuevas y se conservan las categorías, productos e historia anteriores.

## 9. Referencias y límites

- [Estado entregado de Eventos 0.14.0](36-eventos.md): sección vacía y categoría retirada de nuevas Compras.
- [Nombres de pago vigentes](35-nombres-pago-ventas.md): Nequi en Compras/Tesorería y Transferencia en Ventas.
- [Esquema actual de ventas y líneas](../lib/core/infrastructure/database/schema.dart): la estructura comercial se reutiliza y cualquier ampliación futura debe preservar las migraciones publicadas y la historia.

Este levantamiento no modifica el programa, el esquema, perfiles, saldos o inventario. No incluye torneos con rondas, posiciones, emparejamientos, cupos, reservas, calendario o gestión nominal de jugadores, porque no se han solicitado.

## 10. Implementación posterior autorizada

El propietario solicitó implementar la sección y confirmó después **Desactivar a todos los eventos**. La implementación 0.15.0 y sus decisiones técnicas se describen en [Eventos operativos](38-eventos-operativos.md): PU redondeado con mitades hacia arriba y PVP positivo en el flujo actual. La edición, reactivación, reversas, gratuidad, recurrencia automática e informes adicionales continúan fuera de este incremento. Los apartados anteriores conservan el levantamiento original y sus pendientes a esa fecha.
