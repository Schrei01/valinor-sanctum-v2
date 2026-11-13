# Mensualidad Élfica — Desarrollo 0.47.0

La membresía cuesta COP 109.000 por mes calendario y comparte la persona de Deudores. Permite cobrar en Efectivo, Transferencia, Deudas o dividir el total mediante el flujo existente de Ventas. La inscripción se activa únicamente al confirmar esa venta, incluso cuando queda deuda. Los abonos posteriores se registran en Deudores y no renuevan ni restituyen beneficios.

## Uso

1. En **Membresías → Registrar persona**, elegir una persona ya registrada o escribir un nombre nuevo. Correo y día/mes de nacimiento son opcionales. No se guarda año de nacimiento. La fecha se valida, incluido el 29 de febrero.
2. Pulsar **Inscribir en Ventas**. Se abre una cuenta asociada con una Mensualidad Élfica. Puede añadirse otro consumo y elegir el pago o dividirlo. Confirmar con **Registrar venta**.
3. Al elegir esa persona en otra cuenta de Ventas se muestran vigencia y beneficios. También pueden consultarse en Membresías.
4. **Entregar booster** permite elegir una unidad física disponible. Confirmar la entrega descuenta inventario a costo FIFO y consume el booster incluido. No genera una venta cobrada ni un movimiento de Caja/Nequi. Se conserva como salida trazada de inventario y como beneficio de membresía.
5. Para los otros dos boosters, seleccionar el producto en Ventas y marcar **20 % de membresía**. La cantidad de esa línea consume la misma cantidad de descuentos. Se calcula el 80 % del PVP vigente, con redondeo a la unidad monetaria mínima. Puede usarse pago dividido o Deudas. Los descuentos se consumen al confirmar la venta, no al marcar la casilla.
6. **Renovar en Ventas** registra otra mensualidad. Si la actual sigue vigente, el período nuevo empieza al terminar el último contratado. Si ya venció, empieza el día de la nueva venta.

## Fechas y beneficios

- Fechas comerciales de Bogotá. Un período iniciado el 12/11 vence el 12/12 a las 00:00 de Bogotá; su último día de uso es el 11/12. Si el siguiente mes no tiene el día inicial, se usa su último día.
- Cada período tiene acceso ilimitado, un booster incluido y dos unidades con descuento del 20 %, combinando Yu-Gi-Oh!, Magic y Pokémon. No se acumulan beneficios entre períodos.
- La selección identifica productos físicos con «Booster» y el juego en su nombre (Magic, Pokémon/Pokemon, Yugi/Yu-Gi-Oh). Heroclix, Bulk y Alquiler quedan excluidos. El catálogo debe identificar correctamente los boosters.
- El acceso ilimitado se muestra para comprobar la vigencia en atención. Este incremento no lleva un registro de visitas ni cobra pasadías automáticamente a los miembros.
- Aviso dentro de la app al abrir y durante su uso: por vencer a tres días, vence hoy y vencida. Revisión por minuto y al actualizar/abrir Ventas. No envía correos ni notificaciones con la app cerrada.
- Historial por persona: períodos y productos entregados/comprados con descuento. El nombre del producto y sus precios se conservan como hechos históricos.
- Se confirma primero la inscripción y después se usan beneficios. Se conserva la regla existente de Ventas: un mismo producto debe tener un solo precio dentro de una cuenta. Para unidades del mismo booster a precio normal y con descuento se usan cuentas separadas.

## Integridad

Migración 28: cuatro tablas nuevas (`membership_profiles`, `membership_periods`, `membership_benefits`, `membership_sale_plans`) y una columna de borrador `quick_sales_lines.membership_discount`, predeterminada en 0 para todas las líneas anteriores. El historial de períodos, beneficios e intenciones preparadas es inmutable. La clasificación interna del servicio fijo reutiliza la vía sin inventario de Pasadía; su identidad es exclusiva `membership:elven`. No recibe compras.

La intención de inscripción/descuento se guarda en la misma transacción que prepara la venta y se aplica en la transacción que confirma inventario, dinero y deuda. Un rechazo revierte todo. Dos cuentas preparadas pueden competir por beneficios; la primera confirmada los consume y la otra se rechaza sin cobro ni salida de mercancía si ya no alcanza el cupo. Las entregas incluidas tienen identidad estable por período; reabrir/reintentar no las duplica. Una inscripción preparada en un día anterior pide preparar de nuevo para no activar una vigencia retroactiva por accidente.

Las migraciones publicadas 1–27 permanecen inalteradas y la apertura hace respaldo verificado antes de migrar. Los datos de Desarrollo y Producción siguen separados. Este incremento no publica Producción ni abre su base operativa.

## Verificación

Pruebas nuevas de calendario y cambio de mes, fecha de nacimiento, pagos parciales, deuda, entrega incluida con inventario/costo, límites de descuentos, cuentas concurrentes, renovación anticipada, recuperación tras reapertura y migración desde v27. Pruebas de interfaz a 1120 y 400 píxeles. Suite completa ejecutada: 940 aprobadas y tres omisiones conocidas del entorno; las dos pruebas de compatibilidad que requerían adaptar sus fixtures al nuevo campo fueron corregidas y verificadas en la repetición final, con 38 aprobadas y ningún fallo. Esa repetición incluye recuperación real tras varias reaperturas, pagos divididos, abonos, entrega y consumo de beneficios. Análisis sin incidencias y 243 archivos formateados. Compilación Release y paquete de 19 archivos verificados. Desarrollo quedó abierto y respondió; lectura nativa de su base confirma v28, 84 tablas, integridad correcta y ninguna violación de claves foráneas. Respaldo v27 automático observado. Producción sigue abierta y su ejecutable de distribución conserva su huella. [Evidencia de ejecución](evidence/memberships-047.json).

La entrega se realiza mediante PR desde `codex/membresias-elficas`. Su integración y etiqueta `dev-0.47.0` esperan la revisión del propietario y el CI completo aprobado.
