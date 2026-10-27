# Personas de Deudores en las cuentas de Ventas — 0.26.0

El campo **Cuenta** permite escribir un nombre libre para una mesa o buscar y seleccionar una persona registrada en Deudores. El botón de persona abre el listado completo de las personas habilitadas para fiar, con su saldo pendiente. La selección está disponible antes de agregar productos o elegir Deudas.

Elegir una persona llena el nombre de la cuenta y guarda su identificador. Todas las líneas marcadas Deudas de esa cuenta pertenecen a ese titular. Las líneas de Efectivo entran a Caja y las de Transferencia a Nequi; no aumentan la deuda del titular. Se conserva una persona por cuenta, el guardado automático y la posibilidad de abrir varias cuentas independientes.

Se retiró el selector separado que antes aparecía solo al elegir Deudas. Al escribir manualmente otro nombre se elimina la vinculación anterior, evitando que una cuenta renombrada cargue deuda a una persona que ya no está indicada. Escribir un nombre por sí solo no asigna un deudor: se debe elegir una sugerencia o usar el listado. Deudas sigue exigiendo selección explícita; las personas bloqueadas no se ofrecen para nuevas asignaciones.

Las cuentas y solicitudes anteriores conservan su titular e historia. Los campos quedan bloqueados durante preparación o recuperación incierta. No se modifican esquemas, medios de pago, contabilidad ni hechos confirmados: el reparto atómico de ventas mixtas ya existía y se reutiliza.

## Verificación y entrega

- 59 pruebas finales aprobadas, incluidas búsqueda/selección por teclado o listado, persistencia, cuentas independientes, retirada de titular al renombrar, ventas mixtas, bloqueo de operaciones inciertas y reintentos sin duplicación.
- Una prueba de controlador con SQLite real parte de dos personas con deuda previa. Comprueba que la parte fiada aumenta solo el saldo de la persona elegida, Caja y Nequi reciben sus importes pagados y el reintento conserva un único asiento/venta.
- Tres casos de render sintético y cuatro imágenes inspeccionadas: selector y venta mixta, con anchos 1366, 620 y 400 px. El titular y los tres medios de pago siguen visibles; las ventanas estrechas mantienen desplazamiento vertical.
- Análisis limpio y formato de 189 archivos verificado, sin cambios pendientes.

- Release Windows 0.26.0+40 sin overrides publicado, con pie 0.26.0. ZIP, estable y copia versionada coinciden en 18 archivos, sin datos privados; anteriores limpiados.
- Respaldo consistente verificado en `backups/named-sales-20261027`. Esquema 16 y 68 tablas: todas las filas y definiciones activas idénticas antes/después de publicar y abrir; integridad correcta y cero FK.
- App abierta y respondiendo. Tras cargar Ventas, accesibilidad nativa observó Versión 0.26.0 y el botón Elegir persona de Deudores. Sin crear ventas ni seleccionar personas sobre la activa.

Pruebas y renders con datos sintéticos; ninguna venta, deuda ni movimiento de prueba sobre la base activa. Evidencia sanitizada en `docs/evidence/named-sales.json`. CI del commit nuevo se comprueba después de subirlo; las verificaciones anteriores son locales.
