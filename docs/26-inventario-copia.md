# Consulta de inventario de una copia — 0.8.0

El propietario pidió visualizar el inventario de `C:\proyectos\valinor - copia.db`, una copia independiente de su base de producción. Se inspeccionó con SQLite en modo estrictamente de lectura. Su tabla `products` contiene nombre, cantidad, PVP (`price`), precio de compra (`purchasePrice`) y lote; no contiene categoría, proveedor ni SKU.

Se conserva la tabla completa, incluidos los registros agotados. No se agrupan nombres ni se interpretan lotes como SKU. Las cantidades y precios se conservan; el precio de compra se retiene en el snapshot, sin crear una valoración FIFO de la app nueva. Las cifras del corte real y su conciliación quedan en los archivos locales privados.

## Uso en Catálogo

Cuando hay un snapshot local válido, **Inventario de la copia** aparece seleccionado al abrir Catálogo. Muestra productos, PVP en COP, unidades y estado de existencias; el lote aparece debajo del nombre. Permite buscar por nombre o lote y paginar. Indica que es una consulta de la copia y la fecha en que se extrajo. La copia no incluye categorías ni proveedores: no se asignan valores inventados para esos filtros.

El selector de origen permite volver a **Catálogo de esta app**, que conserva sus filtros de categoría/proveedor y los productos ingresados desde Compras. Las fuentes se muestran por separado. Si no hay snapshot, se mantiene el catálogo habitual. Un archivo inválido muestra un aviso con reintento, sin convertir el error en un inventario vacío.

Esta consulta no habilita sus productos en Ventas ni genera compras, pagos, saldos iniciales, deudas, lotes FIFO o asientos. No cambia la escala monetaria del perfil de la app ni migra su esquema v7. No es sincronización: reemplazar la copia de origen no actualiza el snapshot ya extraído.

## Extracción local

`tool/export_reference_inventory.dart` lee únicamente `products` de una base abierta con `readOnly` y `query_only`. Convierte los importes desde su representación decimal de SQLite a enteros con dos decimales, sin cálculos financieros en `double` ni redondeo silencioso. Rechaza datos incompatibles. El JSON guarda IDs, nombres, cantidades, PVP, precio de compra y lotes, además de metadatos de origen y extracción; no guarda ventas, clientes ni movimientos de caja.

El archivo de consulta de este perfil es `data/development/development/reference-inventory.json`, fuera de Git y de los ZIP de entrega. La app lee ese JSON; no abre la base de origen. El extractor no sobrescribe un snapshot existente sin `--replace`. La huella de la fuente se calcula antes y se comprueba después; filas, cantidades, precios y lotes se concilian contra el resultado. Las instrucciones siguientes se ejecutan dentro del repositorio nuevo:

```powershell
$copyPath = 'C:\proyectos\valinor - copia.db'
$copyHash = (Get-FileHash -LiteralPath $copyPath -Algorithm SHA256).Hash
./scripts/dart.ps1 run tool/export_reference_inventory.dart --source $copyPath --output 'C:\proyectos\valinor_sanctum_2\data\development\development\reference-inventory.json' --source-sha256 $copyHash
if ((Get-FileHash -LiteralPath $copyPath -Algorithm SHA256).Hash -ne $copyHash) { throw 'La fuente cambió durante la extracción: no usar el corte.' }
```

## Verificación

Se aprobaron 50 pruebas distintas entre modelos/lector/extractor, Catálogo, espacio de trabajo, Ventas y Compras. Una aserción nueva de búsqueda coincidía tanto con el campo editable como con la celda: se acotó a la tabla y se repitieron las siete pruebas nuevas de interfaz, todas aprobadas. Las otras 43 comprobaciones ya habían pasado. Se verificó que la inyección desde WorkspaceSession llega a Catálogo y no agrega los productos de referencia a Ventas. No se repitió la suite financiera general.

El análisis estático quedó limpio y los once archivos Dart modificados quedaron formateados. Una revisión independiente no encontró fallos accionables. La extracción real se concilió campo a campo y la huella de la fuente se mantuvo igual antes/después. El archivo privado está ignorado por Git; el paquete y el publicador rechazan snapshots fuera de las rutas runtime excluidas.

La compilación Windows 0.8.0+11 final, sin defines de Sanctum, terminó en 55,75 s. Se publicó el acceso estable y se verificaron los 17 archivos contra el ZIP y la copia `dist/0.8.0/ValinorSanctum2`. El ZIP tiene 14.628.547 bytes y SHA256 `0A98D3631A0466D6297261B1837F07D7B2D025B902206AEFE6C36A7D3C246527`; no contiene bases ni el snapshot privado.

La apertura nativa confirmó versión, fuente de copia seleccionada, totales coincidentes con la conciliación privada, etiquetas de lote, PVP/Unidades/Estado y aviso de consulta. Se inspeccionó mediante accesibilidad y teclado, sin capturar ni publicar nombres o precios reales. Las 42 tablas de la base propia de 2.0 conservaron todos sus registros al comparar en lectura antes y después de abrir Catálogo. Se dejó la ventana abierta en el inventario para el propietario; la comparación corresponde al momento de esa verificación, no a modificaciones posteriores que pueda realizar el usuario.

La evidencia de pruebas y entrega se registra en [reference-inventory.json](evidence/reference-inventory.json). Los datos reales y las huellas de su contenido no se publican en esa evidencia. El POS original no se ejecuta ni se modifica.
