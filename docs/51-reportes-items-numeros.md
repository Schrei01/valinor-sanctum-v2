# Reportes: fechas iniciales, ítems paginados y números con miles — 0.22.0

Solicitud del 27/10/2026. El propietario aclaró que dejar vacía la fecha inicial debe esperar a que se elija; no significa consultar todo el historial.

## Comportamiento

- Reportes abre sin fecha inicial y sin ejecutar consultas. La fecha final predeterminada es la fecha y el minuto actuales de Bogotá. Generar sin inicio muestra una indicación y no consulta la base.
- Se mantiene fecha → Aceptar → hora AM/PM en ambos selectores. Se puede quitar el inicio. Una actualización conserva los cortes del último informe generado; los selectores no cambian los datos ya calculados hasta generar otro.
- Debajo del comprobante aparece «Ítems vendidos»: fecha/hora, nombre del producto, cantidad, pago e importe. Son líneas de ventas confirmadas, incluidas inscripciones y ventas antiguas archivadas; no ingresos de mercancía ni borradores.
- Diez filas por página, más recientes primero, desempate estable por identificador. Anterior/siguiente y contador; vuelve a la primera página tras cada consulta exitosa. Un error conserva el informe anterior.
- Las ventas nuevas usan los importes históricos de `sale_lines`. Las antiguas usan cantidad × PVP de su producto archivado, con asterisco de estimación; productos eliminados o precios ausentes conservan su fila e indican «Sin información». No se consulta el PVP actual para reconstruir ventas antiguas.
- Todos los campos de importes y cantidades separan miles con punto al escribir o pegar, por ejemplo `25000` → `25.000` y `1000` → `1.000`. Los perfiles históricos con decimales conservan la coma y su precisión. El formato no cambia la escala monetaria ni el valor guardado.
- Se conserva la edición del cursor, selección, borrado de separadores y composición IME. Cantidades fraccionarias permanecen inválidas. Ventas guarda sus borradores con dígitos canónicos sin puntos y recupera el texto agrupado al abrirlos.

## Archivos principales

- `lib/features/reports/{application,presentation,domain,data}`: selección inicial, consulta coherente, filas históricas/nativas y paginación.
- `lib/core/presentation/grouped_number_formatter.dart`: formato común de presentación.
- Formularios de Compras, Ventas, Eventos, Deudores, Tesorería y formularios financieros anteriores: aplicar formato y normalizar cantidades antes de su lectura.
- Pruebas de Reportes, conversión histórica, formato numérico, Compras y Ventas.

## Verificación y publicación

Suite completa: 722 aprobadas y tres omitidas por enlaces simbólicos de Windows. Foco de formato/Compras/Ventas: 23 aprobadas. Análisis sin incidencias. Dos renders sintéticos inspeccionados. Se corrigieron durante el desarrollo la validación de cantidades fraccionarias y un helper local de pruebas.

Sobre una copia privada se conciliaron las 4.305 filas archivadas, con 4.153 estimaciones y 152 importes desconocidos; las cantidades de filas y los importes calculables coinciden con el resumen. También se comprobó el orden y el filtro de minuto. Las ventas nativas se validan con operaciones sintéticas en pruebas; no se crearon ventas reales para probar.

Respaldo verificado; las 64 tablas activas conservan exactamente filas y esquema, integridad correcta y cero violaciones FK. Publicado el release sin overrides: ZIP/estable/versionada coinciden en 17 archivos, sin datos privados, ejecutable 0.22.0+34. Se limpiaron las versiones anteriores de dist. App cerrada al verificar; sin recorrido nuevo de GUI nativa. Evidencia: `docs/evidence/report-items.json`.

Sin migración: esquema 15, 64 tablas. No se crean operaciones de prueba en la base activa ni se modifica el POS original. No se añaden gráficas, exportaciones ni un visor de cambios de PVP en este incremento.
