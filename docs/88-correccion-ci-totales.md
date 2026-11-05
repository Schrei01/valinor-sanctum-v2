# Corrección de CI — Desarrollo 0.40.1

La suite completa de [GitHub Actions del commit 06883ea](https://github.com/Schrei01/valinor-sanctum-v2/actions/runs/41934323250) aprobó formato y análisis, pero terminó con 853 pruebas aprobadas y dos fallos:

- `quick_sales_credit_store_test`: una venta válida deja Caja en 1 y deuda en el máximo admitido. Cada saldo es válido, pero su suma potencial supera el límite monetario. La validación anticipada añadida en `SqliteTreasuryStore.load` rechazaba la lectura completa del saldo.
- `treasury_operations_test`: el total esperado tras un gasto todavía excluía Caja mayor, cuyo saldo sintético es −200,00. El importe correcto con la fórmula nueva es 1.176,55.

Se retira la validación anticipada de los nuevos totales derivados al leer Tesorería. Sus getters siguen usando cálculo exacto y comprobación de rango. Si Potencial o Total exceden el límite, solo su tarjeta indica **Fuera de rango**; los saldos y demás tarjetas siguen consultables. Total calcula directamente Disponible + Deudas − Inversión, de modo que una suma intermedia excesiva no invalida un resultado final representable. No se alteran los límites de ventas, cobros, deudas ni asientos.

La expectativa del gasto incluye ahora Caja mayor. Se añade una comprobación de interfaz para mostrar saldos válidos y Total neto válido cuando Potencial excede el rango, y se amplía la prueba existente del cálculo neto exacto.

La corrección es Desarrollo **0.40.1+70**, esquema 23, sin migración. Producción permanece en 1.4.2. Bases y registros descargados para diagnóstico se conservan privados en `tmp` y `backups`.

Validación local: 63 pruebas aprobadas de ventas a crédito, operaciones de Tesorería, saldos, interfaz y apertura. Incluye los dos fallos del registro de CI y el nuevo caso de interfaz con Potencial excesivo y neto válido. Formato de 217 archivos sin cambios y análisis sin incidencias. No se ejecutó otra suite completa local; GitHub la ejecutará de nuevo al subir el parche.

Release compilada y ZIP generado con 19 archivos sin bases privadas. [Evidencia](evidence/ci-totals-0401.json). El publicador del acceso estable requiere cerrar la edición de Desarrollo que Windows tiene en uso; no cerrar Producción ni modificar sus datos.

Tras la confirmación del propietario, se respaldó Desarrollo y se publicó la 0.40.1 en el acceso habitual. Al reabrir conserva las definiciones y filas de sus 74 tablas, integridad correcta y ninguna violación de claves foráneas. El ZIP y el bundle estable contienen los mismos 19 archivos; se retiró el ZIP anterior y no quedó limpieza pendiente. Coinciden las 43 huellas de archivos productivos, instalación vigente y selector/JSON de Desarrollo. La ventana de Desarrollo quedó abierta y responde; Producción siguió abierta, sin consultar su base. No se registraron negocios de prueba ni se realizó inspección visual nativa.
