# Eventos con inversión — Desarrollo 0.33.0

El costo fijo de un evento puede pagarse personalmente seleccionando **Inversión** en **Pagar costo fijo desde**. Aumenta el pasivo **Inversión por recuperar** y queda visible en el historial de Tesorería. Caja y Nequi conservan sus saldos. La devolución posterior utiliza **Registrar devolución**, con los mismos límites y trazabilidad de las inversiones realizadas desde Compras.

Los productos utilizados como premios conservan su descuento de inventario y costeo FIFO. No aumentan otra vez la inversión: su adquisición ya tuvo su propia financiación. El costo del evento sigue siendo el costo fijo más el costo de los productos, dividido entre el mínimo de asistentes para obtener el PU sugerido. Se conserva el PVP manual. Cualquier costo exige un mínimo positivo. Seleccionar Inversión con costo fijo cero no crea deuda.

## Persistencia y compatibilidad

Esquema20, sin tablas adicionales. `events.funding_mode` distingue `cash` de `investment`. La inversión usa el pasivo existente `investment:owner-payable`; no crea una cuenta monetaria ficticia ni un pago a proveedor. El asiento del propio evento acredita ese pasivo por el costo fijo. Los egresos monetarios de Reportes siguen representando salidas efectivas; el costo del evento se reconoce una sola vez, y las devoluciones de inversión siguen separadas.

La migración conserva las filas anteriores de eventos, productos, asignaciones FIFO y solicitudes pendientes, con `funding_mode=cash` para los eventos existentes. Reconstruye el grafo con claves foráneas activas y repone sus restricciones, incluida la prohibición de consumir Pasadía como premio. Mantiene intactas las migraciones1–19 y su verificación. El respaldo SQLite anterior se verifica por contenido antes de migrar.

La confirmación es atómica e idempotente. Comprueba el pasivo activo, límites enteros y orden cronológico tanto en la aplicación como al publicar el documento en SQL. Un fallo revierte dinero, inversión, productos y asiento juntos. Vender inscripciones, desactivar el evento o reintentar su creación no repite la inversión.

## Entrega y verificación

Edición Development0.33.0+50, portable, con almacenamiento propio de desarrollo. Producción1.0.0 y su base de Documentos no se actualizan. La entrega sustituye la edición anterior de desarrollo y conserva la última productiva. El acceso raíz abre `dist/ValinorSanctum2`.

Las comprobaciones finales y sus resultados se registran en [la evidencia sanitizada](evidence/events-investment-033.json). Los respaldos, rutas privadas, datos reales y capturas sintéticas de revisión se conservan fuera de Git y del ZIP.

Pasaron128 pruebas de aplicación de Eventos, Inversión, Reportes, Tesorería, base de datos, migraciones y navegación, junto con dos renders sintéticos. Tras ajustar el texto del formulario se repitieron ocho pruebas de interfaz y los dos renders, inspeccionados a1280 y400 píxeles. Análisis limpio y formato208 archivos sin cambios. No se repitió la suite completa.

El ensayo privado y la migración activa19→20 conservaron todos los valores anteriores de las72 tablas, con respaldos manual y automático comprobados por contenido. Se repitió la comprobación en solo lectura después de abrir el ejecutable. No se ingresaron operaciones comerciales de prueba en la base activa. ZIP y bundle coinciden en19 archivos; no incluyen datos privados. Los21 archivos de la entrega productiva, su base e historial de Documentos y el selector/historial de desarrollo conservan sus huellas. La versión anterior de desarrollo se retiró y la última de Producción se mantuvo. La ventana nativa quedó abierta y respondió con título Desarrollo; la revisión visual fue sobre renders sintéticos, sin atribuir inspección visual nativa.
