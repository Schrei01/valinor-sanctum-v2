# Pagos divididos en Ventas — 0.28.0

El propietario aprueba dividir el importe de una misma línea entre Efectivo, Transferencia y Deudas. Eventos conserva su comportamiento actual; Compras sigue calculando el costo unitario desde el total y las unidades.

## Operación

1. Agregar producto y cantidad en una cuenta de Ventas.
2. Pulsar **Dividir pago** en esa línea.
3. Escribir los importes. **Enviar restante a Deudas** calcula total menos efectivo y transferencia.
4. Elegir la persona cuando exista deuda. La persona se aplica a todas las deudas de esa cuenta, como antes.
5. Pulsar **Guardar reparto**. Solo acepta importes válidos, medios habilitados y suma exacta. Cerrar o cancelar el cuadro conserva el reparto anterior.
6. Revisar el resumen de la cuenta y pulsar **Registrar venta**. Guardar el reparto todavía no cobra ni descuenta productos.

Un artículo de COP30.000 puede registrar COP10.000 en Caja, COP5.000 en Nequi y COP15.000 como deuda personal. Se vende y entrega una sola unidad. También permite repartir todo entre efectivo y transferencia sin deuda ni persona obligatoria.

**Editar reparto** vuelve a abrir los valores guardados. Elegir un medio en el selector habitual reemplaza el reparto por un pago completo. Cambiar de producto limpia el reparto anterior; cambiar cantidad conserva los importes para revisión y exige cuadrarlos con el nuevo total al registrar.

El borrador recupera sus partes al cambiar de sección o reabrir. La confirmación preparada guarda el reparto exacto y no permite cambiarlo durante un reintento. Las ventas, cantidades, costos e inscripciones se contabilizan una sola vez. Los abonos posteriores reducen el pendiente sin otra venta ni salida de inventario.

## Datos y compatibilidad

Esquema17, migración `split_line_payments_v17`: agrega `quick_sales_lines.payment_split_json`, inicialmente `[]`, y `quick_sale_split_tenders` para las partes confirmadas. Las 68 tablas previas conservan sus valores; se agrega una tabla, total69. Las filas de migraciones1–16 y sus checksums se conservan.

Las solicitudes nuevas con reparto usan canónico4. Los canónicos1–3 y sus tablas de pago originales conservan su significado. El registro compuesto reutiliza la venta FIFO y un cobro por los medios monetarios; la deuda es el saldo de la misma cuenta por cobrar, ligada a la persona elegida. Todo confirma en una sola transacción con identidad e importes inmutables.

Los importes se validan como enteros exactos de la escala del perfil. No se reparte la cantidad física entre medios ni se crean artículos duplicados. En los hechos de pago, la primera parte lleva la cantidad como proyección y las restantes cero; la cantidad comercial de Reportes proviene de `sale_lines` y se cuenta una sola vez.

Reportes suma los importes de las partes en Caja, Transferencia y Deudas. Los abonos posteriores continúan separados del total vendido. El historial de Ventas muestra una línea comercial con su desglose, importes formateados y cantidad original.

La actualización realiza el respaldo SQLite automático de v16 antes de migrar. La entrega local será de desarrollo, con la base propia del proyecto; no traslada datos a Documentos ni modifica el POS original.

## Validación y entrega

La suite completa ejecutada tuvo 772 pruebas aprobadas, tres omitidas por restricciones de enlaces simbólicos y un fallo en la construcción de una base histórica v12: intentaba copiar la nueva columna a un esquema que aún no la tenía. Se corrigió exclusivamente esa preparación y se repitieron las tres pruebas de compatibilidad, todas aprobadas. No se atribuye una segunda ejecución completa verde. Los once casos nuevos de pagos divididos pasaron en la suite general.

Se verificaron pagos con y sin deuda, recuperación de borrador y solicitud preparada al reabrir SQLite, varias líneas del mismo producto, abonos posteriores, rechazo de totales incorrectos/persona ausente/stock insuficiente, reversión ante fallo SQL intermedio, inmutabilidad y rechazo de solicitudes falsificadas. Una prueba de widgets conectada a SQLite verificó el cuadro, separadores de miles, persona obligatoria, suma exacta, reconstrucción y registro real. Dos renders sintéticos adicionales de 1200 y 400 píxeles se inspeccionaron. El primer render quedó esperando la escritura bajo FakeAsync; se ajustó el ejecutor privado a runAsync y ambos terminaron correctamente.

Análisis estático final sin incidencias y formato de 198 Dart sin cambios. Release 0.28.0+43 sin overrides SANCTUM, empaquetada como Development. ZIP y estable coinciden en18 archivos, sin bases o snapshots privados. Las entregas anteriores de dist se limpiaron según la retención aprobada. No se genera instalador local en este incremento.

Base activa de desarrollo respaldada con copia manual verificada y ensayo previo de migración sobre otra copia. La aplicación de v17 y la lectura después de iniciar el ejecutable conservaron los valores de todas las columnas anteriores de las68 tablas, las16 filas históricas de migración, perfil y registros comerciales. Se agregó la tabla vacía de repartos y el valor inicial `[]` en los borradores. Respaldo automático v16 verificado por contenido. Sin operaciones comerciales de prueba en la activa; Documentos conserva su SHA256 y el original permanece intacto.

La app queda abierta y responde, con título Valinor Sanctum2.0 y PE0.28.0+43 comprobados. No se atribuye inspección visual nativa de las cuentas reales. Evidencia sanitizada en `docs/evidence/split-payments.json`.
