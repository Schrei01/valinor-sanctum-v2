# Bulk por valor vendido — Desarrollo 0.44.0

Ventas ofrece **Bulk Magic**, **Bulk Pokémon** y **Bulk Yu-Gi-Oh!** junto con los demás productos. Al elegir uno aparece **Valor vendido**, sin campo de cantidad de cartas ni precio predeterminado. El importe debe ser positivo. Se muestra con los separadores y decimales del perfil; Valinor conserva COP y cero decimales.

El bulk es otra línea de la misma cuenta. Una gaseosa de 3.000 y Bulk Magic por 5.000 suman una cuenta de 8.000, que se paga desde su selector habitual por Efectivo, Transferencia o Deudas, o mediante Dividir cuenta. No tiene un pago independiente. Si cambia el valor después de guardar una división, debe revisarse el reparto, igual que con cualquier cambio de consumo.

Hay un importe por tipo de bulk en cada cuenta. Si el cliente lleva más cartas del mismo juego, se aumenta ese valor. Las sugerencias no repiten un tipo ya elegido en otra línea; el almacenamiento también rechaza duplicados. Distintos tipos de bulk sí pueden coexistir en una cuenta. Cada cuenta y cada venta conservan su propio importe; editarlo no cambia el catálogo ni otras ventas.

Los tres artículos tienen categoría **Artículo**, disponibilidad ilimitada y PVP de catálogo cero, marcado como **Variable**. No figuran para reponer en Compras, consumir como premios o corregir cantidades. No descuentan inventario. Los productos físicos de la cuenta siguen descontando sus unidades normalmente.

En Reportes se guarda el importe efectivamente vendido, no el PVP cero del catálogo. Se agrupa por nombre y medio de pago como los demás ítems. La cantidad interna es una operación por tipo de bulk en la cuenta; los totales de cantidades del reporte representan operaciones de bulk, no cartas individuales. No se registra ni estima un costo de adquisición para las cartas.

## Persistencia y compatibilidad

La migración 25 amplía `catalog_services.kind` para distinguir `day_pass` de `bulk`. Conserva todas sus filas anteriores y el resto de las 76 tablas, sin cambiar migraciones publicadas ni agregar columnas a las ventas. Mantiene las protecciones de servicios sin inventario y exige una operación y valor positivo al confirmar un bulk.

Al entrar en Ventas se registran una sola vez los tres productos de configuración, su clasificación y el PVP inicial cero. Se reutiliza una categoría de artículos activa; si falta, se crea una. No se reactivan, renombran ni convierten productos antiguos por parecido de nombre. Los identificadores reservados distinguen estos productos de los físicos existentes.

La venta utiliza las solicitudes, comprobantes y pagos existentes: conserva su importe en el borrador, recupera confirmaciones preparadas al reabrir y no duplica dinero ni inventario al reintentar. Las ventas y compras pendientes anteriores siguen siendo compatibles. El arranque respalda la base de Desarrollo antes de migrar de 24 a 25. Producción 1.6.0 y sus datos de Documentos permanecen independientes.

La validación cubre cuenta mixta con los tres medios y reparto, deuda de la persona asociada, valores vacíos/cero y cantidades inválidas, cambio posterior a una división, importes distintos por cliente, reporte histórico con PVP cero, reapertura real de SQLite, solicitudes preparadas anteriores y protección de existencias. Las comprobaciones finales y la entrega se registran en [bulk-variable-price-044.json](evidence/bulk-variable-price-044.json).

Resultados locales: 122 pruebas de aplicación distintas aprobadas entre dos ejecuciones de 67 y 63, con ocho casos compartidos. Las tres pruebas de interfaz de bulk se repitieron después del ajuste de búsqueda por «pokemon» sin tilde. No se repitió la suite completa local: el CI completo debe aprobarse antes del merge. Dos renders sintéticos de 1120 y 400 píxeles inspeccionados, análisis sin incidencias, formato de 227 archivos sin cambios y compilación Windows Release correcta.

Portable publicada y abierta para revisión. ZIP y bundle estable coinciden en sus 19 archivos, sin datos privados. Se retiró la anterior de Desarrollo y la limpieza no dejó pendientes; 43 huellas de Producción, instalación y configuración permanecen iguales. El ensayo privado y la comprobación posterior al arranque preservaron todas las filas históricas de las 76 tablas. Se añadieron únicamente la migración y los tres productos de configuración, sus clasificaciones e historial inicial cero; en esta base no fue necesario crear otra cuenta de Ventas. Integridad y claves foráneas correctas. No se ingresaron ventas ni movimientos de dinero o inventario en la base activa. La revisión visual corresponde a renders de widgets, sin inspección visual nativa.

Se entrega Desarrollo portable 0.44.0+77 para revisión mediante PR. Conserva los incrementos de Reportes y Compras que todavía estaban pendientes de integrar al iniciar este trabajo. No integrar ni etiquetar hasta conformidad del propietario y CI completo aprobado; no se publica Producción en este incremento.
