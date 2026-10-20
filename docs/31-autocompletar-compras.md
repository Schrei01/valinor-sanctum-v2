# Autocompletar productos en Compras — 0.11.1

Al buscar un producto por nombre o SKU y seleccionarlo en Compras, el formulario completa su SKU, categoría y PVP actuales, junto con el proveedor y precio de compra unitario conocidos. Esto también funciona con los productos incorporados mediante la apertura de inventario, incluidos los agotados que se desean reponer.

Los campos siguen siendo editables. La cantidad corresponde a las unidades que ingresan en esta compra: no se sustituye por las existencias ni por la cantidad de una compra anterior. La cuenta elegida para pagar también se conserva.

## Procedencia de los valores

El catálogo aporta SKU, categoría y PVP. Para proveedor y costo se consulta el último ingreso contabilizado del producto, incluyendo compras anteriores y apertura de inventario. Se exige documento y asiento contabilizados. Los dos valores proceden del mismo ingreso; no se combinan proveedores antiguos con costos recientes ni se utiliza el costo medio del inventario.

Las fechas se comparan como instantes, con desempate determinista por origen e identificadores. Se utiliza el nombre vigente del proveedor por su ID, siempre que siga activo. Si no existe un proveedor utilizable, su campo queda vacío. Cuando un recibo antiguo solo registra costo total, se sugiere costo unitario únicamente si la división por cantidad es exacta a la escala monetaria del perfil.

Un costo conocido de cero se muestra como cero; uno desconocido queda vacío. Se mantiene la validación existente de precio de compra positivo para registrar una compra pagada.

## Edición y recuperación

Elegir otro producto reemplaza los datos completados. Si ese producto no tiene proveedor o costo conocido, se limpian esos campos para evitar reutilizar los del anterior. Cambiar el nombre para crear un producto nuevo limpia también SKU, categoría y PVP asociados a la identidad anterior.

Actualizar la pantalla no sobrescribe los cambios manuales del formulario. Las solicitudes preparadas pendientes conservan sus valores guardados y su recuperación previa; los datos sugeridos no sustituyen una operación ya preparada.

## Verificación

- **50 pruebas aprobadas**: nueve de widgets, diez de controlador y 31 de almacenamiento/esquema de Compras. Incluyen cuatro casos nuevos de datos y un caso nuevo de cambio de producto, además de ampliar la cobertura de edición y recuperación.
- Se verificaron apertura con agotados/costo cero/sin proveedor, reposición posterior, proveedor renombrado o inactivo, costo no divisible y mapa inmutable. Los widgets verifican datos completados, edición de costo/PVP, recarga, limpieza de campos y conservación de cantidad/pago.
- Análisis sin incidencias y los seis archivos Dart modificados con formato limpio. Revisión independiente sin hallazgos pendientes.
- Esquema v9 sin cambios ni migraciones. Las pruebas usan datos sintéticos; esta mejora no requiere importar inventario, reinicializar saldos ni registrar una compra en el perfil del propietario.

El bundle Windows final sin configuraciones de prueba se compiló y publicó en el acceso habitual. Se verificaron los 17 archivos entre ZIP, ruta estable y copia versionada, sin bases ni snapshots privados. La comprobación nativa mediante accesibilidad y teclado confirmó selección de producto, proveedor/costo/PVP/categoría completados y cantidad de ingreso conservada en uno. No se envió el formulario ni se registró una compra. La captura de pantalla no estuvo disponible; esta comprobación fue por accesibilidad. Se dejó la ventana abierta en Compras para el propietario.

La evidencia de compilación y entrega local se registra en [purchase-prefill.json](evidence/purchase-prefill.json).
