# Abonos dentro del comprobante — Desarrollo 0.37.1

La indicación visual del propietario sitúa Abonos de deudores dentro del comprobante, debajo de Transferencias entre cuentas y a la derecha de Deudores al cierre. Se traslada el contenido a esa columna y se elimina la tarjeta independiente que aparecía después de los ítems vendidos. El encabezado, subtotales y total quedan alineados con las transferencias, aprovechando ese espacio.

En ventanas estrechas, Deudores al cierre, Transferencias entre cuentas y Abonos de deudores se apilan en ese orden dentro del comprobante. Se conserva el detalle completo sin scroll vertical interno. Los ítems vendidos y las notas siguen después del comprobante.

Es una corrección de presentación: mantiene la consulta, el rango y los cálculos de 0.37.0. Sin migración ni escrituras financieras, esquema 21 y 73 tablas. Entrega portable Desarrollo 0.37.1+58, con Producción 1.2.1 independiente. Ver [evidencia sanitizada](evidence/report-payment-position-0371.json).

Pasaron 24 pruebas de widgets y dos renders sintéticos, inspeccionados a 1280/400. Se comprueba que Abonos pertenece al comprobante, queda después del total transferido y antes de los ítems y, en ancho de escritorio, comparte la coordenada horizontal de Transferencias a la derecha de Deudores. Se mantienen detalle, subtotales, vacíos y ausencia de scroll interno. Análisis limpio y formato de 214 archivos sin cambios. No se repitió la suite financiera porque no cambian sus consultas ni cálculos.

El ZIP se preparó antes de pedir el cierre de Desarrollo 0.37.0. El propietario confirmó que la ventana estaba cerrada antes del respaldo y la publicación.

Respaldo de desarrollo verificado por contenido, 73 tablas con filas y definiciones idénticas antes y después del inicio nativo, integridad correcta y cero violaciones de claves foráneas. ZIP y bundle coinciden en 19 archivos sin privados. La entrega anterior de Desarrollo se retiró y la limpieza quedó sin pendientes.

Los 21 archivos de distribución productiva, 20 de su instalación y el selector/JSON de desarrollo conservaron sus huellas. No se abrió la base productiva ni se realizaron operaciones comerciales de prueba en desarrollo. La app de desarrollo quedó abierta y respondiendo con su título; la revisión visual utilizó renders sintéticos.
