# Deuda anterior a cada fiado — Desarrollo 0.48.0

En Deudores, el historial de la persona cambia **Pendiente** por **Deuda anterior**. El segundo importe representa el saldo personal inmediatamente anterior a ese movimiento, calculado con los cargos y abonos registrados hasta entonces. El saldo actual sigue en la tarjeta superior.

Ejemplo: saldo inicial de $100.000, fiado de $20.000, abono de $50.000 y otro fiado de $10.000. El primer fiado muestra Deuda anterior $100.000; el segundo muestra $70.000. El abono posterior no cambia el valor anterior del primer fiado.

La reconstrucción considera saldos iniciales registrados, ventas a deuda y préstamos; resta los abonos posteriores a esas operaciones registrados tanto en Deudores como en el adaptador de Cobros. En ventas divididas, Valor fiado es únicamente la porción a Deudas. El cobro inmediato de la parte en Efectivo/Transferencia no se resta otra vez ni reduce deudas anteriores.

Se ordenan las operaciones por su fecha/hora comercial y, en empates, por la secuencia de registro de sus documentos. El historial muestra primero los movimientos más recientes. Se conservan también los cargos ya pagados. El cálculo parte del primer saldo registrado en esta app; no inventa movimientos anteriores a una importación. Si el historial disponible produce un saldo no representable, se muestra Sin información.

Es una proyección de lectura: no modifica importes, abonos, dinero, inventario ni el esquema v28. La propiedad restante por deuda sigue disponible internamente para cobrar y conciliar.

Validación enfocada: saldos personales independientes, abonos intermedios y posteriores, deudas liquidadas, empates de fecha/hora, ventas divididas, cobros anteriores, reapertura de archivos, ausencia de escrituras adicionales y presentación a 1120/400 píxeles. 41 pruebas enfocadas aprobadas, análisis sin incidencias y verificación de formato sobre 243 archivos sin cambios. Compilación Release y paquete de 19 archivos verificados. Desarrollo quedó abierto y responde; lectura nativa confirma esquema28, 84 tablas, COP/0 decimales, integridad correcta y ninguna violación de claves foráneas. No se abrió la base operativa de Producción y su distribución conserva la huella. [Resultados](evidence/debtor-history-048.json).

Conserva Membresías 0.47.0. Como su PR #10 sigue abierto para revisión, este incremento se entrega en una rama temporal dependiente (`codex/deudores-saldo-anterior`) y un PR cuya base es `codex/membresias-elficas`. Tras integrar #10 se retargetea a main y se vuelve a validar antes del merge. No se integra ninguno sin la conformidad del propietario y CI completo aprobado.
