# Abonos de deudores en Reportes — Desarrollo 0.37.0

Debajo de los ítems vendidos aparece Abonos de deudores: fecha y hora de Bogotá, nombre de la persona conservado al cobrar, medio e importe. Muestra subtotales de Efectivo y Transferencia y Total abonado con el estilo financiero de la app. Si existen cobros en otras cuentas, conserva su nombre y los incluye en el total. El rango utiliza las mismas fechas/horas del reporte e incluye todo el minuto final.

El detalle completo se ordena del más reciente al más antiguo, sin scroll vertical interno. En ventanas estrechas cada movimiento se distribuye en líneas; no hace falta desplazarse horizontalmente para leer los abonos. Un rango vacío muestra total cero y un mensaje explícito. Las notas siguen al final del reporte.

Solo se incluyen abonos confirmados, con documento y asiento publicados: pagos de Deudores y cobros manuales conservados del módulo anterior. Se excluyen cobros inmediatos de Ventas, nuevas ventas a Deudas, transferencias internas, aperturas y operaciones pendientes o rechazadas. No se vuelve a sumar un abono al total vendido: el cobro ya forma parte de los saldos monetarios existentes.

La consulta reutiliza los movimientos agrupados por documento y cuenta. Un abono distribuido entre varias deudas no se repite por cada asignación. Si un cobro antiguo utilizó varios medios, aparecen sus importes por cuenta y el total cuenta cada importe una vez. No se infieren abonos de ingresos genéricos del archivo antiguo, que no conservan identificación fiable de la persona.

Es un cambio de lectura y presentación, sin nuevas tablas, escrituras financieras ni migración. Esquema 21, 73 tablas. Entrega portable Desarrollo 0.37.0+57; se conserva Producción 1.2.1. Ver [evidencia sanitizada](evidence/report-payments-037.json). Datos, respaldos y capturas sintéticas permanecen fuera de Git y del paquete.

La primera ejecución aprobó 34 casos y encontró un fallo de carga del archivo de widgets por declarar sus helpers después de las pruebas nuevas. Se corrigió el orden y la repetición final aprobó 50 pruebas de aplicación más dos renders, inspeccionados a 1280/400. Cubren límites del rango por minuto, totales monetarios y desbordamientos, reintentos, cobros manuales antiguos con dos medios, separación de ventas, vacíos, orden de las secciones y ausencia de scroll interno. Análisis limpio y formato de 214 archivos sin cambios finales. No se repitió la suite general.

Respaldo de desarrollo verificado por contenido; las definiciones y filas de sus 73 tablas coinciden antes y después del inicio nativo, con integridad correcta y cero violaciones de claves foráneas. No se registraron negocios de prueba en la base activa. ZIP y bundle coinciden en 19 archivos sin privados; se retiró el ZIP anterior de Desarrollo y la limpieza quedó sin pendientes.

Los 21 archivos de distribución productiva, 20 de su instalación y el selector/JSON de desarrollo conservaron sus huellas. No se abrió la base productiva ni se detuvieron procesos del propietario. Desarrollo quedó abierto y respondiendo con su título. La revisión visual usa los renders sintéticos, sin inspección visual nativa nueva.
