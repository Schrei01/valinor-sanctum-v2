# Contrato — pagos a proveedores 0.5.0

Autorizado mediante «Da el siguiente incremento», después de proponer pagos a proveedores como siguiente entrega. Se completa el pago posterior de las compras a crédito ya recibidas.

- Mostrar compras pendientes, importe original, pagado y restante. Compras también refleja pagos confirmados. Un pago se aplica a una obligación de compra concreta y puede ser parcial, completo o repartido entre cuentas/medios.
- Reutilizar los catálogos locales de Cobros. Exigir cuenta monetaria activa y disponible, medio activo y saldo registrado suficiente por cuenta, sumando todas sus partes. No hay conexión bancaria ni envío de dinero externo: la interfaz registra un pago ya realizado.
- Guardar solicitud exacta antes de confirmar. Documento, partes históricas, aplicación de deuda y asiento se confirman juntos. Debitar proveedores por pagar y acreditar cuentas monetarias; no generar otra compra, gasto, costo o movimiento de stock.
- Revalidar deuda, fondos, actividad y disponibilidad en el momento de confirmar. Preparar no reserva dinero. Dos solicitudes sobre el mismo saldo pueden prepararse; la primera que confirma consume el saldo y la segunda se rechaza si ya no alcanza.
- Recuperar solicitudes preparadas al reabrir y reintentar con la misma identidad. Conservar la respuesta original, incluido el pendiente inmediatamente posterior a ese pago. Un error de almacenamiento no autoriza a inventar otro comando; solo un rechazo determinista puede descartarse para corregir.
- Reservar identidades entre compras, ventas, cobros y pagos. Conservar nombres/códigos históricos aunque se renombren o archiven los catálogos. Usar dinero entero y agregaciones BigInt acotadas a int64.
- Rechazar pagos anteriores a la compra, a otro pago de esa deuda o al último movimiento confirmado de cada cuenta usada. Comparar microsegundos UTC; las fechas de negocio se expresan en Bogotá.
- Añadir esquema v5 sin modificar migraciones v1–v4. Validar integridad, identidad y checksums antes de migrar y generar respaldo SQLite consistente previo, exclusivamente para bases propias.

Aceptación principal: compra de 100, fondos sintéticos obtenidos mediante venta/cobro, abono de 40, reapertura con deuda de 60 y pago restante repartido entre dos cuentas; deuda cero y saldos exactos. Reintentar ambos pagos sin duplicación; conservar la respuesta original del primer abono. Stock, capas, costo de ventas e ingreso comercial permanecen iguales. Cubrir sobrepago, fondos insuficientes por cuenta incluso con varios medios, disponibilidad/actividad, rechazo tras otra confirmación, rollback y recuperación durable, historial inmutable, migración v4 con cobros y navegación estrecha.

El formulario aún sin preparar solo vive durante la sesión. Las compras mantienen su límite de reintento en memoria del incremento 02. Aperturas, gastos, transferencias, capital, arqueos, ajustes/reversas, restauración desde interfaz, usuarios, importación y producción siguen pendientes. En una base nueva, el dinero disponible proviene de cobros registrados; no se inventan saldos de apertura.
