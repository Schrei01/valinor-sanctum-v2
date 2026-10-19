# Preguntas de negocio, indicadores y recomendaciones

Estado: especificación propuesta. No hay resultados calculados del negocio ni datos reales en este repositorio.

## Convenciones de lectura

Los períodos se expresan como [inicio incluido, fin excluido), definidos en la zona del negocio y convertidos de forma consistente a instantes UTC. Una fecha comercial se conserva para agrupación local. Se comparan períodos equivalentes y se muestra si alguno está incompleto.

Cada indicador entrega valor o ausencia de valor, unidad, moneda, período, fuente, fórmula/versionado y calidad de datos: completo, parcial o no disponible. Un denominador cero no se convierte en porcentaje ficticio. Cero medido es distinto de falta de registros o información insuficiente.

Fuentes: documentos confirmados para detalle comercial; journal_lines para saldos y clasificación financiera; inventory_movements/cost_layers/cost_allocations para existencias y CMV. Las fuentes se concilian entre sí, pero no se suman para contabilizar dos veces el mismo hecho. Una reversa se netea con su origen según fecha efectiva; no se borra la operación.

## Matriz de preguntas y datos

| Pregunta | Datos mínimos / dimensión | Cálculo o criterio | Limitación que debe mostrarse |
|---|---|---|---|
| ¿Cuánto vendimos? | Ventas confirmadas, importes de línea, descuentos, devoluciones e impuestos separados | Brutas = importe antes de descuentos/devoluciones, sin impuestos trasladados; netas = brutas - descuentos - devoluciones | Anticipos/cobros no son ventas; definir inclusión de impuestos visible |
| ¿Cuánto cobramos? | payments, payment_parts, settlements y reversas | Entradas de cobro efectivas, clasificadas por origen y cuenta | No sumar ventas a crédito como dinero recibido; distinguir anticipos |
| ¿Qué categorías aportan ingresos? | Categoría histórica de sale_lines y ventas netas | Suma por snapshot de categoría y porcentaje del total | Sin categoría aparece explícitamente; no atribuir categoría actual a todo histórico |
| ¿Qué productos se venden más? | Producto/snapshot, cantidad y devolución | Unidades netas e ingreso neto; rankings separados | No comparar unidades heterogéneas sin aclaración |
| ¿Qué días/horas tienen actividad? | Instantes de ventas y fecha comercial/zona | Totales por día/hora; mediana o promedio con cobertura | Períodos con cierres/falta de datos no se etiquetan demanda cero sin contexto |
| ¿Cuánto vale el inventario? | Capas restantes y costos de recepción conocidos | Suma del costo remanente por capa al corte | Separar unidades con costo desconocido y valor parcial; no usar precio de venta |
| ¿Qué productos rotan más? | CMV del período y valor promedio de inventario | Rotación = CMV / inventario promedio valorizado | Promedio temporal de saldos diarios o ponderado por duración; si falta cobertura no inferir |
| ¿Cuánto tiempo llevamos sin vender? | Última venta, fecha primera recepción, disponibilidad | Días desde último movimiento de venta; separar nunca vendido | Ausencia de historial importado no prueba inactividad anterior |
| ¿Qué hay que reponer? | Stock disponible, reservas si existen y punto de reposición por producto | Disponible <= umbral configurado; agotado se señala como hecho | Sin parámetro no inventar nivel óptimo ni demanda futura |
| ¿Cuánto capital está inmovilizado? | Valoración y clasificación de antigüedad/inactividad | Valor de capas dentro del criterio elegido por usuario | No equiparar falta de venta con pérdida o deterioro confirmado |
| ¿Qué productos generan utilidad? | Ventas netas y costo histórico asignado | Contribución bruta = ingreso neto - CMV asignado | Costos faltantes impiden afirmar utilidad total; gastos comunes no se asignan sin criterio |
| ¿Qué margen tenemos? | Ingreso neto y costo histórico | Margen bruto = (ventas netas - costos directos) / ventas netas | Con ingreso cero, mostrar no aplicable; declarar cobertura del costo |
| ¿Cuánto dejan los servicios/eventos? | Venta de servicio, fulfillment/evento y costos directos vinculados | Ingreso neto reconocido - costos directos; detalle por evento | Anticipos de evento futuro no son ingreso reconocido; costos indirectos separados |
| ¿Cuáles son los gastos? | expenses y cuentas de gasto, período devengado y pagos vinculados | Suma por categoría y resultado operativo | Comprar mercancía o retirar capital no es gasto operativo |
| ¿Cuál es el resultado operativo? | Ingreso neto - CMV - costos directos de servicio - gastos operativos | Resultado antes de componentes financieros/fiscales no modelados | Explicitar alcance; separar partidas desconocidas y no operativas |
| ¿Qué dinero hay disponible? | Cuentas monetarias activas, asientos y último arqueo | Saldo libro por cuenta; efectivo contado y diferencia por separado | Un saldo sin conciliar no se presenta como contado |
| ¿Qué debemos cobrar/pagar? | obligations, tercero, vencimiento, liquidaciones, moneda | Saldo abierto y antigüedad por CxC/CxP | No confundir Deudas original con una clase específica sin revisión |
| ¿Cuánto podemos destinar a compras? | Saldos conciliados, compromisos por vencimiento, reservas definidas | Escenario: liquidez disponible - compromisos seleccionados - reserva del usuario | No garantía; cobros esperados y su incertidumbre separados, sin reserva predeterminada |
| ¿Por qué utilidad y caja difieren? | Resultado, CxC/CxP, stock, compras, capital, anticipos | Puente entre devengo y flujos; entradas/salidas por clase | Cobertura incompleta implica puente parcial; no forzar diferencia a cero |
| ¿Cómo evolucionan las ventas? | Períodos equivalentes, retornos y cobertura | Variación absoluta y porcentual si base distinta de cero | Base cero: informar cambio absoluto y porcentaje no definido |
| ¿Hay concentración de ingresos? | Ventas netas por producto/categoría/cliente cuando exista | Participación de cada dimensión y concentración configurada | Cliente no registrado se conserva como anónimo/desconocido |
| ¿Qué beneficio permitiría un escenario? | Ventas, proporción de costo variable y gastos introducidos por usuario | Resultado simulado bajo supuestos explícitos | No es pronóstico ni promesa; sin margen válido no calcular punto de equilibrio |
| ¿Qué ingreso requeriría una meta elegida? | Beneficio objetivo opcional, gastos, margen de contribución | Ingreso requerido = (gastos fijos + objetivo) / margen de contribución | Margen <= 0: sin solución bajo esos supuestos; no usar margen bruto si omite variables |
| ¿Qué pasa si suben costos/gastos o bajan ventas? | Escenario base y cambios configurados | Recalcular ventas/costos/gastos e intervalo de liquidez | No modificar hechos ni aplicar porcentajes económicos predeterminados |
| ¿Qué inversión de stock requeriría crecer? | Demanda hipotética, existencias, compra/costo, plazos/cobros/pagos | Unidades/costo incremental y calendario de caja bajo supuestos | Sin plazos/proveedores o demanda no estimar liquidez fiable |
| ¿Cómo vamos frente al presupuesto/objetivo? | Objetivo opcional, indicador, unidad, período y objetivo creado por usuario | Real comparable - objetivo; avance cuando matemáticamente procede | Si no hay objetivo, no crear brecha ni juicio de rendimiento |

## Motor determinista y explicable

Contrato de recomendación:

| Campo | Contenido |
|---|---|
| Identidad | ID estable de regla, versión y entidad afectada |
| Datos de respaldo | Indicadores, valores/unidades, IDs de hechos o consulta reproducible |
| Período | Inicio/fin y zona; instante de evaluación y de corte |
| Criterio | Fórmula, condición y parámetros efectivos; quién los configuró |
| Acción sugerida | Acción concreta y revisable, sin ejecución automática de compras/ajustes |
| Limitaciones | Cobertura, costos desconocidos, períodos incompletos y supuestos |
| Prioridad/estado | Severidad explicada; nueva, vista, descartada o resuelta |

Reglas iniciales:

| Regla | Evidencia y condición | Acción sugerida | Limitación / activación |
|---|---|---|---|
| Producto sin movimiento | Última venta o recepción y antigüedad mayor al período configurado | Revisar surtido, exposición o demanda | Requiere historial suficiente y período elegido |
| Existencias bajas | Disponible <= punto por producto | Revisar reposición y obligaciones de pago | Umbral no configurado: no recomendar cantidad óptima |
| Producto agotado | Disponible cero en producto activo | Revisar demanda y reposición | Es un hecho operativo; no implica rentabilidad |
| Margen decreciente | Dos períodos con costos completos y caída superior al criterio elegido | Revisar costos/precios y mezcla | Sin comparabilidad o costos, emitir limitación en lugar de señal falsa |
| Cambio de ventas | Variación respecto de período comparable y umbral configurado | Investigar calendario, eventos y disponibilidad | No atribuir causa automáticamente; tratar base cero |
| Concentración | Participaciones por dimensión y umbral elegido | Revisar exposición comercial | No imponer nivel aceptable de concentración |
| Posible falta de liquidez | Saldos/obligaciones y horizonte con supuestos visibles | Revisar calendario de pagos/compras/cobros | No contar CxC incierta como caja ni decidir retiro automáticamente |
| Descuadre | Conteo de arqueo distinto de saldo esperado | Investigar movimientos y registrar resolución autorizada | No corregir saldo automáticamente; cualquier diferencia es informada |
| Costos incompletos | Capas/líneas sin costo confirmado | Completar evidencia o limitar reporte | Costo desconocido nunca se completa usando el último precio |
| Información incompleta | Obligaciones sin vencimiento o registros en cuarentena | Completar clasificación y conciliación | No puede evaluar bien una obligación sin fecha |

Los umbrales comerciales no contienen metas predefinidas. La detección de inconsistencia objetiva (asiento desbalanceado, costos faltantes, conteo distinto) no requiere una meta económica. Si falta configuración para una regla comercial se muestra pendiente de configurar, no se inventa el parámetro.

El motor evalúa consultas inyectadas y políticas versionadas, devuelve explicaciones estructuradas y no modifica el libro. Una interfaz de analizador adicional permitirá otras capacidades en el futuro; los cálculos transaccionales seguirán siendo deterministas, verificables y utilizables sin red.

## Planificación y objetivos opcionales

Los escenarios guardan nombre, período, versión, moneda, referencias de base, parámetros introducidos, justificación y resultados derivados. Se distingue escenario base real, supuesto del usuario y dato no disponible. Guardar escenario no crea movimientos de dinero ni altera ventas.

Presupuestos y objetivos están vacíos al iniciar. No habrá cifra de salario, venta, margen, crecimiento o beneficio precargada. Cambiar/eliminar un objetivo conserva hechos y resultados históricos. Comparaciones y recomendaciones no presuponen cuál pregunta es prioritaria para el propietario.

Para validar fórmulas se usarán fixtures puramente sintéticos, identificados como pruebas; sus números no se convierten en parámetros del negocio ni metas del producto.
