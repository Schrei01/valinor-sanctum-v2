# Avisos de cumpleaños — Desarrollo 0.51.0

La franja verde superior informa de cumpleaños desde siete días antes hasta el propio día, aunque la persona solo esté registrada o tenga la membresía vencida. Requiere haber guardado día y mes en Membresías. Informa Cumpleaños en X días, Cumpleaños mañana o Cumpleaños hoy. Ordena por proximidad y luego nombre; muestra hasta tres personas y la cantidad adicional. Pulsar la franja abre Membresías, donde las tarjetas muestran el aviso individual de todos los próximos cumpleaños. Se conserva el aviso amarillo de vencimientos.

Se calcula el próximo cumpleaños con fechas de Bogotá y contempla el cambio de diciembre a enero. Para29 de febrero se usa28 de febrero en los años no bisiestos. Sin año de nacimiento, datos nuevos, migraciones ni modificaciones de cumpleaños guardados; esquema29. El cambio de día se actualiza con el reloj existente de la app. Los avisos son internos mientras la app está abierta.

Al guardar la ficha se actualiza también la lectura global de personas, para mostrar o retirar el aviso inmediatamente sin reiniciar la aplicación. Las personas sin día/mes no generan avisos.

Se aprobaron16 pruebas seleccionadas: ventana7→0 y exclusión8 días/pasados, cambio de año, medianoche de Bogotá,29 de febrero, ausencia/errores de fecha, aviso de personas sin mensualidad y vencidas, orden, acceso a Membresías y coexistencia con vencimientos a1120/400. Incluye regresión de los formularios de meses e interfaz general. La revisión conserva0.50 y se consolida en PR14 hacia main para revisión/CI. Producción1.9 continúa independiente.

Portable0.51.0+89 publicado y abierto para revisión; análisis limpio, formato250 sin cambios y Release correcta. Esquema29/87 tablas con integridad correcta y sin violaciones FK. Se retiró el ZIPDev anterior y se preservaron39 huellas de Producción/instalación. [Evidencia](evidence/membership-birthday-051.json).
