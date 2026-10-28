# Desarrollo portable 0.27.0 — 28/10/2026

El propietario solicita la versión de desarrollo 0.27 que usa la base existente del proyecto, sin instalar. Se conserva la versión 0.27.0+42 y el esquema16; no cambia el código Dart de la aplicación.

## Abrir

Ejecutar `Iniciar Valinor Sanctum.cmd` en la raíz del proyecto o `dist/ValinorSanctum2/valinor_sanctum_2.exe`, conservando la carpeta completa. La app quedó abierta para revisión.

La configuración normal de desarrollo lee `data/development/active-workspace.json`, cuyo perfil actual es `valinor`, y utiliza `C:\proyectos\valinor_sanctum_2\data\development\valinor\sanctum2.sqlite3`. No usa Documentos. No abrir directamente desde build: ese lugar conserva el aislamiento de las compilaciones de prueba.

La distribución comprimida es `dist/valinor-sanctum-2-0.27.0-development-windows-x64.zip`. No instala accesos ni contiene bases o snapshots privados. El instalador ya entregado continúa usando Documentos.

## Reproducir

```powershell
./scripts/flutter.ps1 build windows --release --no-pub
./scripts/package-windows.ps1 -Edition Development
```

No pasar defines SANCTUM a esta compilación: el selector local debe permanecer habilitado. El empaquetador diferencia nombres e instrucciones de ambas ediciones y verifica los defines de la compilación habitual para evitar etiquetar como desarrollo un binario instalado, o a la inversa. El comportamiento predeterminado del empaquetador sigue siendo Installed, como usa CI.

La verificación del instalador toma su bundle esperado del ZIP de la edición instalada, independientemente de la edición publicada en la ruta estable. La limpieza reconoce ZIP de desarrollo anteriores y conserva las dos ediciones de la versión vigente.

## Comprobado

- 25 pruebas de configuración, rutas y selección local aprobadas; tres omitidas por restricciones de enlaces del host. Compilación Release correcta, sin overrides SANCTUM.
- Respaldo local previo de la base existente verificado por SHA256. Resolución del perfil y ruta confirmadas, sin operaciones comerciales de prueba.
- Dieciocho archivos idénticos entre ZIP y bundle estable; instrucciones específicas de desarrollo y ausencia de datos privados.
- Inicio nativo con proceso respondiendo y título Valinor Sanctum 2.0. No se atribuye inspección visual de la interfaz.
- Después de abrir, las 68 tablas conservan todas sus filas y definiciones; esquema16, integridad correcta y cero violaciones FK. SHA256 del archivo completo también coincide con el previo. La primera lectura de hash con acceso compartido limitado encontró bloqueo; se verificó con lectura compartida y con SQLite en solo lectura.
- Instalador previo idéntico por SHA256. Al conciliar artefactos, el ZIP instalado no estaba disponible: se recuperó desde el recurso Payload.zip del instalador y se verificó idéntico al hash anterior. El ensayo de limpieza posterior indica cero artefactos a eliminar de la versión vigente.
- Intentar empaquetar esta compilación como Installed fue rechazado antes de publicar. No se generó instalador nuevo, no se modificó la base de Documentos ni el POS original.

No se repitieron análisis Dart ni la suite comercial completa por este cambio de empaquetado. El CI de la entrega instalable 16c28c6 terminó correctamente; el de este cambio se consulta tras publicar.
