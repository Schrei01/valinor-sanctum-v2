# Dividir el total de la cuenta — 0.29.0

El propietario pide mantener por ahora el selector de pago por línea y trasladar la división al total de la cuenta. La deuda debe usar exclusivamente la persona ya asociada en el encabezado.

## Uso

En Ventas, **Dividir cuenta** aparece junto al total, antes de Registrar venta. El cuadro muestra el total de todos los artículos y permite repartirlo entre Efectivo, Transferencia y Deudas. Conserva **Enviar restante a Deudas** y los separadores de miles. Al volver a abrirlo, muestra los importes actuales de la cuenta, incluidas las selecciones por línea.

No hay un selector de persona dentro del cuadro. Si hay deuda, se informa a quién se asignará; si falta la asociación o está bloqueada, no permite guardar y dirige al encabezado de la cuenta. Los pagos sin deuda no requieren una persona.

**Guardar reparto** cambia el borrador completo en una sola edición. **Registrar venta** sigue siendo la confirmación de dinero, inventario y deuda. El botón pasa a **Editar división** cuando la cuenta tiene un reparto guardado. Cancelar el cuadro conserva los valores previos.

El selector habitual permanece en cada línea. Elegir un medio allí reemplaza el pago de esa línea y actualiza el resumen de la cuenta; las otras líneas conservan sus pagos. Cambiar cantidades conserva los importes guardados para revisión: si ya no cuadran con el nuevo total, hay que editar la división o corregir el pago antes de registrar. No se eliminan borradores o ventas anteriores.

## Registro exacto

No cambia el esquema17 ni las69 tablas. El importe global se distribuye internamente entre las líneas para reutilizar el registro durable y los Reportes existentes. Cada medio se reparte proporcionalmente a los importes restantes de las líneas, con restos mayores y desempate por orden de línea. Se usan enteros BigInt; tanto el total por artículo como el total por medio coinciden exactamente, incluso con redondeos.

Esta distribución es una convención para el detalle de pagos por producto en Reportes: el usuario introduce el pago de la cuenta completa. Se guarda al confirmar el reparto, no se recalcula a partir de precios futuros. Las cantidades físicas permanecen intactas y solo se descuentan al registrar la venta.

Se rechazan importes negativos, medios repetidos, sumas distintas del total, cantidades/productos incompletos y totales fuera de rango. También se rechaza la deuda sin persona antes de consultar por su identificador en SQLite.

## Validación y entrega

- 33 pruebas de interfaz y controlador aprobadas, incluido el cuadro con SQLite real, varias líneas, persona heredada del encabezado, ausencia del selector redundante, guardado, recuperación y venta.
- Otra ejecución con26 aprobadas cubrió reparto, pagos, abonos, rollback, historia inmutable, compatibilidad, navegación y crédito. La repetición final tras el ajuste de validación de persona tuvo13 pruebas de aplicación aprobadas y dos renders adicionales.
- Cinco pruebas nuevas de algoritmo/controlador incluyen40 órdenes deterministas de20 líneas, igualdad de ambas sumas, casos cero, valor monetario máximo, errores, conservación de datos de entrada y cambio posterior de un selector de línea. Son escenarios de asignación, no jornadas de ventas adicionales.
- Análisis limpio y formato de200 Dart sin cambios. Dos imágenes sintéticas de1200 y400 píxeles inspeccionadas: cuadro compacto con persona informativa, sin otro selector.

Release de desarrollo 0.29.0+44 compilada sin overrides y publicada; ZIP y estable coinciden en18 archivos sin datos privados. La distribución anterior se limpió. No se genera un instalador local.

Respaldo manual verificado antes de publicar. Tras abrir el ejecutable, las69 tablas conservan sus filas y definiciones y el SHA256 completo de la base de desarrollo coincide con el previo. Documentos también conserva sus bytes. La primera lectura de comprobación coincidió con el bloqueo de arranque; la repetición en solo lectura con espera de SQLite verificó correctamente los datos. Sin operaciones comerciales de prueba en la activa ni cambios al original.

La ventana queda abierta y responde; versión PE0.29.0+44 y título comprobados por proceso. No se atribuye revisión visual de las cuentas reales. No se repitió la suite completa en este incremento; el CI de la entrega anterior3a807aa terminó correctamente. La evidencia sanitizada final está en `docs/evidence/account-split.json`.
