# Desarrollo 0.32.1: Tesorería sin pagos a proveedores

Se retira el panel **Pagos a proveedores** de Tesorería y su carga automática
desde la aplicación. Para devolver dinero al propietario se utiliza
**Registrar devolución**, con el flujo de inversión de la 0.32.

Se conservan los registros de compras, pagos y movimientos históricos. El motor
de pago a proveedores continúa liquidando las compras normales dentro de su
transacción; no se elimina esa contabilidad ni se modifica el esquema 19.
El componente de interfaz anterior solo se ejercita de forma independiente en
sus pruebas de compatibilidad; no tiene acceso desde la aplicación.

42 pruebas de widgets aprobadas: Tesorería, navegación, devoluciones, compatibilidad
del componente anterior y entorno. Se actualizaron las expectativas que antes
abrían el panel retirado. Análisis limpio. No se necesita una migración ni una
suite financiera completa nueva para retirar este acceso.

Release **0.32.1+49** publicada en el acceso raíz de Desarrollo y dejada abierta;
proceso responde y título nativo Desarrollo comprobado, sin inspección visual
nativa nueva. ZIP/bundle coinciden en 19 archivos, sin datos privados. Se retiró
el ZIP anterior de Desarrollo; el dry-run final no tiene pendientes. Los 21
archivos de la entrega productiva mantienen su SHA256.

Lecturas de solo consulta antes y después del arranque comprobaron los mismos
datos y definiciones en las 72 tablas de Desarrollo, esquema 19, integridad
correcta y cero violaciones de claves foráneas. No se hicieron operaciones de
negocio en la base del propietario. Formato: 207 archivos Dart sin cambios.
Evidencia sanitizada en `docs/evidence/treasury-0321.json`.
