# Deuda al registrar — Desarrollo 0.52.0

Tras la aclaración del propietario, el incremento corresponde a **Ventas**. En el bloque informativo de la cuenta se añade **Deuda al registrar**, sumando el saldo actual de la persona seleccionada y el importe nuevo asignado a Deudas.

Ejemplo: debe COP10.000 y la cuenta suma COP8.000, con COP5.000 pagados y COP3.000 a Deudas; se muestran COP13.000 como deuda al registrar. El importe usa la porción a Deudas calculada por el controlador, por lo que excluye Efectivo, Transferencia y cobertura con bono. Se actualiza al cambiar la persona o el consumo. Se muestra con persona activa y nuevo fiado, una vez revisada la división si hubo cambios.

Se conserva la deuda actual y el resumen de cobrado/fiado. El texto queda debajo de las acciones y no desplaza el botón Registrar venta. Es una proyección: no registra operaciones ni modifica deuda, dinero, stock, validaciones ni esquema29.

Las pruebas existentes de interfaz cubren fiado completo y pago mixto con saldo previo, verificando el total y que la proyección no prepara ni registra ventas. Se comprueban además los flujos de división y membresías. Desarrollo se entrega para revisión mediante PR a main; Producción1.10.0 y su base permanecen independientes.

Se aprobaron12 pruebas seleccionadas, con las dos de membresías repetidas para verificar expresamente la exclusión del bono. Análisis limpio, formato250 sin cambios y Release correcta. Portable0.52.0+91 publicado y abierto para revisión; se retiró el ZIPDev anterior y se preservaron39 huellas de la distribución/instalación productiva. [Evidencia](evidence/sale-debt-total-052.json).
