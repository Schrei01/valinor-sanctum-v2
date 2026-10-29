# Producción1.1.0

Instalador Windows x64 **1.1.0+51**, con las funcionalidades de Desarrollo0.33.0 y esquema20. Incluye inversión en Compras y Eventos, devoluciones al propietario, historial de Tesorería unificado, el total de Deudores y su detalle completo en Reportes. Tesorería utiliza Registrar devolución para las inversiones y ya no muestra Pagos a proveedores.

## Instalación y archivos

Ejecutar `dist/Valinor-Sanctum-1.1.0-Produccion-Instalar.exe`. Actualiza la instalación por usuario y sus accesos **Valinor Sanctum - Producción**. Se identifica como Producción en ventana, interfaz, metadatos y accesos; el pie muestra1.1.0. El instalador requiere cerrar la edición instalada que esté actualizando.

La aplicación lee `%USERPROFILE%\Documents\sanctum2.sqlite3` y `legacy-treasury.json`. En el equipo actual corresponde a `C:\Users\ValinorPC\Documents`. Se conservan esos archivos; no hay que copiar la base de desarrollo. Si falta la base, crea una nueva con Valinor, COP y0 decimales. El paquete no contiene bases, perfiles ni historiales privados.

La base existente se actualiza al abrir la aplicación. Antes de migrar, SQLite crea y verifica un respaldo en `Documents\ValinorSanctum2-backups`. La migración18→20 conserva los hechos anteriores; reclasifica una sola vez el saldo negativo preexistente de Caja mayor como Inversión por recuperar positiva, sin mover Caja ni Nequi. Los eventos existentes conservan su financiación anterior. Una base incompatible o dañada se conserva y muestra un error.

El instalador, la actualización y la desinstalación conservan los datos de Documentos. La entrega del instalador no ejecuta una instalación operativa ni migra la base real por anticipado.

## Separación de ediciones

Se conserva íntegra la última versión de Desarrollo0.33.0 en `dist/ValinorSanctum2`, su ZIP y `Iniciar Valinor Sanctum.cmd`. La entrega productiva está en `dist/ValinorSanctum2-Produccion`, su ZIP termina en `-production-windows-x64.zip` y el instalador lleva Produccion en el nombre. La limpieza retira las versiones anteriores de la misma edición.

El código mantiene `pubspec.yaml` en la versión de desarrollo. Producción se compila expresamente con `--build-name=1.1.0 --build-number=51 --dart-define=SANCTUM_ENV=installed`, y los scripts de paquete e instalador reciben `-Version 1.1.0`. El selector de perfiles de desarrollo no modifica la ruta de producción.

## Verificación

Resultados de la entrega en [la evidencia sanitizada](evidence/production-110.json). Los archivos de ensayo, huellas, copias de datos y resultados privados quedan en `tmp`, fuera de Git y de la distribución. La revisión de los archivos operativos se realiza en solo lectura; las migraciones y los arranques de prueba utilizan copias en usuarios aislados.

- 32 pruebas de configuración, rutas, almacenamiento e interfaz aprobadas; tres omitidas por permisos de enlaces del host. Dos renders productivos inspeccionados a1280 y400 píxeles. Análisis limpio y formato208 archivos sin cambios. El CI completo del backend0.33 terminó correctamente en40926997905; esta entrega no repite una suite completa local.
- El ensayo18→20 preservó los registros de las69 tablas anteriores, Caja y Nequi, con la única reclasificación financiera prevista. La base final tiene72 tablas. Historial JSON conciliado con su apertura; integridad y claves foráneas correctas.
- Instalación nativa, apertura de base nueva y existente, rechazo de actualización abierta, reinstalación, reapertura y desinstalación aprobados en aislamiento, conservando base e historial. Se verificaron19 archivos instalados. El ensayo omite registro y accesos reales; utiliza las mismas rutas de código del instalador con destino privado.
- Un primer ensayo nativo de la base18 cerraba la ventana a los seis segundos, antes de finalizar la migración; el rollback conservó18. La reapertura se dejó terminar y se observó Ventas cargado, rótulo Producción y versión1.1.0 mediante accesibilidad. Se verificaron esquema20, todos los hechos históricos y el respaldo automático por contenido, también después del cierre. No se atribuye inspección visual nativa de capturas.
- ZIP, bundle e instalador coinciden; no incluyen datos privados. Desarrollo0.33, su launcher y los archivos reales de Documentos conservaron sus huellas. Producción1.0 se retiró de dist y la limpieza final no tiene pendientes. Solo quedó abierta la ventana de Desarrollo que ya tenía el propietario.
