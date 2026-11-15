# Producción 1.10.0

Publica Desarrollo 0.51.0: selector del mes de nacimiento por nombre y avisos de cumpleaños desde siete días antes, también para personas sin membresía activa. Conserva la Mensualidad Élfica de COP109.000 con bono de COP30.000, las ventas, deudas y operaciones anteriores.

Compilación `1.10.0+90` con `SANCTUM_ENV=installed`. El `pubspec.yaml` y el portable de Desarrollo conservan `0.51.0+89`, su almacenamiento y configuración independientes. El esquema continúa en29: esta entrega no introduce migraciones nuevas. Una instalación que aún esté en esquema27 utiliza las migraciones28/29 existentes y el respaldo previo correspondiente.

El instalador `dist/Valinor-Sanctum-1.10.0-Produccion-Instalar.exe` no contiene bases ni historial privados. Usa los archivos de Documentos del usuario al arrancar la edición instalada. Preparar una versión no instala sobre el equipo operativo, no abre su base con escritura y no cierra sus ventanas. El propietario instala cuando corresponda.

La publicación se prepara en una rama temporal desde `origin/main`, mediante PR y `verify-and-build` completo aprobado. El artefacto final se reconstruye desde el commit integrado y aprobado, se identifica con la etiqueta inmutable `prod-1.10.0` y conserva la distribución actual de Desarrollo. Los ensayos de instalación, reinstalación, desinstalación y conservación de datos usan únicamente ubicaciones privadas dentro de `tmp`.
