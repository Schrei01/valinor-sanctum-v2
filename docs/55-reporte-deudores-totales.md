# Deudores al cierre y presentación de totales — 0.24.0

El reporte agrega el saldo de cada deudor y el total pendiente a la fecha y hora final seleccionadas. Es una existencia al cierre, que incluye deudas anteriores al inicio; la fila Deudas de Ventas sigue mostrando únicamente lo vendido a crédito durante el período. Se incluyen personas bloqueadas para fiar si conservan saldo y se omiten saldos cero.

La consulta reconstruye las cuentas por cobrar y resta solo los abonos contabilizados antes del fin exclusivo del rango. La titularidad de ventas y aperturas empieza en la fecha de su documento; para asignaciones posteriores de ventas históricas se usa la fecha de negocio del comando de asignación, no su hora técnica de guardado. Un corte anterior no recibe retroactivamente esas asignaciones. El importe sin titular aparece como **Sin asignar** y concilia contra el total del libro o el saldo histórico convertido. La falta de cobertura sigue siendo **Sin información**.

Todo el reporte se obtiene en la misma transacción de lectura. No se agregan tablas, migraciones, ventas, cobros ni asignaciones al perfil activo.

## Interfaz

- Deudores: separación de 16 px entre campos y acciones del abono, con alineación central y espacio al envolver los botones.
- Reportes: encabezado y filas compactos; en escritorio amplio, Saldos, Ventas y Egresos ocupan tres columnas. Deudores y Transferencias comparten la fila inferior. Las secciones se apilan al reducir la ventana. Ítems vendidos conserva su paginación de 10.
- Las explicaciones, cobertura histórica y advertencias de importes parciales quedan al final, después de los ítems, bajo Notas del reporte.
- `FinancialTotal` comparte fondo, color de texto, importe de 17 px en negrita y cifras tabulares para los totales de Compras, Ventas, Catálogo, Deudores, Tesorería, Eventos y Reportes. Las ayudas de Compras usan un tamaño secundario de 12 px; se conservan los campos y su orden.

El resumen se compacta para escritorio sin eliminar nombres ni rutas. Las listas de deudores y transferencias tienen desplazamiento local cuando superan 120 px; sus totales permanecen fuera de ese desplazamiento. En ventanas pequeñas la página conserva desplazamiento vertical.

## Verificación y entrega

- Ejecución general: 738 pruebas aprobadas, tres omitidas por enlaces de Windows y dos fallos de interfaz durante el ajuste. Se actualizaron las expectativas del total y se repitió la distribución final.
- Repetición final de las pantallas afectadas y almacenamiento de Reportes: **91 pruebas aprobadas**, incluyendo tres casos de render sintético. La prueba adicional de 30 deudores y seis rutas comprueba desplazamiento local, altura acotada y totales visibles.
- Nueve imágenes sintéticas inspeccionadas, con fuentes reales, para Compras, Deudores y Reportes a anchos 1366, 900 y 620, alto 768. El resumen amplio cabe completo; las ventanas estrechas mantienen desplazamiento vertical.
- Consulta de dos cortes sobre una copia privada consistente de la base propia: desglose conciliado con el total; esquema y todas las filas de la copia idénticos antes/después. Sin operaciones de prueba en la activa.

- Análisis final sin incidencias y formato de `lib`, `test` y `tool` verificado: 187 archivos, cero cambios.

- Release Windows 0.24.0+38 sin overrides publicado en el acceso estable, con pie 0.24.0. ZIP, estable y copia versionada coinciden en 17 archivos, sin datos privados; distribuciones anteriores limpiadas.
- Respaldo consistente verificado en `backups/report-debt-layout-20261027`. Esquema 16, 68 tablas: todas las filas y definiciones activas idénticas antes/después de publicar y de abrir la app; integridad correcta y cero FK.
- App abierta y respondiendo al terminar. La accesibilidad mostró el menú y Versión 0.24.0. No se completó navegación nativa: el clic devolvió `element 25 is not available in cached app state`. La validación visual del formulario/reporte corresponde a los renders sintéticos y widgets, sin operaciones de negocio en la activa.

Evidencia sanitizada en `docs/evidence/report-debt-layout.json`. Bases, respaldos, capturas sintéticas y scripts de comprobación permanecen privados. La ejecución remota de este commit se crea al subirlo; comprobar su resultado en Windows checks, sin atribuir al CI las comprobaciones locales.
