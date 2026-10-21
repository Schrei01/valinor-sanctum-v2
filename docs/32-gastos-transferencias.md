# Gastos y transferencias — 0.12.0

Tesorería incorpora **Registrar gasto** y **Transferir dinero** junto al resumen de saldos. Se conserva el inventario y el historial comercial existentes.

## Registrar gasto

Selecciona **Caja o Nequi**, escribe el valor y elige **Arriendo, Aseo, Servicios u Otro**. La observación es opcional en todos los casos. La fecha se toma del momento del registro y se presenta en horario de Bogotá.

El gasto descuenta el saldo de la cuenta elegida y aparece en Últimos movimientos con su motivo y observación, si se escribió. Contablemente registra gasto de funcionamiento contra la cuenta monetaria; no genera productos, compras de mercancía ni deudas.

## Transferir dinero

Selecciona cuenta de origen, cuenta de destino y valor. Puedes escribir una observación. Se ofrecen cuentas monetarias activas y disponibles, incluyendo Caja mayor. Las deudas de clientes no son una cuenta de dinero.

El registro mueve el mismo valor de origen a destino en una sola transacción. El historial de origen identifica la salida y el destino; el historial de destino identifica la entrada y el origen. La transferencia no genera una venta ni un gasto.

**Total disponible** sigue siendo Caja + Nequi. Transferir entre estas dos cuentas conserva ese total; mover dinero hacia Caja mayor lo reduce y mover desde Caja mayor lo aumenta. Caja mayor conserva su saldo heredado, incluido su signo. Una cuenta sin fondos suficientes no puede ser origen de un nuevo gasto o transferencia.

## Confirmación y recuperación

Se exige un valor positivo a la precisión del perfil, saldo suficiente y cuentas distintas para transferir. Se valida nuevamente dentro de la transacción; dos operaciones preparadas no pueden gastar los mismos fondos. Se comprueba el rango monetario, la identidad de las cuentas y la cronología de ambas cuentas afectadas.

Cada solicitud se prepara antes de contabilizarse. Si el resultado no puede confirmarse, Tesorería mantiene una tarjeta para **Reintentar** la misma solicitud. Tras cerrar y reabrir la app, las solicitudes guardadas vuelven a aparecer. Un reintento de una operación ya confirmada devuelve el resultado original y no mueve dinero otra vez. Una operación rechazada habilita **Corregir** para revisar sus datos mediante una nueva solicitud.

Los documentos, asientos y solicitudes confirmadas son inmutables. Las dos líneas del asiento deben corresponder exactamente con el gasto o transferencia guardados. La migración v10 agrega tablas y restricciones específicas; las migraciones publicadas v1–v9 se conservan intactas. No se importan saldos ni se reinicializan cuentas para habilitar estas opciones.

## Verificación

- **563 casos aprobados en conjunto**: la ejecución general aprobó 562 y omitió tres por enlaces de archivos no disponibles en el host. La comprobación restante de migración se adaptó para esperar el esquema vigente y se repitió con éxito. No se atribuye a la ejecución general un resultado único sin fallos antes de esa corrección de prueba.
- Hay **58 casos nuevos**: 20 de almacenamiento, 13 de restricciones SQL, 14 de controlador, diez de formularios y uno de migración v9 con respaldo. La prueba del shell existente también comprueba que ambos botones estén conectados y se recarguen al entrar en Tesorería.
- Cobertura de importes exactos, fondos insuficientes, origen/destino distintos, reserva negativa, desbordamiento, competencia, cronología por ambas cuentas, recuperación tras cierre, respuesta incierta, identidades reservadas e inmutabilidad. Las notas opcionales aparecen en el historial.
- Análisis limpio, 21 archivos Dart modificados con formato limpio y revisión independiente sin hallazgos pendientes. Los nueve nombres y checksums de migraciones publicadas se compararon con la entrega anterior y permanecen intactos.
- Respaldo previo verificado de la base propia v9. El ensayo final sobre una copia aislada migró a v10 y conservó todos los registros de las 46 tablas anteriores, saldos e inventario. Solo se agregan la fila de migración y la configuración interna del gasto; las dos tablas nuevas quedan vacías. Integridad correcta y cero violaciones de claves foráneas.

La evidencia y la entrega local se documentan en [treasury-operations.json](evidence/treasury-operations.json).

## Entrega local

El bundle Windows final sin configuraciones de prueba está publicado en el acceso habitual, con copia versionada y ZIP 0.12.0. Sus 17 archivos se verificaron entre las tres copias; el paquete excluye bases, perfiles y snapshots privados.

La apertura del bundle final migró la base propia a v10 y creó su respaldo automático v9, coincidente con el respaldo manual. La comparación posterior conserva todos los registros de las 46 tablas previas, dinero e inventario; las tablas nuevas de operaciones permanecen vacías. Solo se añaden la configuración contable de gastos y la fila de migración.

En Windows se observaron ambos botones y se abrieron los dos diálogos mediante accesibilidad y teclado. Se comprobaron cuenta/valor/motivo/observación del gasto y origen/destino/valor/observación de la transferencia; ambos se cerraron sin enviar operaciones. Se dejó Tesorería abierta para el propietario. No se capturaron imágenes ni se registraron gastos o transferencias de prueba en su perfil.
