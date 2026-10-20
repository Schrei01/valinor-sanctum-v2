# Catálogo de consulta — 0.7.1

Por solicitud del propietario, Catálogo pasa a ser únicamente una vista de consulta. Se retiraron las altas, formularios de edición, botones de archivado/reactivación y columnas Acciones y Valoración. Productos muestra Producto (con SKU y categoría), PVP, Unidades y Estado. El estado anterior permanece como información, sin acciones para modificarlo.

Productos, Categorías y Proveedores seleccionan el listado visible. Cada listado conserva búsqueda y paginación; cambiar de listado limpia la búsqueda y vuelve a la primera página. Los ingresos y altas de productos/proveedores siguen en Compras.

El cambio se limita a presentación. No modifica adaptadores, operaciones monetarias, existencias ni datos guardados; no añade migraciones y conserva esquema v7. Se eliminaron también los diálogos privados que ya no tenían acceso desde la pantalla.

Archivos funcionales: `catalog_page.dart`, etiqueta de versión en `sanctum_app.dart`, `pubspec.yaml` e instrucciones del paquete. Se actualizó la prueba de edición anterior para verificar filtros, búsqueda por SKU/nombre, ausencia de controles de modificación y cero llamadas de guardado. Las otras dos regresiones comprueban perfil requerido y ventana estrecha.

## Verificación ejecutada

- Tres pruebas de `test/widgets/inventory_test.dart` aprobadas.
- Análisis estático sin incidencias y formato limpio en los tres archivos Dart modificados.
- [Vista previa del catálogo](images/catalog-readonly.png) generada desde widgets con datos sintéticos e inspeccionada visualmente. No es una captura de la ventana nativa.
- No se repitió la suite financiera general: no se modificó su implementación. El corte 0.7.0 conserva su evidencia de 370 pruebas y tres omitidas.

La compilación final de Windows 0.7.1+9, sin defines de Sanctum, terminó en 62,52 s.

Se publicó en el acceso estable después de que el propietario cerrara la versión anterior. Se verificaron los 17 archivos contra el ZIP y la copia `dist/0.7.1/ValinorSanctum2`. ZIP: 14.620.663 bytes; SHA256 `9004E7E770AC603D3068007F603332D8668DD88C219D3AEC616014558A8EADCA`.

La apertura nativa mostró versión 0.7.1, los tres filtros, PVP/Unidades/Estado y ausencia de Valoración, Acciones y controles de alta/edición/archivado. Se observó por accesibilidad y teclado, sin ingresar datos, y se cerró la ventana propia. Una comparación de solo lectura de las 42 tablas antes y después confirmó todos los registros exactamente iguales. El hash del ZIP no cambió. No se añadió migración ni se abrió el POS original.

Evidencia completa: [catalog-readonly.json](evidence/catalog-readonly.json).

Las demás limitaciones del MVP permanecen en el [informe 0.7.0](23-incremento-07.md).
