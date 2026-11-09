# Producción 1.8.0 — Alquiler y correcciones

Entrega instalada de Windows con los incrementos revisados de Desarrollo0.45 y0.46, ya integrados en main por el propietario:

- Ventas ofrece Alquiler por importe positivo, compartiendo pagos/deudas/división de la cuenta sin stock de juegos.
- Tesorería separa Agua, Energía y Envíos en los nuevos gastos; Servicios se conserva en historia y solicitudes previas.
- El menú de correcciones de Catálogo conserva cantidades y permite nombre/PVP para Comestibles y Artículos, además de editar Eventos con revisión previa e historial.
- Retirar componentes de un evento devuelve los artículos con su costo proporcional registrado; añadirlos consume solo la diferencia. Aumentar costo fijo cobra el adicional desde Caja/Nequi o incrementa Inversión. Las rebajas no devuelven dinero ni borran egresos anteriores. Las inscripciones confirmadas conservan sus snapshots. [Detalle](99-correcciones-catalogo-y-gastos.md).

La ventana, interfaz y accesos indican **Producción1.8.0**, compilada como `1.8.0+81` con `SANCTUM_ENV=installed`. El pubspec y portable de Desarrollo conservan **0.46.0+80** y sus datos independientes.

## Datos y actualización

Lee `%USERPROFILE%\Documents\sanctum2.sqlite3` y `legacy-treasury.json`. La migración25→27 crea un respaldo verificado antes de actualizar, conserva las76 tablas anteriores y sus filas y agrega cuatro tablas de correcciones vacías (80 totales). No cambia los movimientos o inscripciones existentes.

Al abrir Ventas se agrega únicamente la configuración de Alquiler si falta, con PVP global0 y la clasificación de valor variable. Bulk conserva su configuración. No se registra dinero ni stock por esa alta; si faltan cuentas abiertas, puede guardarse la cuenta inicial vacía prevista. Se conservan las solicitudes pendientes. Una instalación sin base crea Valinor/COP/0 decimales.

El instalador no contiene ni reemplaza archivos privados. Instalación, reinstalación y desinstalación conservan la base y el JSON de Documentos. El ensayo usa un snapshot obtenido abriendo la fuente exclusivamente en lectura y usuarios privados dentro del repositorio; no se instala ni migra la copia operativa durante la preparación.

Artefacto final: `dist/Valinor-Sanctum-1.8.0-Produccion-Instalar.exe`. El propietario cierra Producción y ejecuta el instalador. El primer arranque hace el respaldo y la migración.

## Publicación

El PR de publicación requiere CI completo aprobado del HEAD actualizado, integración y compilación desde el commit integrado. Los ensayos privados cubren arranque, migración, instalación/reapertura/reinstalación/rechazo de actualización con la app abierta y desinstalación conservando datos. ZIP, bundle e instalador deben contener el mismo programa, sin archivos privados.

Tras verificar se publica la carpeta productiva local y se retiran solo los artefactos anteriores de Producción. Se conserva la última ediciónDev y la instalación operativa existente. El lanzamiento queda identificado por `prod-1.8.0`; hashes y resultados finales se registran en el PR y evidencia privada, sin publicar snapshots ni filas operativas.
