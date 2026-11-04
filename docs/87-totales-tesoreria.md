# Totales de Tesorería — Desarrollo 0.40.0

Tesorería muestra tres tarjetas juntas debajo de los saldos individuales, con el mismo estilo de totales:

- **Total disponible** = Caja + Nequi + Caja mayor.
- **Total potencial** = Total disponible + Deudas de clientes.
- **Total** = Total potencial − Inversión por recuperar.

Se conservan los signos: una Caja mayor negativa resta y el Total puede ser negativo. Las otras cuentas monetarias siguen visibles aparte y no se incluyen en estas fórmulas. Deudas incluye la cartera anterior todavía pendiente, sin duplicarla. Inversión es su saldo pendiente de devolución.

Es una consulta de los saldos actuales, sin asientos nuevos ni cambios a las reglas para pagar desde una cuenta. No amplía Reportes ni modifica movimientos existentes. Los cálculos usan sumas exactas y rechazan desbordamientos monetarios.

La entrega portable **Desarrollo 0.40.0+69** conserva el esquema 23 y sus 74 tablas. Se abre mediante **Iniciar Valinor Sanctum.cmd** y usa `data/development/valinor/sanctum2.sqlite3`. Producción permanece en 1.4.2, con su instalador y datos separados.

Las pruebas verifican los tres importes, Caja mayor positiva y negativa, Total negativo, desbordamiento, actualización al entrar a Tesorería y conciliación de operaciones existentes. Los ensayos y capturas usan datos sintéticos. Evidencia de publicación y verificaciones efectivamente completadas: [treasury-totals-040.json](evidence/treasury-totals-040.json).

## Verificación

80 pruebas distintas aprobadas entre ejecuciones de los módulos afectados: la primera ejecución pasó 77 y detectó una expectativa antigua del shell que excluía Caja mayor. Tras actualizarla, esa prueba y dos comprobaciones nuevas de signo/desbordamiento pasaron. Un filtro inicial de repetición no seleccionó pruebas; se corrigió y se ejecutaron las tres. No se repitió toda la suite general.

Se inspeccionaron dos capturas sintéticas, de 1400 y 400 píxeles de ancho; la variante estrecha también se ejecutó por separado. No se realizó inspección visual nativa. Los archivos privados permanecen en `tmp` y `backups`, fuera de Git y del paquete.

Análisis sin incidencias y formato de 217 archivos sin cambios. Se creó un respaldo de Desarrollo antes de reemplazar su ejecutable; no se requieren cambios de esquema.

Release y portable publicadas: ZIP y bundle estable contienen los mismos 19 archivos, sin datos privados. Se retiró el ZIP anterior de Desarrollo; limpieza sin pendientes. Al abrir la nueva app se conservaron las definiciones y filas de las 74 tablas, con integridad y claves foráneas correctas. Ventana de Desarrollo abierta y responde. Las 43 huellas de archivos productivos, instalación vigente y selector/JSON de Desarrollo coinciden; la ventana productiva sigue abierta y no se consultó su base.
