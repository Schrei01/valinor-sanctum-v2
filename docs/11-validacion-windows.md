# Validación nativa de Windows — 0.1.0

Fecha: 19 de octubre de 2026, America/Bogota. Continúa la fundación del [incremento 01](10-incremento-01.md); ese informe y su JSON se conservan como registro histórico del corte anterior.

Este informe describe la entrega histórica 0.1.0. La ruta sin versión `dist/ValinorSanctum2` ahora contiene la versión vigente y el bundle anterior se conserva bajo tmp al publicar. Para iniciar la aplicación actual utiliza `Iniciar Valinor Sanctum.cmd` en la raíz. No ejecutes 0.1.0 contra una base actualizada a v2.

## Entorno y compilación

Con la autorización expresa «Sí autorizo» se ejecutó `scripts/install-build-tools.ps1 -Install`. Visual Studio Build Tools 2022 17.14.42 quedó instalado en `.tooling/visual-studio`, con herramientas C++ x64, CMake y Windows SDK 10.0.26100.0. El instalador terminó con código 0; `vswhere` informa instalación completa y ningún reinicio pendiente. Flutter doctor reconoce el toolchain Windows.

Se conserva Flutter portable 3.47.7, revisión `abaf9c523780a608bd46686fd5e53740a07077f8`, Dart 3.13.5 y el lockfile de dependencias. Los wrappers mantienen SDK y cachés dentro del proyecto nuevo, sin cambiar PATH global. La instalación C++ sí incorpora componentes compartidos de Windows, según la excepción autorizada.

La primera compilación nativa Release terminó correctamente en 87,9 segundos. Esa compilación usa exclusivamente el perfil sintético `smoke-98115880`, entorno `test`, con base en `tmp/desktop-smoke/smoke-98115880/sanctum2.sqlite3`. No es la configuración destinada al paquete final.

## Verificación del núcleo

- 63 pruebas aprobadas, tres omitidas porque el usuario de Windows no puede crear los enlaces simbólicos usados por esos casos. No se cambiaron ajustes de seguridad para habilitarlos.
- Análisis estático limpio, repetido después de formatear la herramienta de verificación.
- Se reforzó la comprobación de identidad y de relaciones del esquema al inicializar y volver a verificar un espacio. Un fallo cierra la sesión y permite recuperar el perfil confirmado mediante reintento.
- `tool/verify_desktop_profile.dart` inspecciona solo bases sintéticas ya existentes dentro de `tmp`, en modo de solo lectura. Comprueba perfil, integridad, esquema, migración y ausencia de operaciones/saldos. Dos informes con la misma huella permiten contrastar una reapertura.

Los logs locales están en `tmp/logs/native-tests.log`, `native-analyze.log`, `doctor-native.log`, `install-build-tools.log` y `build-native-smoke.log`; se excluyen de Git.

## Prueba de escritorio

Se abrió el ejecutable y se observó el formulario «Prepara tu ludoteca» por accesibilidad. El control de Windows no pudo capturar la ventana (`FrameArrived timed out` / `window capture timed out`) ni completar la entrada mediante UIA. Se reinició la conexión una vez y se conservó el mismo problema. La prueba posterior combinó entrada manual del propietario, observaciones por accesibilidad y navegación por teclado; no se presenta como validación automática mediante capturas.

El propietario confirmó: «Perfil creado, cuatro Correcto y ventana cerrada», tras crear «Ludoteca sintética 2.0» con COP y dos decimales. Se comprobó que la aplicación estaba cerrada y se ejecutó la primera inspección SQLite de solo lectura.

Se reabrió la misma compilación sintética: el árbol accesible mostró «Tu espacio está preparado», el nombre guardado, COP, dos decimales y Bogotá, sin volver al formulario inicial. Se cerró con Alt+F4 y se confirmó la ausencia de su ventana. La segunda inspección de solo lectura también pasó y produjo la misma huella `fnv1a64:8fe8dfebc223383e`.

Los [informes previo](evidence/desktop-profile-first.json) y [posterior](evidence/desktop-profile-second.json) comprueban perfil único, identidad de aplicación, esquema v1, migración y checksums, quick_check correcto y cero violaciones de claves foráneas. Las seis tablas operativas inspeccionadas están vacías y los débitos/créditos son cero. La huella compara perfil, migración, esos conteos y sumas; no es un hash de todo el contenido de la base. Además se calculó SHA-256 antes y después de la segunda lectura, con resultado idéntico, y ambos informes conservan tamaño y fecha de modificación durante la verificación.

También se abrió el ejecutable final de `dist/ValinorSanctum2`. Mostró el formulario vacío esperado. Navegando con Tab y Enter a Sistema se observaron perfil `development`, esquema 1, ruta `C:/proyectos/valinor_sanctum_2/data/development/development/sanctum2.sqlite3` y los cuatro indicadores en Correcto. No se creó un perfil de negocio en esa base; se cerró la aplicación con Alt+F4. Esto confirma el arranque y diagnóstico de la entrega, separado del perfil smoke. La etapa 3 de fundación queda completada.

## Empaque

`scripts/package-windows.ps1` reúne el ejecutable, motor Flutter, SQLite, assets y los tres runtimes C++ requeridos (`msvcp140.dll`, `vcruntime140.dll`, `vcruntime140_1.dll`). Omite los perfiles runtime de desarrollo/prueba y los snapshots JIT sobrantes de builds debug; rechaza enlaces o rutas fuera del nuevo proyecto. La revisión independiente de importaciones con `dumpbin /DEPENDENTS` confirmó esas dependencias.

La compilación final Release terminó en 113,4 segundos, sin defines SANCTUM de prueba. Se usó temporalmente `tmp/windows-final-build` para mantener intacta la compilación smoke mientras su ventana seguía abierta; la opción build-dir del perfil Flutter aislado se eliminó al terminar. La huella SHA-256 del AOT final difiere de la del smoke y el AOT extraído del ZIP coincide con el build final.

Artefactos disponibles:

- Ejecutable con todas sus dependencias: `dist/ValinorSanctum2/valinor_sanctum_2.exe`.
- ZIP completo: `dist/valinor-sanctum-2-0.1.0-windows-x64.zip`, 14.101.413 bytes y 17 archivos.
- SHA-256 del ZIP: `52B8FD72CD23D4CD7814ED7AFC602A622D147BB77332FB246042B4741C87FF8A`.
- [Evidencia de compilación y contenido del ZIP](evidence/windows-validation.json).

Se inspeccionaron las entradas del ZIP: están los archivos nativos, assets y runtimes requeridos; no hay bases SQLite, perfiles runtime ni restos debug. Se comparó por SHA-256 cada uno de sus 17 archivos con la copia de dist, y su AOT con el build. La primera copia intermedia de 21 archivos se conservó bajo tmp; el empaquetador ahora excluye los cuatro archivos debug que Flutter había conservado en los assets compartidos. El bundle final extraído se abrió, se diagnosticó y se cerró; el SHA-256 del ZIP continúa coincidiendo con la evidencia después de esa prueba.

Para reproducir esa compilación en otra carpeta de salida dentro del repositorio, `scripts/package-windows.ps1` acepta `-ReleasePath`. Para una compilación normal basta `./scripts/flutter.ps1 build windows --release --no-pub` y después `./scripts/package-windows.ps1`. El empaquetador no sobrescribe un ZIP existente: conservar la entrega anterior y usar otra versión al generar una nueva.

El ZIP completo es necesario; el `.exe` depende de las DLL y la carpeta `data` adyacentes. Fuera del directorio build, la configuración final guarda en `C:/proyectos/valinor_sanctum_2/data/development/development/sanctum2.sqlite3`. Esta versión de desarrollo mantiene su almacenamiento dentro del repositorio autorizado; no es un instalador portátil para otras ubicaciones ni está habilitada para producción.

## Integridad y alcance

La [comparación de hashes del original](evidence/original-check-windows.json) conserva idénticos sus 163 archivos fuera de `.git` y los 28 archivos Git ajenos a las referencias internas de Codex. Solo se observó el reemplazo de dos referencias bajo `.git/refs/codex/turn-diffs/` por otras dos. La igualdad de todo el árbol, incluidas esas referencias, es falsa; excluyéndolas es verdadera. No se escribieron ni restauraron archivos del original.

No se abrió la base productiva, no se ejecutó el POS original ni se hicieron migraciones o sincronización. Catálogo, compras, inventario persistente, ventas/cobros, caja, reportes e importación siguen pendientes. Este incremento entrega la fundación técnica y el perfil vacío.
