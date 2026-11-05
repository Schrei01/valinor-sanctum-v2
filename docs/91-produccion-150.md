# Producción 1.5.0

Edición instalable con las funcionalidades de Desarrollo 0.40.2:

- Compras permite recuperar el PVP anterior con **Usar valor**.
- Tesorería muestra Disponible = Caja + Nequi + Caja mayor; Potencial = Disponible + Deudas; Total = Potencial − Inversión por recuperar.
- Todas las tarjetas de Tesorería presentan el importe debajo del título.
- Los agregados fuera de rango no impiden consultar saldos válidos; el cálculo neto valida su resultado final exacto.

La interfaz productiva indica **Producción 1.5.0**. El instalador se genera con versión `1.5.0+72`, mientras el código de Desarrollo conserva `0.40.2+71` y su última distribución independiente.

## Datos y actualización

El programa instalado usa `%USERPROFILE%\Documents\sanctum2.sqlite3` y `legacy-treasury.json`. Si la base no existe, crea Valinor/COP/0 decimales. El esquema sigue en 23, con 74 tablas; una base ya actualizada a 23 no requiere migración. Las bases anteriores compatibles se actualizan con el respaldo automático habitual.

El paquete no incluye bases ni historial privado. La instalación y desinstalación conservan los datos. Para instalar una actualización, el propietario debe cerrar Producción antes de ejecutar el instalador. La preparación de esta entrega no instala operativamente ni modifica la base real.

## Validación y procedencia

La base operativa se abrió exclusivamente en solo lectura para obtener una copia privada consistente. Se verificaron esquema 23, integridad, claves foráneas, correspondencia del JSON y conservación de todos los valores de las 74 tablas al abrir la copia con el código actual. Los ensayos del ejecutable e instalador se realizan con Documentos aislados dentro de `tmp`.

La publicación sigue el flujo aprobado: rama `codex/produccion-1-5-0`, Pull Request, CI completo aprobado e integración antes de entregar el instalador definitivo. La petición de publicar la última versión confirma la conformidad del propietario con las funciones de Desarrollo 0.40.2 y autoriza la integración necesaria de este PR cuando pasen sus comprobaciones. El PR de documentación del flujo se conserva independiente para la revisión que quedó pendiente.

El PR de publicación registra el resultado final del ensayo de instalación, reapertura, reinstalación, rechazo de actualización mientras el programa está abierto, desinstalación, conservación de datos, archivos y hashes de los artefactos. Los resultados de una ejecución todavía pendiente no se consideran aprobados.

Antes de abrir el PR se aprobaron 12 pruebas específicas de apertura, almacenamiento instalado y rótulos de edición, además del análisis y formato de 217 archivos sin cambios. La suite completa se ejecuta como check requerido del PR; su aprobación es condición de integración.

Artefacto esperado: `dist/Valinor-Sanctum-1.5.0-Produccion-Instalar.exe`. Conservar la última portable de Desarrollo al publicar y limpiar solo los artefactos productivos anteriores después de verificar esta entrega. No se requiere una nueva versión portable de Desarrollo.
