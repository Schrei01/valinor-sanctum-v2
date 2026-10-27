# Retención de entregas y verificación de origen

El propietario autorizó borrar las entregas anteriores y eliminarlas automáticamente al salir una nueva. `dist` conserva la ruta estable `ValinorSanctum2`, la carpeta versionada actual y su ZIP. Solo se eliminan carpetas/ZIP con nombres reconocidos y versión inferior a la instalada. Las versiones superiores y archivos ajenos se conservan.

`clean-old-distributions.ps1` comprueba la versión del ejecutable estable, resuelve todos los destinos dentro de `dist` y hace una revisión completa antes de borrar. Rechaza enlaces/junctions, bases o perfiles privados y versiones anteriores en ejecución. `-DryRun` permite revisar los candidatos sin borrar. El parámetro alternativo de carpeta solo admite fixtures dentro de `tmp` del proyecto.

Después de publicar correctamente, `publish-local-bundle.ps1` elimina el bundle previo que mantuvo temporalmente para rollback y ejecuta la limpieza de entregas obsoletas. `package-windows.ps1` también elimina su carpeta temporal al terminar correctamente. Los respaldos de bases y datos operativos se conservan. Las carpetas temporales históricas creadas antes de este cambio no forman parte de esta limpieza de `dist`.

## Verificación

Se eliminaron 24 carpetas y 25 ZIP anteriores: 49 artefactos y 1.174.539.302 bytes. Permanecen `dist/ValinorSanctum2`, `dist/0.17.2` y `dist/valinor-sanctum-2-0.17.2-windows-x64.zip`. Todos los archivos vigentes se compararon por hash antes/después y siguen idénticos. Se observó inicialmente la app abierta desde la carpeta versionada vigente; el agente no cerró ventanas. Al finalizar ya no se observó el proceso.

Cinco comprobaciones sintéticas aprobaron: revisión sin borrar, retención de versión vigente/superior y archivos ajenos, protección de datos privados, rechazo de versión a conservar distinta de la instalada y publicación con limpieza automática de entregas anteriores. La última usa el publicador real con una raíz de proyecto sintética dentro de `tmp`. Se comprobó que no queden binarios previos en su staging después de publicar. Los cuatro scripts pasan el análisis de sintaxis de PowerShell. La prueba elimina sus propios fixtures tras completarse correctamente.

Las 60 tablas de la base activa se compararon antes/después y permanecen idénticas, con integridad correcta. No hay cambios en Dart, esquema ni versión del programa; no se recompiló ni se repitieron pruebas Flutter. Ver [evidencia](evidence/distribution-retention.json).

## Base consultada por Reportes

La entrega sin overrides usa la raíz fija del proyecto y `data/development/active-workspace.json`, que selecciona el perfil `valinor`; Reportes recibe la misma conexión que el resto de módulos. Tanto el ejecutable estable como el de `dist/0.17.2` resuelven `data/development/valinor/sanctum2.sqlite3`, fuera del bundle. No se cambió el selector ni la conexión.

La cobertura de saldos de la nueva aplicación comienza con su apertura importada. Las fechas anteriores no se reconstruyen desde `cash`/`nequi` del sistema original: esa historia no se importó al libro operativo. La ausencia de saldo anterior se muestra como Sin información, no cero. La copia de origen es distinta de la base operativa de Sanctum 2.0 y permanece solo lectura. Datos, importes y comprobantes de procedencia siguen privados.
