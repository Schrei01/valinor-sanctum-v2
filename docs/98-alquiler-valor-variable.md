# Alquiler por valor — Desarrollo 0.45.0

En Ventas, busca **Alquiler** y escribe el importe en **Valor vendido (COP)**. Es obligatorio y debe ser mayor que cero. Puedes agregarlo a la misma cuenta que una bebida, un evento o Bulk y pagar todo con Efectivo, Transferencia, Deudas o división de cuenta.

No se controla la cantidad de juegos ni el préstamo o devolución física. Como Bulk, una cuenta admite una línea de Alquiler: si aumenta el consumo, cambia su importe. El valor es propio de esa cuenta; no modifica el precio del catálogo ni otras cuentas.

El ítem siempre está disponible sin stock y aparece con precio Variable en Catálogo, en la categoría Artículo. No se ofrece en Compras, como premio de Eventos ni en ajustes físicos. Reportes muestra el importe cobrado y una operación por línea de Alquiler, sin estimar costos de juegos o cantidades alquiladas.

La validación existente se aplica en pantalla, controlador, guardado/confirmación SQLite y disparador de publicación. Cero y negativos no confirman ventas, cobros ni deuda.

## Compatibilidad y entrega

Desarrollo 0.45.0+79 mantiene su base independiente en `data/development/valinor/sanctum2.sqlite3`. La migración 25→26 cambia únicamente el validador de identidades de servicios; conserva las 76 tablas, historial y solicitudes pendientes. Reutiliza la clasificación interna `bulk` para el motor de valor variable, sin cambiar las migraciones publicadas. Al entrar se agrega `rental:sales:games`, su clasificación y un registro inicial de PVP cero de forma idempotente; se reutiliza la categoría Artículo.

Producción 1.7.0, su instalación, su ventana y los datos de Documentos se conservan. Este incremento se entrega primero como portable de Desarrollo, en una rama temporal y PR para revisión; la integración requiere conformidad del propietario y CI completo aprobado.

Los resultados efectivamente ejecutados se registran en `docs/evidence/rental-variable-price-045.json` y en el PR. Las copias de ensayo y respaldos quedan en directorios privados ignorados.
