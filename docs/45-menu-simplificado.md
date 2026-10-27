# Menú simplificado — 0.18.1

El propietario pidió retirar Inicio y Sistema y usar 0 decimales por defecto. Ambas páginas y sus entradas se eliminan. El menú conserva Catálogo, Compras, Ventas, Deudores, Tesorería, Eventos y Reportes, tanto en el lateral como en ventanas estrechas. La aplicación abre directamente en Ventas.

Los espacios nuevos se configuran solo con el nombre del negocio, antes de mostrar el menú. COP, escala0 y Bogotá quedan fijos en el alta, sin selector de decimales. `BusinessProfile` también usa escala0 como valor predeterminado. La creación mediante `WorkspaceController` no acepta otra escala.

El perfil activo ya tenía escala0. Se conserva la escala almacenada de perfiles anteriores: no se reinterpreta un entero monetario como si tuviera otra unidad. No hay migración de esquema, reseteo, reimportación ni cambios en inventario, saldos o historial. Las comprobaciones automáticas de almacenamiento al abrir se mantienen, aunque ya no exista la pantalla de diagnóstico.

La navegación conserva los formularios y cuentas pendientes en el `IndexedStack`; los módulos se actualizan al entrar con sus índices adaptados al nuevo menú.

## Verificación y entrega

La primera ejecución enfocada aprobó 26 casos de alta, controlador, arranque, navegación, eventos, tesorería, reportes y protección de cuentas al cerrar. La revisión de todos los widgets más el controlador y almacenamiento de espacios aprobó 127 casos y detectó una expectativa antigua: buscaba el menú antes de configurar el espacio. Se adaptó al nuevo flujo inicial; la verificación final aprobó cuatro casos (tres de catálogo y una captura sintética). Entre ejecuciones quedaron aprobados 128 casos distintos de aplicación; no se repitió la suite financiera completa ni se presenta la ejecución amplia como íntegramente aprobada.

Se inspeccionaron imágenes sintéticas de Ventas al abrir en ventanas amplia y estrecha, con las siete entradas y sin Inicio/Sistema. Las pruebas verifican alta a escala0, arranque directo, ausencia de opciones retiradas, persistencia de entradas sin confirmar al navegar y guardado pendiente al cerrar. El análisis está limpio.

Formato limpio de 11 archivos Dart. Compilación Windows release 0.18.1+28 sin overrides publicada en el acceso estable. ZIP, copia versionada y entrega estable coinciden en sus 17 archivos sin datos privados; se eliminaron las distribuciones anteriores según la política autorizada.

Se creó un respaldo consistente antes de publicar y se compararon después las 63 tablas y el esquema: todos los registros permanecen idénticos, integridad correcta, cero FK y perfil activo en escala0. Sin migración ni operaciones comerciales de prueba. La app estaba cerrada y se deja cerrada; no se afirma un recorrido nativo nuevo. Ver [evidencia](evidence/menu-simplification.json).
