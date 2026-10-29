# Desarrollo 0.32: inversión por recuperar

El propietario compra mercancía con dinero personal y la lleva a Valinor. El
programa debe conservar cuánto está pendiente de devolverle y permitir abonos.
No se añade una opción para entregar dinero personal a Caja o Nequi.

## Operación

- En **Compras**, **Pagar desde → Inversión** registra el producto o reposición,
  unidades, costo total, PVP, proveedor y categoría con el formulario existente.
  Aumentan inventario e inversión pendiente. Caja y Nequi no cambian. El proveedor
  queda pagado; esa compra no admite un segundo pago a proveedor.
- **Tesorería** muestra **Inversión por recuperar**, separada de Total disponible
  y de las deudas de clientes. **Registrar devolución** admite Caja o Nequi, valor
  y observación opcional, con miles agrupados. El pago reduce la cuenta elegida y
  la inversión pendiente, sin modificar inventario ni crear gastos o ventas.
- Una devolución debe ser positiva, no superar la inversión pendiente ni el saldo
  disponible. La confirmación vuelve a comprobar ambos saldos. Los movimientos
  no pueden ser anteriores al último movimiento de la inversión o cuenta usada.
- Compras y devoluciones tienen solicitudes durables; reabrir o reintentar la
  misma confirmación no repite la operación. Una solicitud rechazada conserva
  su motivo y puede descartarse para corregirla con otra identidad.
- **Reportes** conserva los saldos reales de Caja y Nequi y muestra las
  devoluciones del rango por separado, con desglose por cuenta y total. No se
  suman a ventas, egresos del negocio ni gastos que reduzcan otra vez la ganancia.
  El costo FIFO de la mercancía conserva su tratamiento habitual al venderla.

## Traslado inicial y persistencia

Esquema **19**, con tres tablas nuevas: `investment_operations` identifica
traslado, compras y devoluciones; `investment_initialization` conserva el saldo
de Caja mayor al activar el módulo; `investment_refund_requests` conserva las
solicitudes de devolución y su resultado. Son 72 tablas en total.

La inversión usa una cuenta contable de pasivo; no se registra como una caja ni
como dinero disponible. Una compra liquida la obligación con el proveedor contra
esa cuenta, en la misma transacción que el inventario y el historial de precios.
El historial de ingresos `paid_purchase_entries` admite el medio de financiación
sin una cuenta monetaria ficticia y conserva sus registros previos.

Durante la migración se crea un respaldo SQLite verificado. Si Caja mayor tiene
saldo negativo, se registra un único traslado trazable: queda en cero y el mismo
importe positivo queda pendiente de devolución. No se reescriben los documentos
anteriores. Un saldo cero o positivo se conserva; la migración no añade una cuenta
contable vacía a esos perfiles hasta usar el módulo. La inicialización impide
reinterpretar como inversión futuros saldos de Caja mayor.

Los asientos y operaciones confirmados son inmutables. Los controles SQL validan
la relación con solicitudes y compras, los dos renglones exactos del asiento y
los saldos para devolver. Los acumuladores usan enteros comprobados, incluidos
los casos en que el flujo bruto excede int64 y el saldo neto sigue siendo válido.

## Historial y entregas

Tesorería retira el bloque **Historial de la copia**. **Ver historial**, junto a
Últimos movimientos, abre una consulta conjunta con movimientos anteriores y
actuales, filtros de cuenta/fechas y páginas de diez. La consulta completa no está
limitada a los 50 recientes por cuenta de la pantalla principal. Incluye movimientos
de inversión. El JSON histórico sigue siendo un archivo de consulta; no se vuelve
a contabilizar ni se elimina porque los reportes aún lo utilizan.

La regla de distribución aclarada por el propietario conserva la última entrega
de **cada edición**. Publicar Producción conserva Desarrollo y viceversa. Una
nueva entrega de Desarrollo puede retirar las anteriores de Desarrollo; la 0.30
no queda fijada permanentemente. Este incremento publica únicamente Desarrollo.

## Verificaciones y entrega

La ejecución completa local terminó con **807 aprobadas, tres omitidas por
permisos de enlaces del host y tres fallos**. Dos eran expectativas anteriores
(medios con saldo inicial y etiqueta del historial); se actualizaron al contrato
nuevo. La prueba de navegación agotaba el reloj simulado mientras SQLite seguía
trabajando: se cambió a una espera acotada que cede tiempo real al aislado de base
de datos, conservando sus aserciones de ventas, saldos y cuentas. La repetición de
los tres archivos aprobó sus **35 pruebas de aplicación**, incluidos esos casos.
No se atribuye una segunda ejecución completa verde.

Los renders iniciales del historial encontraron el mismo problema de espera en
el ejecutor privado; se adaptó y se repitieron sus **diez renders**, todos
aprobados e inspeccionados en 1280 y 400 px. Análisis limpio y formato de 207 Dart
sin cambios. Pruebas financieras nuevas cubren compras sin caja, devolución
parcial/total por ambos medios, fondos/deuda insuficientes, revalidación de
solicitudes competidoras, rollback inyectado, reintentos/reapertura y acumulados
brutos superiores a int64 con saldos netos exactos. Migraciones sintéticas desde
v18 con reserva negativa/cero/positiva verificaron conservación, respaldo y
ausencia de repetición. Las pruebas SQL también rechazan sobregiros aunque un
llamador omita las validaciones de aplicación.

La base activa de Desarrollo se ensayó primero en una copia privada, con respaldo
manual verificado. Se migró con respaldo automático comprobado por contenido:
se conservan todos los registros anteriores de 69 tablas; hay 72 tablas y solo se
añade la reclasificación inicial esperada. Integridad y claves foráneas correctas.
Una lectura posterior al arranque nativo volvió a comprobar la conservación.
No hubo operaciones comerciales de prueba en la base del propietario.

Release **0.32.0+48**, esquema 19, publicada en `dist/ValinorSanctum2`; ZIP
`valinor-sanctum-2-0.32.0-development-windows-x64.zip`, con 19 archivos idénticos
al bundle y sin datos privados. El acceso raíz abre esa edición. Aplicación
abierta y responde con título **Valinor Sanctum - Desarrollo**; sin inspección
visual nativa, la revisión visual corresponde a widgets sintéticos.

Se retiraron tres artefactos obsoletos de Desarrollo (carpeta independiente 0.31
y ZIP 0.30/0.31), además de sustituir el bundle estable anterior. Se conservaron
por SHA256 21 archivos de la entrega productiva y los dos archivos de selección
e historial de Desarrollo. Las cinco pruebas de limpieza y seis comprobaciones
de separación por edición aprobaron; ambos dry-run finales no tienen pendientes.
Git autorizado. Evidencia sanitizada: `docs/evidence/investment-032.json`.
