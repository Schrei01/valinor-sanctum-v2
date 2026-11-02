# Producción 1.3.0

Instalador Windows x64 **1.3.0+60**, con las funcionalidades de Desarrollo 0.37.2. Reportes incorpora Abonos de deudores dentro del comprobante, debajo de Transferencias entre cuentas: únicamente los totales de Efectivo y Transferencia del rango seleccionado. No muestra detalle individual de esos abonos ni los cuenta como ventas nuevas. Deudores al cierre conserva su información. [Resumen por medio](79-abonos-resumen-por-medio.md).

Cerrar la aplicación productiva y ejecutar `dist/Valinor-Sanctum-1.3.0-Produccion-Instalar.exe`. Actualiza la instalación y sus accesos por usuario. Interfaz, ventana, metadatos y accesos identifican Producción; el pie indica 1.3.0.

Usa `%USERPROFILE%\Documents\sanctum2.sqlite3` y `legacy-treasury.json`; en este equipo, `C:\Users\ValinorPC\Documents`. No es necesario reemplazar estos archivos. Instalación, actualización y desinstalación conservan los datos. Si falta la base, crea Valinor/COP/0. El paquete no contiene bases ni historiales privados.

El esquema sigue en 21 con 73 tablas. Una base en ese esquema no requiere migración por este incremento; el motor conserva los respaldos automáticos previos al abrir formatos anteriores compatibles.

Se conserva Desarrollo 0.37.2 en `dist/ValinorSanctum2`, su ZIP y `Iniciar Valinor Sanctum.cmd`. Producción utiliza `dist/ValinorSanctum2-Produccion` y su ZIP e instalador propios. La limpieza retira entregas productivas anteriores. Entregar el instalador no ejecuta una instalación operativa ni cierra las ventanas del propietario.

El código mantiene `pubspec.yaml` en 0.37.2+59. Compilación con `--build-name=1.3.0 --build-number=60 --dart-define=SANCTUM_ENV=installed`; scripts de paquete e instalador con `-Version 1.3.0`.

Ver [evidencia sanitizada](evidence/production-130.json). Los ensayos de instalación y arranque usan copias privadas; la fuente operativa solo se abre en lectura para obtener un snapshot consistente. Datos, huellas y capturas locales quedan fuera de Git y de la distribución.

Pasaron 74 pruebas de aplicación sobre reportes, rangos, abonos, interfaz, configuración y almacenamiento instalado, más dos renders productivos inspeccionados a 1280/400. Tres pruebas de enlaces omitidas por permisos del host. Análisis limpio y formato de 214 archivos sin cambios. No se repitió la suite general.

La fuente estaba en esquema 21 y no requirió migración. Snapshot y arranque nativo privado conservaron los valores de las 73 tablas y el JSON, también después de detener el proceso; integridad correcta y cero violaciones de claves foráneas. El arranque sin base creó Valinor/COP/0 en los Documentos del usuario de prueba.

Instalación, reapertura, rechazo de actualización abierta, reinstalación y desinstalación aisladas conservaron base e historial. Se verificaron 19 archivos instalados. El modo de ensayo omite registro y accesos reales. Los procesos de prueba se ejecutaron ocultos y se detuvieron tras verificar los datos; no se atribuye observación del título ni revisión visual nativa.

ZIP, bundle y payload del instalador coinciden en 19 archivos sin privados. Se conservaron 43 huellas de Desarrollo, su ZIP/acceso/selector/JSON y la instalación productiva existente. La ventana de Desarrollo permanece abierta. Se retiraron el ZIP y el instalador productivos anteriores de dist y la limpieza quedó sin pendientes. La instalación operativa no se ejecutó.
