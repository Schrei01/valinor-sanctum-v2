# Filtros del catálogo — 0.7.2

Catálogo muestra siempre productos. Al pulsar **Categoría** se despliega el listado de categorías; elegir **Comestible**, por ejemplo, muestra únicamente los productos de esa categoría. **Proveedor** permite filtrar los mismos productos por quien los suministró. Ambos criterios se combinan entre sí y con la búsqueda por nombre o SKU. **Todos los productos** limpia categorías, proveedor y búsqueda. Cada cambio vuelve a la primera página.

La tabla conserva Producto (con SKU y categoría), PVP, Unidades y Estado. Catálogo sigue siendo de consulta: no permite crear, editar, archivar ni reactivar productos y no muestra Acciones ni Valoración. Las altas e ingresos continúan en Compras. Se indica cuando ningún producto coincide.

La categoría procede del producto actual. La relación con proveedores se obtiene, en lectura, de las líneas de recepciones cuyos documentos y asientos están contabilizados. Se incluyen todos los proveedores históricos distintos que entregaron ese producto: si tuvo dos proveedores, aparece al seleccionar cualquiera. No se inventa una relación para productos sin recepciones. Las opciones archivadas siguen disponibles para consultar sus productos. Esto no equivale a identificar el proveedor del stock que queda actualmente.

No hay migración ni cambios en operaciones financieras, cantidades o datos guardados. Se conserva el esquema v7. El nuevo mapa del snapshot y sus listas son inmutables; no forma parte de las solicitudes durables de compra.

## Verificación ejecutada

- 41 pruebas enfocadas aprobadas: 3 de widgets, 3 de modelos de inventario, 19 del adaptador de inventario y 16 de ingresos de contado. Cubren filtros combinados, búsqueda, limpieza, ausencia de escrituras, proveedores históricos múltiples sin duplicados y protección del snapshot.
- Revisión independiente de la implementación sin hallazgos accionables.
- Análisis estático limpio y formato sin cambios en los ocho archivos Dart modificados.
- [Vista general](images/catalog-filters.png), [categorías desplegadas](images/catalog-category-options.png) y [filtros combinados](images/catalog-filtered.png), generadas desde widgets con datos sintéticos. Las dos últimas se inspeccionaron visualmente; no son capturas de la ventana nativa.
- No se repitió la suite general del corte 0.7.0. Sus 370 pruebas y tres omisiones corresponden a esa entrega.

La compilación Windows final 0.7.2+10, sin defines de Sanctum, terminó en 68,31 s. Se publicó el acceso estable y se verificaron los 17 archivos del ZIP contra él y contra `dist/0.7.2/ValinorSanctum2`. ZIP: 14.621.176 bytes; SHA256 `AF95E8A1AD9BA7B534BDD43370EC71CF80E410AE29DE9D183935F849B7A45FD5`.

La apertura nativa confirmó versión 0.7.2, selectores de categoría/proveedor, restablecimiento, búsqueda y las cuatro columnas, sin controles de modificación. La selección y combinación se verificaron en widgets. Se observó por accesibilidad y teclado; el ayudante no pudo resolver un índice de clic. Después detectó interacción del propietario: se detuvo la automatización y se dejó la ventana abierta. No se ingresaron datos comerciales mediante la automatización ni se atribuye a esta entrega una comparación completa de registros antes/después de esa sesión compartida.

La evidencia está en [catalog-filters.json](evidence/catalog-filters.json). Las demás limitaciones del MVP permanecen en el [informe 0.7.0](23-incremento-07.md).
