# Abonos resumidos por medio — Desarrollo 0.37.2

El bloque Abonos de deudores del comprobante muestra únicamente dos totales: Efectivo y Transferencia. Se retiran sus nombres, fechas, movimientos individuales y total combinado. Cada importe usa el mismo estilo de total financiero de la app y refleja solo los abonos del rango seleccionado; un rango sin abonos muestra cero en ambos medios.

El bloque conserva su ubicación bajo Transferencias entre cuentas, a la derecha de Deudores al cierre en escritorio y apilado después de transferencias en ventanas estrechas. La sección Deudores al cierre permanece como estaba. El historial individual sigue disponible en el módulo Deudores.

No cambian la consulta ni los cálculos: se reutilizan los totales por cuenta del reporte existente, con límites por minuto en Bogotá y sin contar ventas ni transferencias internas como abonos. No se modifican datos ni esquema: 21, 73 tablas. Entrega portable Desarrollo 0.37.2+59, con Producción 1.2.1 independiente. Ver [evidencia sanitizada](evidence/report-payment-totals-0372.json).

Pasaron 26 pruebas de aplicación y dos renders sintéticos, inspeccionados a 1280/400. Se comprueba ubicación, valores por medio, ausencia de nombres/fechas/detalle y total combinado, ceros en rangos vacíos, separación de ventas y límites del período. Análisis limpio y formato de 214 archivos sin cambios finales. El ZIP quedó preparado antes de pedir el cierre de la ventana anterior para publicar.

El propietario confirmó el cierre antes de publicar. Respaldo verificado por contenido y 73 tablas con filas/definiciones idénticas después del inicio nativo, integridad correcta y cero violaciones de claves foráneas. ZIP/bundle coinciden en 19 archivos sin datos privados; entrega anterior de Desarrollo retirada y limpieza sin pendientes.

Los 21 archivos productivos, 20 de su instalación y selector/JSON de desarrollo conservaron sus huellas. La base productiva no se abrió y no se registraron operaciones comerciales de prueba en desarrollo. La app quedó abierta y respondiendo con su título; revisión visual mediante renders sintéticos.
