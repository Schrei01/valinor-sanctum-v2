# Editar datos de Membresías — Desarrollo 0.54.0

En **Membresías → Editar datos**, ahora se puede corregir el nombre y la fecha de inicio, además del correo y día/mes de nacimiento. El mes mantiene la lista de nombres. Al elegir otra fecha se muestra el vencimiento recalculado: un mes calendario después, ajustado al último día del mes cuando sea necesario. No se añade un atajo Ctrl+D.

El bono no se edita ni se reinicia: conserva lo otorgado, lo redimido y su saldo. Cambiar la vigencia afecta la disponibilidad del beneficio según las fechas corregidas. Una persona inscrita sin mensualidad permite editar sus datos personales; para tener una fecha de inicio debe registrarse la mensualidad mediante Ventas.

El nombre conserva el identificador compartido con Ventas y Deudores. Los documentos y sus nombres históricos permanecen como se registraron. Se rechazan nombres duplicados, cumpleaños inválidos y formularios cuyos datos ya cambiaron. La nueva vigencia no puede cruzarse con otra renovación ni dejar por fuera consumos de bono confirmados; se deben resolver las ventas pendientes de esa persona antes de cambiar fechas.

La migración de esquema29 a30 crea `membership_corrections`, con solicitud y valores anteriores/nuevos inmutables. Las protecciones de identidad y períodos solo admiten los cambios correspondientes a una corrección auditada. Nombre, perfil, fechas y auditoría se guardan en una transacción; reintentar la misma solicitud no duplica la corrección. Dinero, deudas, inventario, ventas y beneficios no se recalculan por editar datos. Antes de migrar se crea y verifica el respaldo existente de la aplicación.

Versión `0.54.0+94`, portable de Desarrollo, conserva la corrección de Compras0.53.0. Producción1.11.0 y su base permanecen separadas. El PR18 consolida ambos incrementos hacia main y queda para revisión; no integrar ni etiquetar antes de conformidad del propietario y CI completo aprobado.
