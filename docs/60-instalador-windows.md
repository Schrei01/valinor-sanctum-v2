# Instalador Windows 0.27.0

El propietario solicita un ejecutable instalable con los requisitos acordados: identidad Valinor, COP, cero decimales, entrada directa a Ventas y almacenamiento en Documentos. Esquema 16 sin migraciones nuevas.

## Uso

1. Ejecutar `dist/Valinor-Sanctum-0.27.0-Instalar.exe` en Windows x64 y aceptar la instalación.
2. Abrir Valinor Sanctum 2.0 desde el escritorio o Inicio.
3. La aplicación abre `%USERPROFILE%\Documents\sanctum2.sqlite3`. Para el usuario actual corresponde a `C:\Users\ValinorPC\Documents\sanctum2.sqlite3`.

Si no existe, la aplicación crea su esquema y configura únicamente Valinor, COP, cero decimales y Bogotá. No crea productos, ventas, dinero ni deudas de ejemplo. Si existe una base Sanctum compatible con perfil `valinor`, la valida y continúa sobre ella. Una base incompatible o dañada produce un error; no se borra, reinicia ni sustituye. No se admite una base antigua del POS sin la conversión previamente realizada.

El instalador no incluye bases ni copia automáticamente el almacenamiento de desarrollo. Trasladar datos existentes al equipo de atención es una operación separada: debe hacerse con ambas aplicaciones cerradas y respaldo previo. No reemplazar un archivo existente sin conciliarlo.

## Instalación y conservación de datos

- Programa por usuario en `%LOCALAPPDATA%\Programs\ValinorSanctum2`, con DLL de Flutter, SQLite y runtime C++ incluidos. No requiere Flutter ni herramientas de desarrollo en destino.
- Instalador y desinstalador usan .NET Framework 4.x y componentes de Windows; se compilan con el compilador ya disponible, sin instalar otras herramientas.
- Accesos con icono Valinor en escritorio e Inicio, y entrada en la lista de aplicaciones de Windows.
- Actualización con reemplazo del bundle completo y conservación temporal del anterior para recuperación. Rechaza versiones inferiores y exige cerrar la app instalada antes de reemplazarla.
- La instalación y desinstalación no abren ni eliminan la base de Documentos. Se conservan también sus respaldos.
- Las migraciones compatibles de la aplicación conservan su verificación y respaldo SQLite previo, en `Documents\ValinorSanctum2-backups`. Una base más nueva no se degrada.
- No se acepta un instalador que contenga bases, perfiles runtime o snapshots privados. El comando reservado del Catálogo no se anuncia en instrucciones de uso.

## Desarrollo y compilación

El modo `installed` se selecciona al compilar y usa el usuario de Windows en tiempo de ejecución. No consulta `active-workspace.json`, rutas del ejecutable ni el perfil de desarrollo. Los modos development/test conservan sus rutas y selección anteriores, dentro del repositorio.

```powershell
./scripts/flutter.ps1 build windows --release --no-pub --dart-define=SANCTUM_ENV=installed
./scripts/package-windows.ps1
./scripts/build-installer.ps1
./scripts/verify-installer.ps1
```

La verificación del instalador utiliza exclusivamente una carpeta nueva bajo `tmp`, sin crear accesos ni registro reales. Ejecuta el mismo binario final con un USERPROFILE sintético solo para el proceso hijo. El flujo real de accesos/registro se revisa por código; no se instala la app en el perfil operativo durante esta validación.

Se intentó preparar Inno Setup portable, pero el control automático rechazó la ejecución sin dar más motivo que «blocked by policy». Se continuó con el compilador .NET ya disponible. La herramienta no se descargó ni instaló.

## Validación

- 81 pruebas de configuración, rutas, inicio, bases y migraciones aprobadas; tres omitidas por restricciones de enlaces simbólicos del host.
- Ocho pruebas adicionales de jornadas, navegación e inicio aprobadas; incluyen las tres jornadas de 20 cuentas. Los siete casos nuevos de la edición instalada están incluidos en las 81 anteriores.
- Análisis estático sin incidencias y formato de 193 archivos Dart sin cambios. Compilación Release 0.27.0+42 correcta.
- Instalación aislada verificada en los 18 archivos del bundle, inicio/reapertura nativos, actualización bloqueada con app abierta, reinstalación y desinstalación conservando los bytes de la base. La copia instalada se retiró al terminar.
- La base creada por el ejecutable nativo se inspeccionó en solo lectura: Valinor/COP/0 decimales, esquema16, integridad correcta, cero violaciones FK y cero documentos, ventas, líneas de compra o asientos.
- El primer ensayo ocultó la ventana: Windows no devolvió un handle principal para cerrarla. Se detuvo exclusivamente ese proceso sintético y se repitió con ventana normal, con todos los controles aprobados. No se atribuye inspección visual nativa ni prueba real de accesos/registro.
- Base de desarrollo idéntica por SHA256 antes/después; original intacto, sin operaciones de negocio sobre datos reales ni instalación en el perfil operativo. No se creó la base de Documentos del usuario durante las pruebas.
- Se publicó el bundle estable y se eliminaron versiones anteriores de dist. El instalador ocupa 15.403.520 bytes. No se repitió la suite local completa: la última, sobre ac1967f, tuvo 755 aprobadas y tres omitidas; esta entrega tiene la validación específica descrita arriba.

Resultados sanitizados y hashes finales en `docs/evidence/windows-installer.json`.
