# Proveedor en Catálogo — 0.9.1

La columna **Proveedor** sustituye a **Estado**. La tabla muestra **Producto, PVP, Unidades y Proveedor**, tanto en el catálogo operativo como en la consulta opcional de una copia.

El catálogo operativo usa las relaciones existentes de apertura y recepciones contabilizadas. Si un producto tiene varios proveedores históricos, muestra sus nombres distintos, ordenados y separados por comas. Esto identifica quiénes lo suministraron; no atribuye el stock restante a un proveedor concreto. Sin relación muestra **Sin proveedor**. La copia muestra el proveedor que trae cada producto. Los nombres largos tienen ancho limitado y un tooltip con el texto completo.

Los filtros de categoría, proveedor y búsqueda siguen combinándose. Los productos agotados permanecen ocultos. No se crean ni modifican productos, cantidades o asientos; se conserva el esquema v8 y el perfil activo.

## Verificación

Las 12 pruebas de widgets de catálogo operativo y de referencia aprobaron. Cubren encabezados, nombres múltiples, ausencia de proveedor, filtros combinados, agotados y ventana estrecha. Análisis estático limpio y formato sin cambios en los cuatro Dart modificados. Revisión independiente sin hallazgos accionables. La suite financiera general corresponde al corte anterior 0.9.0 y no se repitió para este ajuste de presentación.

El bundle Windows 0.9.1+13, sin defines de Sanctum, compiló en 56,76 s y quedó publicado en el acceso estable. Sus 17 archivos coinciden con el ZIP y la copia `dist/0.9.1/ValinorSanctum2`; el paquete excluye bases y perfiles privados. La apertura nativa confirmó versión, cuatro encabezados y ausencia de Estado y de errores de carga, mediante accesibilidad y teclado. La ventana quedó abierta en Catálogo para el propietario, sin registrar operaciones comerciales.

La evidencia de compilación y entrega está en [catalog-supplier-column.json](evidence/catalog-supplier-column.json).
