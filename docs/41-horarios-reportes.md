# Horarios de Reportes — 0.17.1

Desde 0.17.2, la interfaz usa AM/PM y el flujo fecha → hora, con solo Caja/Nequi iniciales y finales. Ver [alcance vigente](42-reportes-basicos.md). Esta página documenta la entrega anterior de 24 horas.

El propietario pidió ejemplos de fechas y poder determinar la hora de cada extremo, como en el repositorio base. Se leyó su selector de fecha/hora como referencia, sin ejecutar ni modificar el sistema original.

Reportes incorpora Hora inicial y Hora final con escritura manual HH:mm y selector de 24 horas. Conserva las fechas manuales y el calendario. Los valores iniciales 00:00–23:59 cubren días completos; se pueden elegir turnos en un mismo día o cruzando medianoche. El encabezado identifica las horas realmente consultadas. Actualizar conserva el rango generado.

La interpretación es de minutos de Bogotá (UTC−5), independiente de la zona horaria del equipo: desde el primer instante del minuto inicial hasta el último instante del minuto final. Internamente se compara inicio inclusivo/fin exclusivo al comienzo del siguiente minuto, conservando fracciones de segundo. Un rango 14:30–14:30 consulta ese minuto completo; un final anterior al inicio se rechaza. Los saldos y todos los hechos del reporte usan esos mismos límites; las agrupaciones por día/semana/mes conservan sus etiquetas de calendario.

Se agrega aviso cuando no hay operaciones confirmadas en el rango. Los saldos pueden existir aunque no haya ventas. No se inventan operaciones ni se importa historial del sistema anterior. El esquema permanece v13, sin migración ni escritura de datos por Reportes.

## Validación

Pasaron 30 pruebas de aplicación enfocadas: 16 de integración, siete de controlador, seis de formulario y una de navegación. Se comprobaron límites de un minuto con ventas antes, al inicio, en la última fracción del minuto final y al comienzo del siguiente; saldo inicial/final conciliados, cruce de medianoche, actualización del rango, horas inválidas, inversión en el mismo día y cancelación del selector. Las regresiones existentes de Reportes también pasaron. Una prueba adicional generó imágenes sintéticas de resumen y barras; se inspeccionó el resumen con los cuatro campos de fecha/hora, sin desbordamientos. No se repitió la suite completa.

Análisis sin incidencias y formato limpio de siete Dart. Una copia propia actual se consultó en dos rangos intradiarios; las 60 tablas y su esquema quedaron idénticos. Tras publicar también se concilió el perfil activo: todos los registros y el esquema intactos, integridad correcta y cero violaciones de claves foráneas. No se registraron ventas ni movimientos para la prueba.

Windows release 0.17.1+25 compilado sin overrides y publicado en el acceso estable. ZIP y copia versionada coinciden con la entrega estable en sus 17 archivos, sin bases ni perfiles privados. La aplicación estaba cerrada y se deja cerrada; no se afirma un recorrido nativo nuevo. La interfaz se validó mediante widgets e imagen sintética. Ver [evidencia](evidence/reports-time.json).
