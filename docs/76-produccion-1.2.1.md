# Producción 1.2.1

Instalador Windows x64 **1.2.1+56**, con las funcionalidades de Desarrollo 0.36.0. En Deudores, la lista y su búsqueda muestran solo personas con deuda pendiente. Registrar persona sugiere nombres anteriores, incluidos saldados y bloqueados, y permite consultar su cuenta original sin crear otra ni modificar su saldo o habilitar fiado. Los registros y el historial permanecen guardados. [Detalle del cambio](75-deudores-saldados-sugerencias.md).

Cerrar la aplicación productiva y ejecutar `dist/Valinor-Sanctum-1.2.1-Produccion-Instalar.exe`. Actualiza la instalación y sus accesos por usuario. La interfaz, ventana, metadatos y accesos identifican Producción; el pie indica 1.2.1.

Continúa usando `%USERPROFILE%\Documents\sanctum2.sqlite3` y `legacy-treasury.json`; en este equipo, `C:\Users\ValinorPC\Documents`. No hay que reemplazar esos archivos por los de desarrollo. Instalación, actualización y desinstalación conservan los datos. Si falta la base, crea Valinor/COP/0. El paquete no contiene bases ni historiales privados.

El esquema sigue en 21 con 73 tablas. Una base ya actualizada a 21 no necesita migración por este cambio. El motor conserva el respaldo automático previo cuando se abre una base compatible de versión anterior.

Se conserva Desarrollo 0.36.0 en `dist/ValinorSanctum2`, su ZIP y `Iniciar Valinor Sanctum.cmd`. La edición productiva utiliza `dist/ValinorSanctum2-Produccion` y su propio ZIP e instalador. Se retiran las entregas productivas anteriores de dist; la entrega del instalador no ejecuta una instalación operativa.

El código mantiene `pubspec.yaml` en 0.36.0+55. Compilación con `--build-name=1.2.1 --build-number=56 --dart-define=SANCTUM_ENV=installed`; scripts de paquete e instalador con `-Version 1.2.1`.

La evidencia sanitizada está en [production-121.json](evidence/production-121.json). Verificación de datos mediante snapshot consistente de solo lectura; arranques e instalación de ensayo sobre copias privadas. Datos, huellas y capturas locales permanecen fuera de Git y del paquete.

Pruebas del 30/10/2026: 43 casos de aplicación y dos renders productivos aprobados e inspeccionados a 1280/400; tres omitidos por permisos de enlaces del host. Análisis limpio y formato de 213 archivos sin cambios. Snapshot y arranque nativo conservaron los valores de las 73 tablas y el JSON, con integridad correcta y cero violaciones de claves foráneas. La base ya estaba en 21 y no hubo migración.

Instalación, reapertura, rechazo de actualización abierta, reinstalación y desinstalación en aislamiento conservaron base e historial; 19 archivos instalados verificados. El modo de ensayo omite registro y accesos reales. Un arranque nativo sin base creó Valinor/COP/0. Las comprobaciones nativas usaron procesos ocultos propios, detenidos después de verificar datos; no se atribuye observación visual ni del título nativo.

ZIP, bundle y payload del instalador coinciden en 19 archivos sin privados. En la publicación coincidieron 43 huellas de Desarrollo, su acceso/selector/JSON y la instalación productiva anterior. Se retiraron el ZIP e instalador productivos anteriores. La entrega no ejecutó una instalación operativa.
