# Contrato — cobros y abonos 0.4.0

Autorizado mediante «Vamos con el otro incremento entonces» y «Continúa». Se completa el cobro de ventas a crédito del incremento 03; no se amplía a pagos a proveedores ni operaciones productivas.

- Configurar cuentas locales de efectivo, banco, móvil o tránsito y medios de pago. Una cuenta nueva no crea un saldo de apertura; su saldo registrado se reconstruye del libro. La disponibilidad se distingue de la actividad. No existe conexión bancaria ni procesamiento externo de pagos.
- Aplicar un cobro positivo a una cuenta por cobrar confirmada, completo o parcial, con varias partes por cuenta/medio. La suma no puede exceder el pendiente. La interfaz pide confirmar dinero ya recibido.
- Registrar solicitud, documento, partes históricas, aplicación a deuda y asiento. El cobro debita las cuentas monetarias y acredita el control de clientes. No crea otra venta, ingreso comercial, costo ni movimiento de inventario.
- Preparar en disco el contenido exacto antes de confirmar. Un resultado incierto se recupera y reintenta con la misma identidad después de cerrar/reabrir. Solo un rechazo determinista puede cancelarse para corregir. Las identidades quedan reservadas entre compras, ventas y cobros.
- Conservar el resultado original, incluido el saldo restante en ese momento; reintentar un abono antiguo después de otros cobros no sustituye esa respuesta por el saldo actual.
- Usar dinero entero y agregados BigInt con límites int64, también para el saldo registrado de cada cuenta. Rechazar cobros anteriores a la venta o al último cobro de esa deuda, comparando microsegundos UTC.
- Conservar nombres y códigos históricos de cuentas/medios y cliente/venta. Renombrar o archivar catálogos no reescribe los cobros confirmados. No se cambia la identidad o naturaleza de una cuenta configurada.
- Añadir esquema v4 sin alterar statements/checksums v1–v3. Migrar solo bases propias con validación y respaldo SQLite consistente previo.

Aceptación principal: venta de 100, abono de 40 y pendiente de 60 al reabrir; completar los 60 por dos medios, obtener pendiente cero y saldos exactos; repetir ambos comandos sin duplicación y conservar la respuesta original del primer abono. Inventario, costo e ingreso comercial no cambian por cobrar. Cubrir rechazo de sobrepago, fallo/rollback, historial, concurrencia lógica, interfaz estrecha y recuperación tras lectura fallida.

Los formularios aún sin confirmar solo se conservan durante la sesión. La recuperación durable empieza cuando la preparación quedó guardada. Las compras mantienen el límite de reintento en memoria del incremento 02. Aperturas, pagos a proveedores, gastos, transferencias, arqueos, reversas, restauración desde interfaz, importación y producción permanecen fuera de este incremento.
