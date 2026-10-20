# Tesorería — 0.10.0

**Tesorería** reemplaza la sección **Pagos** y reúne los saldos y los movimientos del dinero registrado en esta app.

| Indicador | Cálculo |
|---|---|
| Caja | Saldo de la cuenta asociada a Efectivo en Ventas y Compras |
| Nequi | Saldo de la cuenta asociada a Nequi en Ventas y Compras |
| Caja mayor | Cuenta de reserva independiente, inicialmente sin dinero registrado |
| Deudas | Pendiente de las cuentas por cobrar a clientes, confirmado por el propietario |
| Total disponible | Caja + Nequi |

Caja mayor y Deudas se muestran aparte y quedan fuera del Total disponible. No se copian los saldos del POS original. El código original sumaba también su reserva en el total y usaba un saldo de deudas genérico; aquí se aplica la fórmula y el significado indicados expresamente por el propietario.

Las ventas de contado ingresan dinero en la cuenta de su forma de pago; las compras y los pagos lo descuentan de la cuenta elegida. Cobrar una deuda aumenta esa cuenta y reduce lo pendiente del cliente. Preparar una cuenta o una operación no mueve dinero. Los saldos y el historial incluyen únicamente documentos y asientos contabilizados, leídos en una misma transacción.

El historial muestra fecha y hora de Bogotá, cuenta, concepto e ingreso o egreso. Conserva los últimos 50 movimientos de cada cuenta y permite filtrarlos. **Actualizar** vuelve a consultar los saldos y el historial; entrar a Tesorería también los recarga. Las cuentas monetarias adicionales siguen disponibles en el filtro y sus movimientos no se incorporan al total de Caja + Nequi.

Los pagos anteriores a proveedores se conservan en un panel secundario dentro de Tesorería. Esto permite recuperar solicitudes anteriores sin ocupar el resumen principal. Se mantienen los formularios y operaciones ya existentes de Compras, Ventas y Cobros. Esta entrega añade la consulta solicitada; no añade movimientos manuales de gastos, transferencias o aportes.

Se conserva el esquema v8. La única configuración nueva es una cuenta independiente de Caja mayor, creada sin saldo ni documentos financieros. No se modifican las migraciones ni se vuelve a importar inventario. Los cálculos monetarios usan enteros con comprobación de rango e intermediarios BigInt.

## Verificación

- Suite completa: **449 pruebas aprobadas**, tres omitidas por falta de enlaces de archivos en el host. Incluye nueve pruebas nuevas del adaptador SQLite, once de página/controller y una de navegación integrada.
- Se verificaron compras de contado, ventas por Efectivo/Nequi, cobros parciales y pagos existentes, con saldos conciliados; borradores excluidos; identidad de las cuentas, reserva separada, límites del historial y cálculos de rango completo sin desbordamientos silenciosos.
- La UI cubre filtros, actualización, errores conservando saldos previos, recuperación del panel de pagos aun si Tesorería falla, formato del mínimo entero y ventana estrecha. Los tests anteriores de pagos siguen pasando con el nuevo acceso secundario.
- Análisis limpio y formato final de 109 Dart sin cambios. Revisión independiente sin hallazgos pendientes. Vista previa de widgets inspeccionada con datos sintéticos.
- Antes de actualizar el acceso estable se creó un respaldo SQLite propio en `backups/treasury-20261020`; sus 45 tablas coincidieron con el perfil activo. El respaldo y las huellas de datos permanecen fuera de Git y del paquete.

La compilación Windows final 0.10.0+14, sin defines de Sanctum, terminó en 60,68 s. Se publicó el acceso estable y se verificaron sus 17 archivos contra el ZIP y `dist/0.10.0/ValinorSanctum2`, sin datos privados en el paquete.

La apertura nativa confirmó versión 0.10.0 y navegación Tesorería en lugar de Pagos. El control detectó interacción del propietario y la ventana después estaba minimizada; se detuvo la automatización. No se atribuye a esa sesión una inspección nativa de las tarjetas o filtros: estos se comprobaron en widgets. La app quedó abierta para el propietario y el agente no registró operaciones comerciales.

La comparación posterior de las 45 tablas confirmó 43 sin cambios y exactamente una fila nueva en `cash_accounts` y otra en `ledger_accounts` para Caja mayor, sin movimientos financieros de esa reserva. Integridad correcta y cero violaciones de claves foráneas. No se reinició la base ni se volvió a importar inventario.

La evidencia está en [treasury.json](evidence/treasury.json).
