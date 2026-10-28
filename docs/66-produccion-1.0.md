# Producción1.0.0 y desarrollo0.30.0 conservado

El propietario pidió generar un instalador productivo, cambiar los rótulos de Desarrollo, conservar expresamente la0.30 de desarrollo y comprobar los archivos colocados en Documentos. Se elige **1.0.0+46 — Producción** como primera distribución productiva identificada, distinta de **0.30.0+45 — Desarrollo**. El esquema sigue en18 y no cambian los cálculos comerciales.

## Uso

Ejecuta `dist/Valinor-Sanctum-1.0.0-Produccion-Instalar.exe`. El instalador actualiza la instalación por usuario en `%LOCALAPPDATA%/Programs/ValinorSanctum2`, crea accesos **Valinor Sanctum - Producción** en escritorio e Inicio y registra ese nombre en aplicaciones instaladas. Retira un acceso antiguo con el nombre genérico solo si apunta al mismo ejecutable de esa instalación. No modifica el acceso de desarrollo del repositorio.

Producción usa únicamente `%USERPROFILE%/Documents/sanctum2.sqlite3` y su historial `%USERPROFILE%/Documents/legacy-treasury.json`. Conserva los datos al instalar, actualizar o desinstalar; el paquete no los incluye. Si falta la base, se configura una nueva Valinor/COP/0 decimales. Si existe una base incompatible o dañada, se conserva y se muestra el error. El instalador rechaza retrocesos de versión y requiere cerrar la copia instalada que está actualizando.

La ventana nativa, el título de Flutter, la etiqueta del encabezado, el pie lateral, los accesos y el instalador identifican **Producción**. El pie muestra1.0.0 y el encabezado usa un icono de tienda. Las compilaciones de desarrollo mantienen la identificación Desarrollo; el ejecutable0.30 ya publicado permanece sin cambios.

## Distribuciones independientes

| Edición | Carpeta local | Archivo |
|---|---|---|
| Desarrollo0.30.0 conservado | `dist/ValinorSanctum2` | `valinor-sanctum-2-0.30.0-development-windows-x64.zip` |
| Producción1.0.0 | `dist/ValinorSanctum2-Produccion` | `valinor-sanctum-2-1.0.0-production-windows-x64.zip` |

El acceso `Iniciar Valinor Sanctum.cmd` continúa abriendo desarrollo y su base independiente. No publicar una nueva compilación de desarrollo sobre esa carpeta protegida sin conservar antes la0.30.

`package-windows.ps1 -Edition Installed` exige `SANCTUM_ENV=installed`, genera el sufijo `-production` y un manifiesto público `EDICION.json`. El publicador valida que la edición del manifiesto corresponda al destino antes de reemplazar archivos. Las versiones antiguas de desarrollo sin manifiesto continúan admitidas en su destino de desarrollo. El creador del instalador exige manifiesto de producción y versión coincidente.

La limpieza selecciona artefactos de la misma edición, protege la otra y mantiene expresamente los archivos de desarrollo0.30.0 aunque se publique una versión posterior. Se mantienen las verificaciones de rutas, enlaces, datos privados y rollback. La compilación C++ usa el mismo define de entorno que Dart para su título y metadatos; no depende de una variable editable al ejecutar.

## Archivos de Documentos

La comprobación se realizó con SQLite en modo solo lectura. Los69 conjuntos de datos y su esquema coinciden con la base preparada, salvo la cuenta interna de gastos añadida por el arranque normal de desarrollo. Se verificaron esa única fila adicional, los valores conservados y la huella del JSON contra la apertura de Tesorería. Los archivos son correctos para esta edición.

Se compararon sus SHA256 antes y después de las verificaciones y del ensayo del instalador: ambos permanecen idénticos. No se ejecutó producción sobre esos archivos operativos ni se instaló silenciosamente en el perfil de uso. Las pruebas nativas usaron un usuario de ensayo y carpetas propias dentro de `tmp`, incluyendo una copia independiente de la base y el JSON verificados.

## Validación

- Análisis limpio y formato revisado. Ejecución final con24 pruebas de configuración/interfaz/instalación aprobadas más dos renders. Cuatro casos nuevos cubren ambas etiquetas en1280 y400 píxeles. Otra ejecución aprobó24 pruebas de rutas, selector y controlador, con tres omisiones por enlaces del host. Un comando inicial seleccionó una ruta inexistente de pruebas; se corrigió y se repitió la selección final. No se atribuye una nueva suite completa.
- Dos renders finales inspeccionados, con logo y rótulos de Producción. Se repitieron tras esperar explícitamente la carga de la imagen del logo en el render privado.
- Cinco comprobaciones históricas de limpieza aprobadas, más pruebas de conservación entre ediciones, publicación separada, rechazo de edición incorrecta y protección futura del archivo0.30.0.
- Release installed1.0.0+46 compilada. Bundle y ZIP coinciden en19 archivos; el instalador incorpora exactamente ese ZIP, sin bases ni historial privado.
- Instalación y arranque nativos en aislamiento, creación automática de base nueva, actualización bloqueada con app abierta, reinstalación, reapertura y desinstalación aprobados. Otro arranque con copia de los archivos preparados comprobó el título nativo Producción y conservó bytes de base y JSON, también al reinstalar y desinstalar. Se verificaron19 archivos instalados. Registro y accesos reales se revisaron por código y no se ejecutaron en el ensayo.
- Los18 archivos de la distribución de desarrollo0.30.0, su ZIP y su launcher conservan sus SHA256. No se cerró ni reemplazó la ventana de desarrollo del propietario.

La instalación operativa queda en manos del propietario mediante el ejecutable entregado. El esquema18 y los datos preparados no necesitan otra conversión por el cambio de versión comercial. Ver `docs/evidence/production-100.json` para la evidencia sanitizada.
