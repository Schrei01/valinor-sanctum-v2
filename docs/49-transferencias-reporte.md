# Transferencias entre cuentas en Reportes — 0.20.1

El comprobante del rango incorpora una sección de transferencias entre cuentas, con origen → destino, cantidad de movimientos y suma de importes por ruta. La dirección contraria permanece en otra fila. El total trasladado cuenta cada operación una sola vez: no suma sus dos apuntes contables ni se añade a ventas o egresos.

Se agrupan las rutas para conservar un reporte compacto incluso en rangos con muchos movimientos. La tabla se adapta al ancho sin desplazamiento horizontal. Si no hay transferencias muestra cero y un estado vacío. El rango impreso y los selectores de fecha seguida de hora AM/PM mantienen el comportamiento existente, incluyendo todo el minuto final de Bogotá.

Se consultan las operaciones nativas de Tesorería confirmadas y las filas archivadas `transfermovements` de tipo transferencia. Los importes antiguos son los guardados en esos registros, sin estimaciones por saldos. Se incluyen las cuentas Caja, Nequi, Caja mayor y Deudas según figuran en el origen. Los nombres equivalentes Efectivo/Caja, Transferencia/Nequi y la capitalización de Caja Mayor se normalizan solo para agrupar la presentación; los registros no se modifican.

Las transferencias históricas reciben identificadores de lectura distintos de los documentos nativos. Un importe inválido permanece contado como información faltante y marca parcial el total; no se inventa un valor cero. Una fecha inválida impide generar el reporte y conserva el último resultado. No se recontabilizan transferencias antiguas ni se cambian saldos, inventario o deudas.

Esquema14, sin migración ni tablas o vistas persistentes nuevas. Los datos privados y las capturas sintéticas de verificación permanecen fuera de Git y del ZIP.

## Verificación

La primera ejecución aprobó 51 casos y encontró una medición de altura fallida en la interfaz, calculada con la fuente artificial del runner. La prueba se adaptó a las métricas Roboto reales de la aplicación y conserva el límite del comprobante base dentro de 1000×850. La ejecución posterior de interfaz/navegación/render aprobó 13 casos; la captura final adicional también pasó. Entre ejecuciones se aprobaron 51 casos distintos de aplicación y un render sintético; no se repitió la suite financiera completa.

Se verifican rutas con varias operaciones, aliases históricos, direcciones contrarias, importe contado una sola vez, Caja mayor/Deudas antiguas, mezcla de registros antiguos/nativos, límites de minuto/fracciones, importe faltante, cero movimientos, desbordamiento, conservación de ventas/egresos y datos intactos. Se inspeccionaron imágenes sintéticas amplia/estrecha y el análisis no tiene incidencias.

La copia privada contiene 469 transferencias archivadas y tres nativas. Siete rangos se contrastaron con una consulta y agrupación independientes: coinciden cantidades, rutas, importes por ruta y total. Las 63 tablas y el esquema del respaldo permanecen idénticos tras consultar. Datos, cifras y capturas de trabajo quedan privados.

## Entrega

Release Windows 0.20.1+32 compilado sin overrides y publicado cuando la app ya estaba cerrada. ZIP, acceso estable y copia versionada coinciden en sus 17 archivos privados excluidos. Las distribuciones anteriores se eliminaron según la retención autorizada.

El respaldo consistente tomado antes de actualizar se conservó y verificó en `backups/report-transfers-20261027`. La base activa coincide íntegramente con esa referencia en sus 63 tablas y esquema; integridad correcta, cero FK, esquema14 y escala0. Sin migración ni operaciones de prueba sobre datos del propietario. La app se deja cerrada; no se afirma un recorrido nativo nuevo. Abrir con `Iniciar Valinor Sanctum.cmd`. Ver [evidencia](evidence/report-transfers.json).
