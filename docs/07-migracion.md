# Compatibilidad e importación futura del POS original

Estado: diseño de importador, sin código ejecutable ni migración realizada. El original y sus respaldos permanecen intactos.

## 1. Qué puede y qué no puede recuperarse

La única evidencia actual es el código de la revisión auditada. La base real puede tener un esquema distinto según su historial de migraciones. user_version no basta para conocer columnas efectivas.

| Fuente original | Información potencialmente recuperable | Información ausente/ambigua |
|---|---|---|
| products | ID/nombre, cantidad actual, precio/costo actual, lote textual | Entradas históricas, costos por capa, SKU, valoración histórica |
| sales | ID, producto, cantidad, fecha y medio si existe columna | Cabecera/ticket, precio/costo del momento, descuentos/devoluciones, cliente |
| cash / nequi | Fotografías de saldo e identificador; fecha si existe | Asiento causal y garantía de integridad del histórico |
| caja_mayor / deudas | Fotografías de saldo y fechas | Origen, contraparte y significado activo/pasivo de Deudas |
| movimientos | Tipo/cuenta/monto/motivo/fecha | Registro completo de ventas, transferencias, aportes y relaciones entre partidas |
| Cuentas abiertas | No hay tabla identificada | No se pueden importar automáticamente los objetos que solo viven en memoria |

No se prometerá reconstruir margen histórico, costos de ventas, flujo completo o deuda individual con información que el original no guarda. Los productos eliminados pueden dejar ventas sin referencia recuperable. Los datos no finitos, fechas inválidas, saldos ambiguos y referencias huérfanas requieren reporte y cuarentena.

## 2. Modalidades propuestas

**Modo preferido: archivo histórico explícito más apertura verificada.**

- Conservar observaciones originales y sus IDs bajo un namespace legado, con archivo de origen, calidad y advertencias.
- Las ventas antiguas sin precio/costo documentados no se convierten en ventas de 2.0 con un precio inventado. Pueden consultarse como cantidades/medios/fechas conocidas; sus importes y márgenes siguen no disponibles.
- Incorporar catálogo y stock al instante de corte como apertura identificada, con costo confirmado cuando exista evidencia o capa de costo desconocido.
- Abrir cuentas monetarias con saldos al corte conciliados por el propietario. Una diferencia no se oculta: se documenta como pendiente o ajuste explícito.
- No contabilizar todas las fotografías de saldo como entradas de dinero. No descontar ventas antiguas otra vez del stock al corte.
- Conservar movimientos legados con información parcial; no sumarlos de nuevo al saldo inicial.
- Clasificar Deudas con el propietario y, si hay desglose externo verificable, crear obligaciones individuales. Nunca repartir arbitrariamente un total entre personas.

**Modo de reconstrucción histórica** solo si respaldos/evidencias adicionales contienen precios, costos, aperturas y movimientos conciliables. Debe tener adaptador, pruebas y conciliación propios; el código auditado no permite asumir esos datos. No mezclar ambos modos sobre el mismo hecho sin controles contra duplicación.

Un reporte puede combinar fechas nuevas y legadas solo si presenta cobertura y fuentes por separado. No presentar una serie monetaria completa cuando un tramo carece de importes confiables.

## 3. Cadena de importación segura

1. **Selección:** el usuario proporciona un respaldo, no el archivo operativo Documentos/valinor.db. Rechazar la ruta operativa conocida y cualquier enlace al mismo archivo. No descubrir/abrir bases productivas automáticamente.
2. **Copia de trabajo:** verificar archivo, tamaño, firma SQLite y huella SHA-256; copiar únicamente el respaldo seleccionado a un staging dentro del almacenamiento propio 2.0. No modificar el respaldo seleccionado.
3. **Consistencia:** exigir snapshot autocontenido y coherente. Si hay WAL pendiente o no se sabe cómo se creó el respaldo, detener y solicitar respaldo consistente; no ignorar WAL ni usar immutable para fingir consistencia.
4. **Apertura de staging:** modo de solo lectura/query_only, sin extensiones ni ejecución de SQL proporcionado por el archivo. Introspección permitida sobre tablas explícitas; límites de lectura y tamaños.
5. **Inspección:** integrity_check/quick_check según volumen, foreign_key_check cuando aplicable, user_version, columnas/tipos, índices, claves y fingerprint canónico de esquema. La presencia de FK declarada no demuestra que se haya aplicado.
6. **Compatibilidad:** elegir adaptador por versión y fingerprint. Rechazar esquemas desconocidos o tablas necesarias faltantes; no ejecutar onUpgrade del POS original.
7. **Previsualización:** contar candidatos, huérfanos, duplicados, negativos, costos ausentes, fecha/medio desconocido y ambigüedades. Proponer mapeo sin escribir datos operativos de destino.
8. **Plan:** definir namespace del origen, fecha de corte, moneda/escala, timezone y conversiones; usuario revisa equivalencias de productos, cuentas y categorías. Mantener “sin clasificar” cuando falte evidencia.
9. **Preparación de destino:** bloquear nuevas escrituras operativas de 2.0, comprobar espacio, esquema esperado y crear backup consistente de destino con hash/verificación y restauración ensayada sobre copia.
10. **Aplicación:** importar a staging de destino o una sola transacción; resolver relaciones mediante IDs mapeados y claves idempotentes. Las aperturas/documentos/asientos se confirman juntos. Error bloqueante revierte la transacción.
11. **Conciliación:** comparar conteos y relaciones, cantidades al corte, saldos aprobados, totales conocidos y sumas de asientos. Mostrar cada diferencia; no forzar igualdad mediante ajustes ocultos.
12. **Resultado:** informe legible con importados/omitidos/en cuarentena, limitaciones, mapeos, huellas, configuración y versión de adaptador; el usuario acepta la conciliación antes de usar datos importados.
13. **Reversión:** un fallo antes del commit hace rollback. Recuperación por backup solo bajo exclusión, destino correcto y sin operaciones posteriores; si existen, no restaurar encima ni borrarlas. La reversión posterior requiere plan y autorización específicos.

La API de backup de SQLite permite obtener snapshots consistentes de bases activas; el mecanismo concreto depende de lo que exponga el adaptador seleccionado. No se promete que copiar el archivo principal abierto sea suficiente. [Documentación de backup](https://www.sqlite.org/backup.html).

## 4. Identidad, idempotencia y trazabilidad

Tablas propuestas: import_runs, import_id_map, import_issues y legacy_observations; definidas en el [modelo de datos](05-modelo-financiero.md).

- Cada negocio/base de origen tiene un namespace estable. Dos respaldos del mismo negocio comparten ese namespace, aunque su hash cambie.
- Clave única de identidad: namespace + tipo de entidad + ID original; no únicamente hash del archivo. Guardar fingerprint de fila y mapeo al ID de destino.
- Misma identidad y mismo contenido: omitir como ya importado.
- Misma identidad con contenido cambiado: detectar conflicto; no volver a crear ni sobrescribir un hecho confirmado silenciosamente.
- Archivo/hash repetido: rechazar o mostrar ejecución previa. Una ejecución fallida no se considera completada.
- Apertura única por namespace/perfil/tipo/objeto (producto, cuenta u obligación). La fecha de corte es atributo y no parte de la identidad: cambiarla no permite volver a sumar stock o dinero. Una corrección posterior exige documento de ajuste vinculado y revisión explícita.
- El importador no actualiza las ventas posteriores a la fecha de corte y no funciona como sincronización incremental/bidireccional.
- Conservar tanto fecha original/texto como instante interpretado y política de zona aplicada; no inventar precisión temporal.
- Conversiones de REAL legado a enteros requieren escala y redondeo documentados; conservar valor legado como evidencia y reportar ajustes, sin asumir exactitud del dato anterior.

## 5. Conciliaciones obligatorias

| Comprobación | Condición para aceptar |
|---|---|
| Relaciones | Todos los IDs mapeados o excepción explícita; sin huérfanos silenciosos |
| Unicidad | Segunda ejecución y respaldo posterior no duplican entidades/aperturas |
| Stock | Cantidades importadas por producto coinciden con corte aprobado; legado no se vuelve a descontar |
| Valoración | Valor conocido concilia con capas; desconocidos separados |
| Caja | Aperturas por cuenta concilian con saldo aceptado; snapshots no tratados como flujos |
| Obligaciones | Clasificación/contraparte documentada; total ambiguo no tratado como efectivo |
| Asientos | Débitos = créditos por documento y moneda; origen único |
| Histórico | No precios/costos actuales etiquetados como históricos; cobertura visible |
| Atomicidad | Fallos inyectados no dejan importación parcial |
| Origen | Hash del respaldo seleccionado permanece igual al terminar |
| Reversión | Restauración ensayada con copia sintética o de destino en pruebas |

## 6. Pruebas antes de admitir un respaldo real

Generar fixtures sintéticos que representen onCreate actual, esquemas previos relevantes y variantes incompletas detectadas en las migraciones. Incluir fechas sin zona, columna fecha ausente, paymentMethod ausente/duplicable, nombres similares, producto eliminado, fila duplicada, cantidades negativas, costos desconocidos y snapshots sin movimiento.

Probar dos importaciones del mismo archivo; dos backups distintos del mismo origen; IDs iguales de negocios distintos; misma fila modificada; fallo tras cada grupo de entidades; destino con operaciones existentes; archivo corrupto; esquema desconocido; falta de espacio simulada; backup/restore sobre copia.

No usar copias reales para los primeros tests. Si más adelante se necesita comprobar compatibilidad real, trabajar solo con copias verificadas, con autorización y aislamiento; esta fase no solicita ni necesita abrir la base productiva.

## 7. Transición final

El POS original continúa operando durante el desarrollo. Solo después de pruebas, conciliación y validación expresa del propietario se definirá fecha de corte y procedimiento de transición. Se decidirá cómo cerrar/capturar las cuentas abiertas que el original no persiste. No se habilita sincronización bidireccional ni sustitución automática del sistema actual.
