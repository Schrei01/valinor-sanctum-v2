# GitHub Actions: versión del SDK y cartera de ejemplo — 0.23.1

## Corrección de CI

El checkout superficial de Flutter descargaba únicamente el SHA, sin etiquetas. Flutter calcula su versión de framework desde las etiquetas Git; ese checkout se identificaba como `0.0.0-unknown` y el resolvedor rechazaba la dependencia de pruebas por su versión mínima de Flutter.

El workflow descarga la etiqueta oficial **3.47.7**, comprueba que apunta al commit fijado `abaf9c523780a608bd46686fd5e53740a07077f8` y después hace checkout de ese SHA. Comprueba además `frameworkVersion` y `frameworkRevision` con `--version --machine` antes de resolver dependencias. No se actualizan paquetes ni se relaja `--enforce-lockfile`.

Una prueba con un repositorio superficial nuevo reprodujo la ausencia de etiquetas y verificó que descargar la etiqueta devuelve exactamente la versión y revisión fijadas. La resolución local del lockfile terminó correctamente. La nueva ejecución remota se genera al subir este commit y puede consultarse en [Windows checks](https://github.com/Schrei01/valinor-sanctum-v2/actions/workflows/windows.yml).

## Interfaz

Se retira el anuncio del comando reservado de los textos normales del catálogo y del resumen público del README. La función y su alcance siguen disponibles, sin botones ni avisos que enseñen a invocarla. No se añaden mecanismos de autenticación.

## Datos de ejemplo autorizados

El propietario pidió repartir la cartera actual entre dos titulares de ejemplo. Se usó la API existente de Deudores con `PreviousDebtSource.includedInLegacy`: una asignación por el monto fijo solicitado y otra por el saldo restante. Los documentos se identifican como `synthetic`, con origen `legacy`. No se fabrican ventas ni se añade deuda al total, y no se realizan cobros.

Primero se comprobó sobre una copia privada, incluyendo un reintento completo sin cambios en ninguna fila. Luego se respaldó la base activa con la app cerrada y se aplicó la distribución solicitada. Todas las filas anteriores se conservan; Caja, Nequi, Caja mayor, inventario, ventas y cartera total no cambian. Esquema 16 y 68 tablas, sin migración, integridad correcta y cero FK. Los nombres, importes, planes, base y respaldos permanecen locales fuera de Git y del ZIP.

## Verificación

- 16 pruebas enfocadas aprobadas (catálogo/comando y Deudores).
- Formato de `lib`, `test` y `tool`: 186 archivos revisados sin cambios.
- Análisis sin incidencias y resolución de dependencias bloqueadas correcta.
- Release Windows sin overrides, ejecutable/pie 0.23.1+37/0.23.1; ZIP, estable y versionada idénticos en 17 archivos, sin datos privados; anteriores limpiados.
- Respaldo verificado en `backups/ci-debt-20261027`; conservación de filas previas y saldos, origen de la reasignación y reintento verificados mediante consultas independientes.

Evidencia sanitizada: `docs/evidence/ci-debt.json`. La comprobación de la ejecución remota de este commit se realiza después de publicarlo; no confundir las comprobaciones locales con un resultado de GitHub todavía pendiente al crear el commit.
