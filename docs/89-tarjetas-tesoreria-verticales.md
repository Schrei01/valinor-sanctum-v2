# Tarjetas de Tesorería — Desarrollo 0.40.2

Todas las tarjetas de Tesorería presentan el título arriba y el importe debajo, alineados a la izquierda, como Inversión por recuperar. Incluye Caja, Nequi, Caja mayor, Deudas, los tres totales y las otras cuentas monetarias.

Se usa una opción de presentación vertical del componente `FinancialTotal` exclusivamente en estas tarjetas. Conserva sus colores y tipografía; los otros usos del componente mantienen su distribución anterior. No hay cambios en cálculos, movimientos, permisos, límites ni esquema 23.

Validación: 34 pruebas existentes de interfaz de Tesorería, operaciones, navegación y apertura aprobadas; una ejecución adicional de la variante estrecha aprobada. Se inspeccionaron capturas sintéticas de 1400 y 400 píxeles de ancho. No se añadieron pruebas financieras ni se repitió la suite completa por este ajuste de presentación.

El CI completo del parche anterior quedó verde en los commits bf24854 y eb1d103 (runs 41938047486 y 41939201492). El CI del nuevo commit se consulta después de subirlo; ese resultado anterior no sustituye su validación.

Desarrollo portable **0.40.2+71** usa la base independiente `data/development/valinor/sanctum2.sqlite3` y se abre con **Iniciar Valinor Sanctum.cmd**. Producción permanece en 1.4.2. La evidencia final de entrega está en [treasury-stacked-0402.json](evidence/treasury-stacked-0402.json).

Entrega verificada: análisis limpio, formato de 217 archivos sin cambios, Release compilada y ZIP/estable de 19 archivos idénticos sin datos privados. Desarrollo se respaldó antes de publicar y conserva definiciones y filas de sus 74 tablas después de abrir; integridad y claves foráneas correctas, sin operaciones sintéticas en la base activa. Coinciden las 43 huellas de archivos productivos, instalación vigente y selector/JSON de Desarrollo. Se retiró la portable anterior, sin limpieza pendiente. Desarrollo quedó abierta y responde; Producción sigue abierta y su base no fue consultada.
