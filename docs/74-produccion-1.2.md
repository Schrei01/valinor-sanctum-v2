# Producción 1.2.0

Instalador Windows x64 **1.2.0+54**, con las funcionalidades de Desarrollo 0.35.0 y esquema 21. Incorpora las cuentas nuevas primero, correcciones de existencias con signo, avisos informativos en verde claro y bloqueos en rojo claro. En Ventas, los saldos y el desglose de pagos aparecen debajo de los controles de cobro y conservan la posición de Registrar venta.

Ejecutar `dist/Valinor-Sanctum-1.2.0-Produccion-Instalar.exe` con la aplicación productiva cerrada. Actualiza la instalación y los accesos por usuario. La ventana, interfaz, metadatos y accesos identifican Producción; el pie indica 1.2.0.

Utiliza `%USERPROFILE%\Documents\sanctum2.sqlite3` y `legacy-treasury.json`; en este equipo, `C:\Users\ValinorPC\Documents`. No hay que reemplazarlos por los de desarrollo. Si falta la base, crea una nueva con Valinor, COP y cero decimales. El instalador y el ZIP no contienen datos privados.

Al abrir una base de esquema 20, la app crea y verifica un respaldo en `Documents\ValinorSanctum2-backups` antes de migrar al 21. Conserva los datos históricos; añade el registro de creación independiente de las cuentas nuevas y el soporte de correcciones positivas de inventario. La instalación, actualización y desinstalación conservan los datos de Documentos.

La entrega conserva Desarrollo 0.35.0 en `dist/ValinorSanctum2`, su ZIP y `Iniciar Valinor Sanctum.cmd`. La edición productiva utiliza `dist/ValinorSanctum2-Produccion` y su propio instalador y ZIP. Solo se retiran las entregas productivas anteriores.

El código mantiene `pubspec.yaml` en 0.35.0+53. Esta entrega se compila con `--build-name=1.2.0 --build-number=54 --dart-define=SANCTUM_ENV=installed`; los scripts de paquete e instalador reciben `-Version 1.2.0`.

Las verificaciones están en [la evidencia sanitizada](evidence/production-120.json). La base operativa solo se lee para obtener un snapshot consistente; las migraciones y los arranques de ensayo usan copias privadas dentro del proyecto. La entrega del instalador no ejecuta una actualización operativa ni cierra las ventanas del propietario.

Pasaron 56 pruebas de configuración, almacenamiento, cuentas, inventario e interfaz; tres omitidas por permisos de enlaces del host. Dos renders productivos inspeccionados a 1280 y 400 píxeles. Análisis limpio y formato de 213 archivos sin cambios. No se repitió la suite general local.

El snapshot operativo y el JSON coinciden con la apertura registrada. La migración privada 20→21 conserva todos los valores anteriores de las 72 tablas y deja los nuevos campos históricos en NULL y la tabla de entradas por corrección vacía. La base final tiene 73 tablas, integridad correcta y cero violaciones de claves foráneas. El respaldo automático se verificó por contenido, también durante el arranque del ejecutable productivo.

El primer verificador de arranque no pudo observar el título ni cerrar una ventana oculta mediante CloseMainWindow. Se corrigió el ensayo: comprobar identidad del PE, respuesta del proceso y datos de la copia, y detener únicamente el proceso de prueba después de comprobarlos. La repetición pasó. No se atribuye observación del título ni inspección visual nativa; la revisión visual usa renders sintéticos.

Instalación, reapertura, bloqueo de actualización con la app abierta, reinstalación con base/JSON existentes y desinstalación pasaron en un destino aislado. Se comprobaron 19 archivos instalados y la conservación de datos. Ese modo de ensayo omite el registro y los accesos reales. Cinco pruebas de limpieza y seis comprobaciones de separación de ediciones aprobadas.

ZIP, bundle y payload del instalador coinciden en 19 archivos sin datos privados. La última Desarrollo y su acceso, selector e historial, junto a los archivos de la instalación productiva existente, conservaron 43 huellas. Se retiraron el ZIP e instalador productivos anteriores de dist; la instalación operativa sigue sin actualizar y su ventana fue preservada.

Un arranque nativo adicional sin base creó Valinor/COP/0 en los Documentos del usuario de prueba, esquema 21 e integridad correcta. Tras detener el proceso de migración privado se repitió la comprobación de datos históricos, JSON y respaldo con resultado correcto. La limpieza final no tiene entregas obsoletas pendientes.
