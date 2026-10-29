# Desarrollo 0.31.0: deudores visibles y total de cartera

El listado de Deudores al cierre en Reportes ocupa toda su altura: ya no tiene
un desplazamiento interno de 120 px. El comprobante crece con la cantidad de
personas para permitir capturarlo completo. La página conserva su desplazamiento
general cuando el contenido supera la pantalla; las transferencias conservan su
presentación anterior. No cambian el corte temporal ni los cálculos del reporte.

Deudores muestra arriba **Total deudas**, con el mismo estilo de los demás
totales. Suma los saldos de todas las personas, incluso las bloqueadas para fiado,
la cartera importada sin asignar y las cuentas por cobrar sin titular. Las deudas
ya asignadas no se vuelven a sumar desde su detalle. Buscar o seleccionar una
persona no cambia el total. Se actualiza al recargar y después de un abono.

## Entrega separada

- Versión portable de desarrollo: **0.31.0+47**; esquema 18 sin migración.
- Acceso: `Iniciar Valinor Sanctum Desarrollo 0.31.cmd`.
- Bundle: `dist/ValinorSanctum2-Desarrollo-0.31.0`.
- Base: `data/development/valinor/sanctum2.sqlite3`, mediante el selector existente.
- La carpeta estable, ZIP y acceso de desarrollo 0.30 se conservan.
- Producción 1.0.0 y su instalador se conservan. No se publica instalador productivo
  para este incremento. CI vuelve a generar únicamente el ZIP de desarrollo.

El empaquetador admite `-ArchiveOnly` para crear un ZIP sin sustituir la entrega
estable ni ejecutar su limpieza. La nueva carpeta de desarrollo usa ese ZIP.

## Verificaciones

29 pruebas de widgets aprobadas (Reportes, Deudores y entorno); incluyen 30
deudores sin scroll interno, ceros, cartera no asignada, filtrado y actualización
del total tras un abono. Dos renders sintéticos aprobados e inspeccionados:
comprobante con ocho deudores y pantalla con total de cartera. Análisis sin
incidencias. No se ejecutó una suite completa nueva ni se realizaron operaciones
comerciales sobre las bases del propietario.

Release Windows compilada y abierta: ventana **Valinor Sanctum - Desarrollo**,
versión nativa 0.31.0+47, proceso responde. ZIP y carpeta coinciden en 19 archivos
y no contienen datos privados. Se compararon por SHA256 41 archivos protegidos
de las entregas anteriores, todos intactos. Producción abierta por el propietario
continúa en su proceso. No se hizo inspección visual de la ventana nativa nueva;
la revisión visual corresponde a los renders de widgets. Formato: 201 archivos,
sin cambios. Evidencia en `docs/evidence/development-031.json`.
