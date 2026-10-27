# Inicio automático e identidad de Valinor — 0.25.0

Una base nueva se configura automáticamente con nombre **Valinor**, moneda **COP**, **0 decimales** y zona horaria **America/Bogota**. La app abre directamente en Ventas. Se retiraron el formulario y la acción del controlador para crear una ludoteca manualmente.

Primero se comprueban identidad, integridad, claves foráneas y esquema. Luego se guarda la configuración y se vuelve a leer antes de mostrar la aplicación lista. Un fallo cierra la sesión y permite reintentar; si el guardado ya se había confirmado, el reintento recupera esa configuración sin crearla de nuevo. Los perfiles existentes conservan sus datos, incluso la escala monetaria histórica.

La configuración inicial no añade productos, dinero, deudas, ventas ni otras operaciones. La apertura real sigue utilizando la ubicación vigente de almacenamiento; el instalador y el cambio a Documentos se preparan por separado.

## Identidad visual

El propietario confirmó usar el logo original del barco y las montañas. El original se consultó en lectura; su copia exacta se conserva en `assets/branding/valinor-original.png`.

El generador `tool/build_brand_assets.ps1` para PowerShell 7 conserva el dibujo y sus textos, elimina únicamente el margen blanco exterior y escala recursos de interfaz e icono de Windows. La app muestra el logo en menú y cabecera. El icono reemplaza al de Flutter en el recurso nativo del ejecutable, que utiliza la ventana y los accesos al programa.

El ICO contiene nueve tamaños: 16, 20, 24, 32, 40, 48, 64, 128 y 256 px. No se cambian los iconos funcionales de Catálogo, Compras, Ventas y demás acciones. El futuro instalador podrá utilizar este mismo recurso de marca.

## Verificación y entrega

- **29 pruebas finales aprobadas**, incluyendo creación/reapertura real de una base vacía, confirmación, recuperación, conservación de configuración previa y tres renders sintéticos.
- Esas tres imágenes, a anchos 1366, 900 y 400 px, alto 768, se inspeccionaron con fuentes y logo reales. La navegación sigue visible; se abre Ventas sin formulario de alta.
- Análisis limpio, resolución bloqueada de dependencias correcta y formato de 188 archivos sin cambios.
- PNG e ICO regenerados con hashes idénticos; copia exacta del logo y recursos del original conservados. Lectura independiente del PE del ejecutable verifica los nueve iconos embebidos, idénticos a los del ICO.
- Release 0.25.0+39 sin overrides publicado, con pie 0.25.0. ZIP, estable y copia versionada coinciden en 18 archivos; incluyen solo el PNG optimizado y el icono compilado, sin perfiles ni datos privados. Versiones anteriores limpiadas.
- Respaldo verificado en `backups/valinor-brand-20261027`: esquema 16 y las 68 tablas activas, con todas sus filas y definiciones idénticas antes/después de publicar y abrir. Integridad correcta, cero FK y sin operaciones de prueba sobre la activa.
- App abierta y respondiendo. Accesibilidad nativa observó el logo, Versión 0.25.0 y ausencia del formulario; no se ingresaron datos ni se realizaron operaciones.

Evidencia sanitizada en `docs/evidence/valinor-brand.json`. Los scripts de auditoría, bases, respaldos y renders de prueba permanecen privados dentro del proyecto nuevo. El generador de marca está versionado para reproducir los recursos. CI de este commit se comprueba después del push; no confundir las comprobaciones locales con un resultado remoto todavía pendiente al crear el commit.
