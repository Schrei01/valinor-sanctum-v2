# Contrato de trabajo — catálogo y recepción 0.2.0

Continuación autorizada el 19/10/2026. Entrega parcial de 4A: catálogo de productos en unidades enteras, categorías, proveedores y compras recibidas a crédito. Sin pagos ni ajustes. Solo desarrollo/pruebas del proyecto nuevo.

## Puerto compartido

`lib/features/inventory/domain/inventory_store.dart` exporta modelos e interfaz:

- `InventoryCategory(id, name, isActive=true)`.
- `InventorySupplier(id, name, isActive=true)`.
- `CatalogProduct(id, name, sku?, categoryId?, listPriceMinor, isActive=true)`.
- `StockPosition(productId, quantity, totalCostMinor)`.
- `PurchaseReceiptLine(productName, quantity, totalCostMinor)` con nombre histórico.
- `PurchaseReceiptSummary(documentId, supplierName, reference?, totalMinor, receivedAtUtc, dueDate, lines=[])`.
- `InventorySnapshot(categories, suppliers, products, stock, receipts)`; listas inmutables.
- `ReceiptLineInput(productId, quantity, totalCostMinor)`.
- `ReceiptCommand(commandId, supplierId, lines, reference?, dueDate, occurredAtUtc)`; fecha de vencimiento ISO YYYY-MM-DD. Guardar el mismo comando para reintentar un fallo incierto.
- `ReceiptResult(documentId, commandId, totalMinor)`; respuesta persistida e idéntica al repetir el mismo comando.
- `InventoryStore.load()`, `saveCategory(InventoryCategory)`, `saveSupplier(InventorySupplier)`, `saveProduct(CatalogProduct)`, `receivePurchase(ReceiptCommand)`.
- `SqliteInventoryStore(AppDatabase database, {bool synthetic=false})` implementa el puerto; valida perfil configurado en cada comando. El entorno test pasa synthetic explícitamente. Generación de IDs por `InventoryIds.next()` disponible en el mismo archivo de dominio o helper exportado.

La sesión de workspace puede exponer opcionalmente `InventoryStore? inventoryStore` sin romper los fakes existentes. El composition root crea el adaptador con la misma conexión. La interfaz no accede a SQLite.

## Persistencia v2

Mantener los statements/checksum v1 intactos para validar bases previas. Migración v1→v2 respaldada con snapshot SQLite consistente, verificado y dentro del proyecto; migración transaccional y rechazo de bases ajenas/futuras/alteradas. Fresh v2 conserva historial v1 y v2 verificable.

Nuevas tablas y columnas acordadas (IDs TEXT, FK RESTRICT, enteros con typeof y límites):

- `categories`: id, name, is_active.
- `counterparties`: id, name, is_customer (0), is_supplier (1), is_active.
- `catalog_items`: id, sku (NULL o único NOCASE), name, kind ('product'), category_id NULL, unit_code ('unit'), quantity_scale (0), list_price_minor >=0, is_active.
- `purchases`: document_id PK/FK, supplier_id, supplier_name_snapshot, supplier_reference NULL, received_at_utc, due_date, payable_minor >0, terms ('credit').
- `purchase_lines`: id, purchase_id, sequence, product_id, name_snapshot, quantity >0, acquisition_total_minor >=0, cost_quality ('documented'); unique(purchase_id,sequence).
- `inventory_movements`: id, document_id, sequence, stock_sequence único, product_id, kind ('purchase'), quantity_delta >0, value_delta_minor >=0, purchase_line_id único; unique(document_id,sequence).
- `cost_layers`: id, inbound_movement_id único, product_id, initial_quantity >0, total_cost_minor >=0, cost_quality ('documented'), fifo_sequence único, acquired_at_utc.
- `obligations`: id, origin_document_id, sequence, counterparty_id, kind ('supplier_payable'), control_account_id, initial_minor >0, issued_at_utc, due_date; unique(origin_document_id,sequence).
- Añadir `command_log.authorization_policy_version` con default histórico 'foundation-v1'; nuevos comandos usan 'development-single-user-v1'.

Las escrituras comerciales empiezan con documento/asiento draft, insertan líneas/movimientos/capas/deuda y congelan documento/asiento al final. Triggers impiden modificar historia confirmada y comprueban coherencia de una compra al confirmar. Compra: Debe Inventario, Haber Proveedores por pagar; sin gasto ni salida de caja. Crear las dos cuentas internas y el actor de sistema 'Operador local' al primer comando, dentro de su transacción, sin saldos de ejemplo. No representar el actor como una persona autenticada.

## Reglas de aceptación

- Perfil obligatorio, precio/costo exactos de su escala, cantidad entera positiva, costo total de cada línea explícito (puede ser cero), total de compra positivo; límites int64 usando BigInt para agregados.
- Rechazar productos/proveedores/categorías inactivos en nuevas operaciones. No eliminar catálogos con historia; permitir editar y archivar, sin cambiar snapshots históricos.
- Validar fechas ISO reales, vencimiento no anterior a fecha de recepción Bogotá, referencias y nombres con límites. Una misma compra no repite un producto en varias líneas.
- Repetir commandId y payload devuelve respuesta original; distinto payload se rechaza. Una falla revierte documento, stock, deuda, asiento y command_log.
- Stock y valoración se reconstruyen desde movimientos/capas confirmados, sin setters de saldo. Ningún dato sintético precargado en la app.
- Formularios con carga/error/reintento, envío doble bloqueado y conservación del mismo commandId en reintento de recepción. Solo borrar formulario después de confirmación.
- Pruebas de migración/preservación, rollback, límites, duplicados, snapshots y reapertura. Build Windows y paquete 0.2.0 después de checks.
