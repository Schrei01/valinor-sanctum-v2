# Existencias en el selector de Ventas — 0.26.1

Las sugerencias de Producto muestran las unidades del inventario junto con el SKU, cuando existe, y conservan el PVP. Solo ofrecen productos físicos activos con cantidad mayor que cero. Los servicios ilimitados y eventos activos permanecen disponibles, identificados como **Ilimitado**.

La cantidad procede de las mismas posiciones de inventario que usa Catálogo, sin descontar borradores ni fabricar reservas. Se retiró el límite de 25 coincidencias: la lista completa se recorre con desplazamiento y construcción de filas a demanda.

Al actualizar los datos se eliminan opciones agotadas de una lista ya abierta y se comprueba nuevamente la disponibilidad antes de aceptar una selección. Se preservan los productos en la información del borrador para poder identificar y corregir líneas anteriores; no se borran selecciones guardadas ni historial. Los productos archivados siguen sin ofrecerse para nuevas ventas. Las validaciones transaccionales de stock y la venta mixta no cambian.

Si no hay artículos disponibles, Ventas indica ingresar o reponer mercancía desde Compras. La creación de productos permanece en ese módulo.

## Verificación y entrega

- 27 pruebas enfocadas aprobadas: sugerencias con unidades, búsqueda por SKU, agotados, servicios/eventos ilimitados, lista de más de 25 coincidencias, actualización de opciones, conservación de borradores y venta/ajuste de stock.
- Prueba de SQLite: vender las últimas diez unidades deja el producto fuera de las opciones, conserva el historial y reponer dos unidades vuelve a ofrecerlo con cantidad dos.
- Dos pruebas adicionales de render aprobadas, con imágenes inspeccionadas a 1366 y 400 px de ancho. Se muestran unidades, SKU y PVP sin desbordamientos.
- Comparación de los lectores reales de Catálogo y Ventas sobre una copia privada consistente: mismas cantidades e identidad de los productos disponibles, agotados excluidos e ilimitados conservados. Todas las filas y el esquema de la copia permanecen idénticos antes/después de consultar.
- Análisis limpio y formato de 190 archivos verificado, sin cambios pendientes.

- Release Windows 0.26.1+41 sin overrides publicado, con pie 0.26.1. ZIP, estable y copia versionada coinciden en 18 archivos sin datos privados; distribuciones anteriores limpiadas.
- Respaldo verificado en `backups/sale-availability-20261027`: esquema 16, 68 tablas, todas las filas y definiciones activas idénticas antes/después de publicar y abrir. Integridad correcta y cero FK. La comprobación tras abrir se repitió al terminar la carga inicial por un bloqueo transitorio de SQLite; el resultado final confirmó conservación completa.
- App abierta y respondiendo; accesibilidad nativa observó Ventas y Versión 0.26.1. No se abrieron menús ni se registraron operaciones sobre la activa. Las imágenes del selector corresponden a datos sintéticos.

Operaciones de prueba y renders con datos sintéticos; la comparación de lectores se hizo sobre una copia privada. Sin operaciones de prueba sobre la base activa. Evidencia sanitizada en `docs/evidence/sale-availability.json`. CI del commit nuevo se comprueba después del push; las verificaciones anteriores son locales.
