# Contrato de trabajo — cuentas abiertas y ventas a crédito 0.3.0

Autorizado por «Entonces continúa» tras acordar dos entregas: cuentas y ventas primero, cobros después. Este incremento es parcial de etapa 4B y opera únicamente en desarrollo/pruebas del proyecto independiente.

## Comportamiento

Una cuenta abierta conserva nombre, cliente, productos, cantidades y precios unitarios elegidos, con revisión para detectar ediciones concurrentes. Guardar la cuenta no reserva ni descuenta stock y no reconoce ingreso ni deuda. La confirmación comprueba el stock vigente y todos los productos activos dentro de la transacción.

Confirmar la entrega genera una venta a crédito con snapshots históricos, salida de inventario y asignación FIFO, costo de mercancía vendida, cuenta por cobrar y asiento balanceado. No se registra dinero recibido. Se exige total positivo; las líneas gratuitas explícitas pueden acompañar líneas positivas. No hay impuestos ni descuentos calculados en este alcance; se conserva el importe comercial ingresado, sin afirmar tratamiento fiscal.

La confirmación se prepara antes como una solicitud persistida: identidad, revisión de cuenta, fecha, vencimiento y contenido exacto. Mientras tenga resultado incierto, la cuenta queda bloqueada. Reintentar utiliza la misma solicitud, también después de cerrar y reabrir. Un rechazo determinista se conserva; solo entonces se puede descartar esa solicitud para volver a editar. El descarte comprueba que no exista resultado confirmado y hace imposible confirmar la solicitud cancelada.

## Persistencia e integridad

Esquema v3 añadido sin modificar los statements/checksums v1/v2. Nuevas tablas de borradores, confirmaciones, ventas/líneas, salidas, asignaciones de costo y cuentas por cobrar. Las compras y obligaciones a proveedores conservan su estructura v2; las consultas de existencias combinan entradas confirmadas y salidas confirmadas. Se evita reconstruir tablas con claves foráneas durante esta ampliación.

Cada venta conserva la política `fifo-front-remainder-v1`: se consumen primero las capas recibidas antes; dentro de una capa cada unidad recibe el cociente entero y las primeras unidades reciben las unidades monetarias residuales. La política anterior de la función pura de fundación se conserva; no había salidas comerciales históricas. El costo total de una capa se conserva exactamente y las asignaciones no se superponen ni exceden sus cantidades.

Las operaciones que cambian venta, stock, costo, deuda, libro y resultado del comando confirman juntas o se revierten completas. Cantidades e importes usan enteros con límites y agregados BigInt; ningún precio actual reescribe ventas anteriores. Historia confirmada protegida contra UPDATE, DELETE y REPLACE.

Antes de migrar bases propias existentes se valida su esquema/historial y se crea un snapshot SQLite consistente. Se verifica el respaldo y su contenido contra la base bajo bloqueo antes de aplicar todas las migraciones pendientes en una transacción. No se admite downgrade, reset ni acceso a bases del original.

## Aceptación

- Recibir tres unidades; guardar dos en una cuenta; cerrar/reabrir: la cuenta sigue y el stock continúa en tres.
- Preparar confirmación, cerrar/reabrir y recuperar la misma identidad; confirmar: stock uno, ingreso, costo y deuda exactos, sin caja.
- Repetir la solicitud devuelve el mismo resultado y no duplica efectos; una identidad reutilizada con otro contenido se rechaza.
- Falta de stock, catálogo inactivo, edición obsoleta, importes inválidos o fallo durante el asiento no dejan una venta parcial.
- Varias capas y particiones conservan costo exacto; editar el catálogo no cambia el historial.
- Formulario, navegación, recuperación, rechazo y reintento ejercitados con pruebas; diagnóstico, compilación y paquete Windows comprobados antes de entregar.

Cobros, pagos, reservas, ajustes, devoluciones, servicios, arqueos, importación y uso productivo quedan pendientes. Este contrato describe el objetivo; los resultados efectivamente verificados se registrarán al terminar el incremento.
