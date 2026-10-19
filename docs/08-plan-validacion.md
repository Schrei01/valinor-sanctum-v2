# Plan de implementación y estrategia de validación

Estado: etapa 3 completada; 4A parcial (catálogo y recepción a crédito) y primera parte de 4B implementada (cuentas persistidas y ventas a crédito con stock, costo, deuda y asiento). Ajustes, cobros, pagos y etapas restantes siguen pendientes. Resultados anteriores en [incremento 02](13-incremento-02.md); alcance actual en [contrato 03](14-contrato-incremento-03.md).

## 1. Prioridades y puertas de avance

P0 en este plan significa requisito previo al uso operativo, no severidad de un hallazgo del original. Primero aislamiento e integridad; después amplitud funcional e inteligencia. No se fija una fecha de lanzamiento sin medir avances.

| Etapa | Incremento y entregable | Criterio verificable para avanzar | Estado |
|---|---|---|---|
| 1. Auditoría | Inventario funcional/técnico, esquema y migraciones, riesgos, reutilización | Fuente inspeccionada y evidencias enlazadas; original sin cambios | Completada por análisis estático |
| 2. Diseño | Arquitectura, datos, matriz negocio, importador futuro y plan | Propietario aprueba enfoque y decisiones de núcleo | Aprobado el 18/10/2026 |
| 3. Proyecto nuevo | Flutter Windows mínimo, Git propio, composición, configuración y SQLite exclusivos, migración inicial | Arranca/cierra/reabre perfil sintético; rutas originales inaccesibles para escritura; pruebas de esquema | Completada para la fundación 0.1.0: perfil persistido, reapertura y diagnóstico del bundle final verificados |
| 4A. Catálogo/entradas | Productos/categorías, compras/proveedores, recepción y capas, ajustes | Stock y valoración reconstruibles; compras diferenciadas de gastos | Parcial: catálogo y recepción a crédito implementados y probados; ajustes pendientes |
| 4B. Venta/pago | Cuenta persistida, venta confirmada, precio/costo histórico, cobro y obligaciones | Venta completa atómica, doble clic/reintento seguro, cierre/reapertura sin pérdida | Parcial: cuentas y ventas a crédito; cobros pendientes |
| 4C. Tesorería | Cuentas/medios, apertura, gastos, transferencias, capital, abonos, arqueo | Saldos desde libro y conciliación; transferencias no alteran resultado | Pendiente |
| 4D. Servicios/eventos | Cumplimiento/consumo de servicios, eventos, torneos/pasadías, costo directo, anticipos | Reconocimiento y costo conforme a estados, sin ventas ficticias de stock | Pendiente |
| 5. Reportes | Ventas/cobros, CMV, bruto/operativo, caja, CxC/CxP y stock | Resultado conciliado con hechos y cobertura; sin recalcular pasado con catálogo | Pendiente |
| 6. Inteligencia | Tendencias, rotación, inactividad, concentración y alertas explicables | Reglas reproducibles con período, evidencia, criterio y límites | Pendiente |
| 7. Planificación | Escenarios, presupuestos y objetivos opcionales | Supuestos editables y aislados; sin metas económicas predefinidas | Pendiente |
| 8. Compatibilidad | Adaptadores y simulación de importación de backups | Pruebas de esquemas, idempotencia entre backups, conciliación y reversión | Pendiente |
| 9. Validación integral | Flujo completo, duración, rendimiento, instalador y recuperación | Evidencias de checks, instalación independiente y aceptación del propietario | Pendiente |
| Transición | Corte e importación aceptada | Validación expresa del propietario y conciliación final | No autorizada en esta fase |

Antes de utilizarlo para operar deben estar completos los flujos que el negocio necesite, las reversas y la recuperación. Un núcleo técnico que arranca no equivale a reemplazo del POS original.

## 2. Decisiones que se registrarán con la aprobación

- Flutter Desktop/Windows + SQLite local y monolito modular.
- Libro interno automático y separación entre medio de pago y cuenta monetaria.
- FIFO por capas, conservación exacta de costo total y manejo explícito de costos desconocidos.
- Moneda y escala inicial; propuesta COP con enteros y parser/formato definidos.
- Cuenta abierta persistida, borrador sin efecto y entrega/consumo confirmado como venta a cobrar.
- Permisos iniciales y alcance de operación de una estación.
- Alcance inicial de servicios/eventos, impuestos y devoluciones.

El significado de Deudas original y los saldos de apertura reales se resolverán antes de compatibilidad/transición, sin bloquear los tests sintéticos de un núcleo nuevo.

## 3. Herramientas y CI del nuevo repositorio

No copiar la configuración defectuosa ni ejecutar el pipeline del original. En la etapa 3 se fijarán SDK/dependencias y comandos reproducibles en el repositorio nuevo. La falta de Flutter/Dart en PATH debe resolverse antes de afirmar que el ejecutable funciona; si se incorpora un SDK portable se ubicará dentro del nuevo directorio y no modificará configuración global durante este encargo.

Checks previstos del nuevo proyecto: formato sin escritura, analyze, pruebas unitarias/integración/widgets y build Windows en un entorno con herramientas verificadas. Cada PR/cambio ejecutará los checks pertinentes; publicación solo después de esos resultados. No se desactivará una prueba para ocultar una falla.

El instalador usará rutas relativas, identificador único y artefactos generados fuera del control de versiones. Los binarios, bases, copias reales, logs de operación y secretos no se incluirán en Git.

## 4. Matriz de pruebas esenciales

Los números usados por las pruebas serán fixtures sintéticos, no parámetros económicos del producto.

| ID | Nivel | Escenario | Resultado exigido |
|---|---|---|---|
| T01 | Integración SQLite | Crear base desde cero y abrir todas las funciones | Esquema completo e idéntico al esperado, incluidas fechas y claves |
| T02 | Integración SQLite | Migrar cada versión propia soportada; fallar una migración | No pérdida de datos; rollback/recuperación; no archivo parcial presentado como válido |
| T03 | Unidad | Parsear dinero local, separadores, exceso de precisión, límites y valores no finitos | Valor exacto o error explícito; sin double ni redondeo oculto |
| T04 | Unidad/integración | Repartir costo de capa entre ventas y devoluciones | Suma de asignaciones + costo remanente = costo original exactamente |
| T05 | Integración | Confirmar venta con producto repetido y stock conjunto insuficiente | Ninguna venta/cobro/asiento/stock parcial; stock no negativo |
| T06 | Integración | Dos comandos sobre última unidad disponible | Solo uno confirma; otro informa disponibilidad vigente |
| T07 | Integración | Inyectar fallo después de cabecera, línea, stock, pago y asiento | Rollback completo en cada punto |
| T08 | Integración/widgets | Doble clic, timeout y reintento con misma solicitud | Un solo documento/efecto; resultado estable; distinto payload rechazado |
| T09 | Integración | Cambiar precio/costo/categoría y archivar producto vendido | Ventas/margen históricos y snapshots permanecen iguales |
| T10 | Integración | Cerrar/reabrir con cuenta abierta; error de cobro | Borrador recuperable; no perder consumos ni anunciar éxito sin commit |
| T11 | Integración | Venta a crédito y cobros parciales por distintos medios | Ingreso se reconoce una vez; saldo CxC y efectivo concilian |
| T12 | Integración | Sobrepago/cobro repetido/moneda incompatible | Rechazo o anticipo expresamente modelado; no saldo imposible |
| T13 | Integración | Compra de stock pagada y luego venta | Compra afecta inventario/caja; CMV solo al vender; gasto no duplicado |
| T14 | Integración | Compra a crédito y pago posterior | CxP cierra sin registrar nuevamente costo/gasto |
| T15 | Integración | Gasto devengado pendiente y pago posterior | Resultado por devengo y flujo por pago, sin doble conteo |
| T16 | Integración | Transferencia fallida en segunda partida; aporte y retiro | Transferencia completa o nada; capital fuera del resultado |
| T17 | Integración | Devolución parcial, reversa de cobro y anulación | Relaciones con original; límite por unidades/montos y costos originales |
| T18 | Integración | Arqueo con diferencia y ajuste aprobado | Esperado/contado/diferencia visibles y ajuste con actor/motivo |
| T19 | Unidad/integración | Costos desconocidos o período incompleto | Indicadores parciales/no disponibles y cobertura, nunca falsa ganancia |
| T20 | Unidad | Rotación con inventario cero o historial insuficiente | No división inválida ni rotación inventada |
| T21 | Unidad/integración | Días completos y límite exacto de períodos | Un hecho no aparece dos veces entre períodos contiguos |
| T22 | Unidad | Regla con evidencia insuficiente/umbral no configurado | Limitación o pendiente de configurar; recomendación reproducible |
| T23 | Unidad | Escenario y objetivo opcional | No modifica hechos; fórmulas con denominadores válidos; sin metas precargadas |
| T24 | Integración | Backup/restauración de base propia activa sobre copia | Snapshot íntegro y restaurable, sin perder WAL |
| T25 | Integración | Importar mismo backup y luego otro del mismo origen | Sin duplicar catálogo, aperturas ni hechos |
| T26 | Integración | Legado con huérfanos, negativos, fechas/costos ausentes | Cuarentena y reporte; no completar hechos con suposiciones |
| T27 | Integración | Fallo de importación y verificación de fuente | Destino sin parcialidades; hash de respaldo fuente igual |
| T28 | Integración | Base original como ruta/symlink/fallback | Rechazo; no apertura con permiso de escritura |
| T29 | Widgets | Cambiar texto después de seleccionar producto | Se limpia/revalida ID; nunca cobrar selección invisible anterior |
| T30 | Widgets | Operación ocupada, error recuperable y navegación | Estado coherente, botón controlado, ningún descarte silencioso |
| T31 | Integración | Operador sin permiso para ajuste/retiro/importación | Rechazo en caso de uso y auditoría adecuada |
| T32 | Escritorio | Instalar/desinstalar 2.0 junto al original | Nuevos IDs/rutas; sin sobrescribir original ni sus datos |
| T33 | Integración | Interrumpir proceso durante confirmación y reabrir | Estado comprometido completo o ausente, sin recreación destructiva |
| T34 | Integración | Segunda instancia mismo perfil y errores de bloqueo | Concurrencia controlada, fallo recuperable y sin duplicados |
| T35 | Integración | Anticipo de evento y posterior prestación/cancelación | Anticipo como obligación hasta reconocer servicio; reembolso trazable |
| T36 | Integración | Reintentar un comando después de otros movimientos | Respuesta persistida idéntica, incluidos saldos al commit original |
| T37 | Unidad/integración | Líneas gratuitas en venta positiva y documento de total cero | Primera operación coherente; segunda rechazada en alcance inicial sin obligación/pago ficticio |
| T38 | Integración | Reservar, liberar y consumir stock con reservas de otras cuentas | Reservas <= existencia vendible; disponible no negativo; consumo atómico |

Además de casos concretos, probar invariantes sobre secuencias sintéticas: libro siempre balanceado por moneda; stock/costo remanente no negativos; obligaciones no se liquidan dos veces; misma solicitud no repite efectos. No se necesitan tests que reproduzcan getters o layouts triviales; priorizar reglas y fallos.

## 5. Rendimiento y estabilidad

No se inventan umbrales de rendimiento. Medir con datasets sintéticos de tamaños crecientes y una máquina de referencia documentada; fijar criterios de aceptación con el propietario según tiempos de uso. Revisar planes SQL e índices por consultas reales, paginación de historiales y estabilidad de operaciones largas.

Una prueba prolongada incluirá aperturas/cierres, ventas concurrentes simuladas, recepción/devoluciones, reporte mientras hay escritura y backups. Registrar versiones, dataset, máquina, duración y fallos reales. No certificar estabilidad por una única compilación.

## 6. Aceptación del núcleo operativo

Antes de considerarlo utilizable:

1. Alta/recepción → venta → pago mixto o crédito → gasto/transferencia → arqueo → reporte concilian con registros.
2. Cambiar catálogo no cambia ventas previas; todas las devoluciones/reversas enlazan al original.
3. Cierre inesperado y reintento no pierden ni duplican cuentas o dinero.
4. Las cantidades, obligaciones y saldos se reconstruyen desde hechos, sin setters manuales.
5. Datos desconocidos y objetivos ausentes se muestran correctamente.
6. Instalación, almacenamiento, backups y desinstalación son independientes.
7. Las pruebas pertinentes y el build fueron ejecutados y tienen evidencia.
8. El propietario valida flujos de su negocio antes de autorizar transición.

## 7. Informe requerido al final de cada incremento

- Archivos agregados/modificados y propósito.
- Funcionalidad comprobable entregada.
- Decisiones y cambios respecto de arquitectura.
- Comandos/checks ejecutados y resultados reales; bloqueos del entorno.
- Riesgos, limitaciones y siguientes funcionalidades.
- Confirmación de no escritura en el original cuando se lo haya consultado.

El [registro documental inicial](09-verificacion.md) conserva la auditoría histórica; la [validación Windows](11-validacion-windows.md) documenta la fundación 0.1.0 y el [incremento 02](13-incremento-02.md), catálogo y recepción 0.2.0.
