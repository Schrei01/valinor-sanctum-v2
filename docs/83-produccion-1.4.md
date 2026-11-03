# Producción 1.4.0

Instalador Windows x64 **1.4.0+63**, con las funcionalidades de Desarrollo 0.38.1. Incluye préstamos a clientes desde Inversión y apertura de la ventana maximizada.

En Deudores, selecciona la persona y pulsa Registrar préstamo. El valor aumenta tanto su deuda como la inversión por recuperar; no descuenta Caja/Nequi ni registra una venta o salida de inventario. Los abonos posteriores siguen entrando a Caja o Nequi y reducen la deuda. La devolución de inversión al propietario sigue siendo un movimiento aparte. [Préstamos desde inversión](81-prestamos-inversion-038.md).

Cierra Producción y ejecuta `dist/Valinor-Sanctum-1.4.0-Produccion-Instalar.exe`. Actualiza el programa y sus accesos por usuario. Ventana, interfaz y metadatos se identifican como Producción 1.4.0. No hace falta copiar nuevamente la base o el JSON.

Usa `%USERPROFILE%\Documents\sanctum2.sqlite3` y `legacy-treasury.json`. Si falta la base, crea Valinor/COP/0. La base existente en esquema 21 se actualiza automáticamente al esquema 22 con un respaldo SQLite verificado antes de migrar, al primer inicio. Se preservan los datos anteriores y se agrega el registro de préstamos. La base no se modifica durante la instalación o desinstalación.

La fuente operativa se consulta únicamente en lectura para obtener un snapshot consistente; migración, arranque e instalación se ensayan en copias privadas dentro del repositorio. La entrega no ejecuta una instalación operativa.

Se conserva la última edición de Desarrollo 0.38.1, su ZIP y `Iniciar Valinor Sanctum.cmd`, con sus datos independientes. La limpieza de dist retira versiones anteriores únicamente de Producción.

El source mantiene `pubspec.yaml` en 0.38.1+62. La compilación productiva usa `--build-name=1.4.0 --build-number=63 --dart-define=SANCTUM_ENV=installed`.

Pasaron 53 pruebas de aplicación y dos renders de Producción revisados a 1280/400. Tres pruebas de enlaces se omitieron por permisos del host. Análisis limpio y formato de 216 archivos sin cambios. No se repitió la suite general.

La copia consistente de la fuente real estaba en esquema 21. La migración privada y el arranque nativo de la edición installed conservaron todos los valores de las 73 tablas anteriores y el JSON, también después de detener el proceso. Se comprobó el respaldo automático por contenido, nueva tabla de préstamos vacía, esquema 22, 74 tablas, integridad correcta y cero violaciones de claves foráneas. El arranque sin base creó Valinor/COP/0 en los Documentos del usuario privado.

La instalación aislada verificó 19 archivos, arranque, reapertura, rechazo de actualización abierta y conservación de base/JSON al reinstalar o desinstalar. El modo de ensayo omite registro y accesos reales. Los procesos propios se ejecutaron ocultos y se detuvieron tras verificar su ruta; no se atribuye observación del título ni inspección visual nativa. El inicio maximizado usa el mismo runner ya comprobado en Desarrollo 0.38.1.

El primer intento de empaquetado encontró una DLL ocupada por la prueba nativa; se repitió correctamente después de finalizar ese proceso. ZIP, bundle y payload del instalador coinciden en 19 archivos sin privados. Se preservaron 43 huellas de Desarrollo, su ZIP/acceso/selector/historial y la instalación productiva existente. Se retiraron el ZIP y el instalador productivos anteriores; la limpieza quedó sin pendientes. La instalación operativa y la migración de la fuente real no se ejecutaron.

Ver [evidencia sanitizada](evidence/production-140.json). Las copias y verificadores con datos privados permanecen en `tmp`, ignorado por Git.
