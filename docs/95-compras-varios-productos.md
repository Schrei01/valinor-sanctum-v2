# Compras con varios productos — Desarrollo 0.43.0

Compras registra una lista de productos con un solo **Total pagado**, una cuenta de pago y una categoría común. El total pagado aparece a la izquierda de **Pagar desde** en el encabezado; las opciones siguen siendo Efectivo, Nequi e Inversión. En una ventana estrecha se colocan uno debajo del otro.

**Agregar producto** añade otro formulario y **Quitar producto** retira uno conservando los demás. Cada formulario permite crear o reponer un producto, buscar por nombre/SKU, completar proveedor y PVP anterior, registrar unidades y costo total de sus unidades, calcular el PVP sugerido y recuperar el anterior con **Usar valor**. El PVP sigue siendo editable, también por debajo de la sugerencia, y su cambio aplica a las existencias y queda en el historial de precios.

La categoría se elige una sola vez. Elegir primero un producto existente puede completar la categoría del encabezado. A partir de ahí las sugerencias ofrecen únicamente productos de esa categoría. No permite cambiarla mientras queden productos existentes de otra categoría; se deben retirar o cambiar primero. La validación del controlador y del almacenamiento también rechaza categorías mezcladas y productos o SKU repetidos. Para repetir un mismo producto, suma sus unidades en un formulario.

El costo escrito en cada producto se conserva exactamente. El encabezado guarda por separado el total realmente pagado y la diferencia **pagado − suma de costos**. La diferencia puede ser positiva o negativa. El total pagado se completa inicialmente con la suma de costos; después de editarlo manualmente conserva ese valor aunque cambien los productos.

Por ejemplo, costos de 11.340 y 600 suman 11.940. Si se pagaron 12.000, el egreso o aumento de Inversión es 12.000 y la compra muestra una diferencia de 60. Para consultar el costo registrado de las cocacolas se mantienen 11.340; para consultar el gasto de la categoría se usan los 12.000 pagados, incluyendo su diferencia.

El historial reúne cada compra completa en una tarjeta: categoría, medio, total pagado, suma de costos, diferencia y detalle de sus productos. Las compras anteriores siguen visibles. La paginación muestra 10 compras completas, sin separar los productos de una compra entre páginas.

## Guardado y consultas

La migración 24 agrega dos tablas (`purchase_batch_requests` y `purchase_batch_items`) y dos vistas de consulta. Conserva las 74 tablas anteriores, sus definiciones y sus datos; no modifica migraciones publicadas. Una base actualizada tiene 76 tablas. El arranque crea un respaldo verificado antes de migrar.

La preparación conserva el encabezado, todos los productos y sus identificadores. Confirmar ejecuta las recepciones, actualizaciones de catálogo/PVP, inventario y pagos en una sola transacción exclusiva. Si falla un producto posterior, se revierten también los anteriores. Reintentos y reapertura recuperan la misma solicitud; una compra confirmada no vuelve a descontar dinero ni a ingresar unidades. Un rechazo permite corregir el formulario expresamente.

Los comprobantes contables existentes se reutilizan para conciliar inventario y cancelación de proveedores con el dinero efectivamente pagado. Internamente se distribuye ese importe entre las recepciones mediante proporciones enteras y restos, sin redondeos flotantes. Esta distribución contable tiene su propio campo `settlement_cost_minor`; **no reemplaza** los costos escritos por el operador, conservados en `declared_cost_minor` y en la solicitud original. No queda deuda con proveedores; Inversión aumenta únicamente por el total pagado y no mueve Caja ni Nequi.

Las vistas separan los dos conceptos y excluyen los comprobantes internos para evitar duplicaciones:

```sql
-- Gasto general o por categoría: dinero realmente pagado.
SELECT category_id, sum(amount_paid_minor)
FROM purchase_spending
WHERE occurred_at_utc >= :inicio AND occurred_at_utc < :fin_exclusivo
GROUP BY category_id;

-- Costo escrito de un producto, sin repartirle la diferencia del encabezado.
SELECT product_id, sum(cost_minor), sum(quantity)
FROM purchase_item_costs
WHERE occurred_at_utc >= :inicio AND occurred_at_utc < :fin_exclusivo
GROUP BY product_id;
```

Ambas vistas incluyen los ingresos individuales anteriores y las compras nuevas. Los reportes actuales siguen tomando los movimientos contables confirmados: sus egresos suman exactamente el total pagado. Las consultas de ejemplo son una referencia para futuros reportes, no nuevas secciones de gráficas o filtros. Para agregados monetarios de aplicación se mantienen sumas comprobadas con BigInt.

Se permiten hasta 100 productos por compra, costos positivos y un total pagado positivo que permita al menos una unidad monetaria mínima por recepción. Esa unidad es 1 COP en un perfil sin decimales o 0,01 en un perfil de dos decimales. Se conserva la precisión configurada; este incremento no cambia Valinor/COP/0 decimales.

## Validación y entrega

Las pruebas específicas cubren el ejemplo, diferencias positivas y negativas, los tres medios de pago, saldos insuficientes, precios distintos, categoría común, quitar formularios, cantidades y PVP sugerido/anterior, duplicados, reintentos inciertos, concurrencia, reapertura real de SQLite, conservación de solicitudes anteriores y migración con respaldo. Se inspeccionaron renders sintéticos de 1120 y 400 píxeles. Los resultados finales de la suite, la compilación y la publicación se registran en `docs/evidence/purchase-batches-043.json`.

Resultado local: 886 pruebas aprobadas en la suite completa y 3 omitidas porque el host no permite crear los enlaces simbólicos de esas pruebas. Antes se aprobaron 51 pruebas seleccionadas; no se suman otra vez al total de la suite. Análisis sin incidencias, formato de 224 archivos sin cambios en la comprobación final y compilación Windows Release correcta.

La portable quedó publicada y abierta para revisión. ZIP y bundle estable coinciden en sus 19 archivos y no contienen datos privados. Se retiró la portable anterior de Desarrollo y la limpieza no dejó pendientes. Las 43 huellas de Producción, instalación y configuración siguen iguales. El ensayo privado y la revisión posterior al arranque conservaron las definiciones y todas las filas anteriores de las 74 tablas, añadiendo solo el registro de migración y las dos tablas nuevas vacías; integridad y claves foráneas correctas. No se añadieron cuentas ni movimientos de negocio. La inspección visual corresponde a renders de widgets, sin inspección visual nativa.

Desarrollo 0.43.0+76 se entrega como portable para revisión del propietario. Conserva el agrupado de Reportes de 0.42.0, cuyo PR anterior aún no estaba integrado al comenzar este incremento. Producción 1.6.0 y sus archivos de Documentos permanecen independientes. El PR de este incremento requiere revisión del propietario y CI completo aprobado antes de integrarse; no publica una nueva versión de Producción.
