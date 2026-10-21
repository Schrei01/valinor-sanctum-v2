# Ventas con Deudas — 0.13.0

> Alcance actualizado en 0.13.2: **Nequi en Compras y Transferencia en Ventas**. Consulta [la aclaración vigente](35-nombres-pago-ventas.md).

Ventas incorpora **Deudas** como forma de pago de cada línea. Se conserva la pantalla de varias cuentas y el registro con una sola acción.

## Registrar una venta fiada

1. Crea o abre una cuenta en **Ventas** y agrega sus productos y cantidades.
2. En las líneas que el cliente deja pendientes, selecciona **Deudas**.
3. Escribe el **Cliente de la deuda** en la cuenta. El campo aparece cuando hay alguna línea en Deudas y es obligatorio para registrar esa venta.
4. Revisa el total y el resumen **Cobrado / Deudas**, y pulsa **Registrar venta**.

La entrega descuenta inventario y registra costo FIFO, venta y cuenta por cobrar en una sola transacción. Lo fiado usa el precio de venta de la línea. No aumenta Caja ni Nequi y no crea una cuenta monetaria llamada Deudas.

Una cuenta puede mezclar líneas en Efectivo, Nequi y Deudas. Solo el importe pagado se cobra y entra a la cuenta monetaria correspondiente; la diferencia queda a nombre del cliente. Una cuenta totalmente fiada no genera un documento de cobro vacío. También se conservan las líneas de precio cero sin inventar movimientos de dinero.

En **Tesorería**, el indicador **Deudas** incluye el saldo pendiente de estas ventas junto a la cartera existente. Desde **Cobros** puedes seleccionar la venta del cliente y registrar su abono o pago. Ese cobro reduce la deuda y aumenta la cuenta elegida; no vuelve a vender ni descontar existencias. El historial de Ventas conserva el cliente y el valor fiado original, aunque luego se cobre.

## Guardado y recuperación

La cuenta, sus líneas y el nombre del cliente se guardan automáticamente. Volver una línea a Efectivo oculta el campo de cliente cuando ya no quedan líneas fiadas; el nombre escrito se conserva en el borrador para reutilizarlo. Las cuentas de contado mantienen su recorrido habitual.

La confirmación preparada queda guardada antes de contabilizar. Si se pierde la respuesta o se cierra la app, **Reintentar venta** recupera el resultado original sin duplicar inventario, venta, deuda ni dinero. Una venta rechazada permite corregir la cuenta. Los hechos confirmados y sus nombres históricos no se editan.

## Transferencia en Compras

En **Compras**, la opción **Nequi** ahora se presenta como **Transferencia**. Conserva la misma cuenta y medio de pago: no crea otra cuenta ni cambia saldos. El resto de la app conserva el nombre Nequi, y los snapshots de pagos históricos mantienen su texto original.

Compras sigue ingresando mercancía pagada de contado. El flujo pedido de descontar inventario y aumentar lo que debe un cliente se implementa en Ventas.

## Esquema y conservación

La migración v11 agrega el nombre del cliente al borrador, la clasificación de crédito a la línea y una tabla de hechos de pago/deuda para las ventas con crédito. Los diez nombres y checksums de migraciones anteriores permanecen intactos. Las solicitudes de contado anteriores conservan su payload, respuesta y hechos originales; el crédito usa una nueva versión canónica con totales pagado/fiado.

La nueva clasificación no tiene cuenta de caja ni medio de pago ficticios. Las restricciones validan cliente, líneas, sumas enteras, venta publicada, cobro parcial y saldo por cobrar. La aplicación comprueba existencias, capacidades monetarias, identidad de solicitudes y cronología antes de confirmar.

## Verificación

- **601 pruebas aprobadas** en la suite completa, sin fallos; tres omitidas por permisos de enlaces no disponibles en el host.
- **38 casos nuevos**: 18 de almacenamiento, seis de restricciones SQL, cinco de controlador, ocho de formularios y uno de migración v10 con respaldo. Incluyen deuda total/mixta, producto repetido entre formas de pago, importes cero, cobro posterior, rollback al final de la operación, competencia por stock, recuperación al reabrir, respuesta incierta, identidades reservadas e inmutabilidad.
- Capacidad de cartera calculada con enteros exactos y considerando el saldo agregado anterior. La confirmación vuelve a comprobarla para impedir que dos solicitudes preparadas excedan el rango permitido.
- Análisis limpio, 18 archivos Dart modificados con formato limpio y revisión independiente sin hallazgos pendientes. Los diez nombres y checksums publicados se compararon contra la entrega anterior.
- Respaldo manual v10 verificado antes de actualizar. El ensayo aislado y la apertura real a v11 conservaron todos los registros previos de las **48 tablas**, saldos, inventario y documentos comerciales. Solo se agrega la fila de migración y las columnas nuevas con sus valores iniciales; la nueva tabla de hechos queda vacía. Integridad correcta y cero violaciones FK. Los respaldos automáticos del ensayo y de la app coinciden en registros con el manual.

## Entrega local

El bundle Windows final **0.13.0+18**, sin configuraciones de prueba, está publicado en **Iniciar Valinor Sanctum.cmd**, con copia versionada y ZIP 0.13.0. Sus 17 archivos se compararon por SHA256 entre ZIP, ruta estable y copia versionada; no contienen bases, perfiles ni snapshots privados.

La app final abrió y mostró la navegación mediante accesibilidad. El helper rechazó un clic por índice por su caché de accesibilidad y no se completó el recorrido nativo de los formularios nuevos; su comportamiento se verificó en los widgets. No se capturaron imágenes ni se enviaron operaciones de prueba en el perfil del propietario. La ventana se dejó abierta para su uso.

Evidencia: [quick-credit.json](evidence/quick-credit.json).
