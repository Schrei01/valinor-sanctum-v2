# Eventos y categorías de Compras — 0.14.0

**Compras** deja de ofrecer **Evento** en el selector de categoría. Al seleccionar un producto histórico de esa categoría, el formulario requiere elegir una categoría disponible antes de registrar un nuevo ingreso. Seleccionarlo no reclasifica ni modifica el producto automáticamente.

**Eventos** aparece en el menú, después de Tesorería y antes de Sistema. Su área de contenido está vacía: no tiene formularios, listas, mensajes de ejemplo, controladores ni operaciones propias. La navegación funciona tanto en escritorio como en ventana estrecha.

Se conservan las categorías, productos, historial y solicitudes anteriores. Las confirmaciones ya preparadas mantienen su recuperación. No hay migración ni cambios financieros: el esquema continúa en v11. El rótulo de versión del menú se actualiza a 0.14.0.

## Verificación y entrega

- **27 pruebas enfocadas aprobadas**, sin fallos: Compras, controlador, espacio de trabajo y navegación de Ventas/Tesorería. Las pruebas existentes comprueban que Evento no se ofrece, que un producto histórico no se reclasifica al seleccionarlo y que Eventos se abre vacío en escritorio y a 400px. Sistema sigue accesible. No se repitió la suite completa.
- Análisis limpio, cuatro Dart modificados con formato limpio y revisión independiente sin hallazgos pendientes.
- Al abrir el bundle final se compararon las **49 tablas** propias con el estado guardado de la app cerrada: todos los registros, saldos e inventario idénticos, esquema v11 sin migración, integridad correcta y cero violaciones FK.
- Bundle Windows final **0.14.0+21** sin configuraciones de prueba publicado en **Iniciar Valinor Sanctum.cmd**, ZIP y copia versionada 0.14.0. Sus 17 archivos extraídos del ZIP coinciden por SHA256 con la ruta estable y no contienen datos privados.
- En Windows se observaron **Eventos** en la navegación y el rótulo **Versión 0.14.0** mediante accesibilidad. El contenido vacío y el formulario se verificaron en widgets. No se capturaron imágenes ni se enviaron operaciones de prueba; la ventana se dejó abierta para el propietario.

Evidencia: [events-placeholder.json](evidence/events-placeholder.json).
