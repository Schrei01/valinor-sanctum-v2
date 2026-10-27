# Reportes básicos — 0.17.2

Desde 0.18.0, una base convertida también ofrece los saldos anteriores a su apertura mediante el historial incorporado. Se mantiene esta misma pantalla básica y el flujo AM/PM. Ver [conversión de la base](44-conversion-base.md).

El propietario acota Reportes a los saldos iniciales y finales de Caja y Nequi. La pantalla muestra dos selectores y dos tarjetas con esos cuatro valores. Las gráficas, listados y otros indicadores se retomarán después; los hechos históricos y el modelo de consulta se conservan.

## Uso

1. Pulsa **Fecha y hora inicial**. Elige la fecha y pulsa **Aceptar**; a continuación elige la hora y AM o PM y acepta.
2. Repite con **Fecha y hora final**.
3. Pulsa **Generar reporte**. Las tarjetas muestran sus fechas/horas consultadas y los valores de Caja y Nequi correspondientes.

El formato de selección y presentación es de 12 horas con AM/PM, independientemente de la preferencia de 24 horas del equipo. 12:00 AM es medianoche y 12:00 PM es mediodía. Cancelar la fecha o la hora conserva la selección completa anterior. Un final anterior al inicio no sustituye el último reporte válido.

Los momentos corresponden a Bogotá. Se conserva la precisión por minuto acordada: inicial al comenzar el minuto seleccionado y final al terminar todo el minuto final. Los cálculos siguen usando los hechos confirmados del libro financiero, incluyendo transferencias y aperturas, sin precios actuales ni límites de últimos movimientos. Si falta el historial anterior a una apertura importada se muestra **Sin información**, nunca un cero inventado. Los saldos de Caja mayor y las métricas comerciales no aparecen en esta pantalla.

El esquema sigue en v13, sin migraciones ni cambios de datos. La consulta se hace en una transacción coherente de lectura.

## Validación y entrega

Pasaron 30 pruebas enfocadas de aplicación: 16 de integración de datos, siete del controlador, seis de la pantalla básica y una de navegación. Se verificaron los cuatro saldos, límites de tiempo y fracciones, flujo de fecha a hora, selección AM/PM incluso con un equipo configurado en 24 horas, conversión de medianoche y mediodía, cancelación de cualquiera de los diálogos, rango invertido, conservación del último reporte al fallar y pantalla estrecha con saldos desconocidos. No se repitió la suite completa.

Una prueba adicional generó una imagen sintética que se inspeccionó: solo dos selectores y los cuatro valores de Caja/Nequi, con fechas y AM/PM legibles. Análisis limpio. La copia propia consultada en dos rangos intradiarios conserva sus 60 tablas y esquema idénticos, integridad correcta y cero violaciones de claves foráneas, sin operaciones comerciales de prueba.

Formato limpio de tres archivos Dart. Release Windows 0.17.2+26 compilado sin overrides y publicado en el acceso estable. ZIP, estable y copia versionada coinciden en 17 archivos sin datos privados. El perfil activo se comparó de nuevo tras publicar: las 60 tablas, sus registros y el esquema siguen idénticos; integridad correcta y cero FK. No hubo migración, importación ni operaciones de prueba reales. La app estaba cerrada y se deja cerrada; no se afirma recorrido nativo nuevo. Ver [evidencia](evidence/reports-basic.json).
