# Pruebas de una jornada comercial — 27/10/2026

Validación funcional de la versión 0.26.1, con bases sintéticas separadas y configuración COP con 0 decimales. No se modifican datos de la ludoteca activa ni se publica un ejecutable nuevo por añadir pruebas.

## Jornadas integradas

`business_day_stress_test.dart` repite una jornada de 20 cuentas con tres órdenes deterministas de cierre: semillas 17, 83 y 2026. Son 60 cuentas en total. Cada jornada utiliza un archivo SQLite propio, cinco titulares con deuda anterior y un inventario inicial de 310 unidades preparado como fixture.

1. Abre cinco cuentas con líneas en Efectivo, Transferencia, Deudas y combinaciones de los tres medios.
2. Cobra primero la cuenta 2 y después la 4. Conserva las demás sin descontar su stock por adelantado.
3. Crea una liga con costo fijo desde Caja y dos unidades del catálogo como premios; verifica que el evento aparezca en el catálogo operativo y en las opciones de Ventas.
4. Transfiere dinero de Caja a Nequi, registra un gasto de aseo desde Nequi y recibe un abono parcial a una persona.
5. Abre la sexta cuenta después de los dos primeros cobros. Cierra y reabre el archivo, y comprueba cuentas, pagos por línea y saldos.
6. Reabre también con una venta preparada; la recupera y repite confirmaciones de venta, transferencia y abono para comprobar que no se duplican.
7. Continúa con nuevas cuentas hasta completar 20, con tres inscripciones a la liga, y cierra las restantes en orden mezclado.
8. Después de cada venta compara Caja, Nequi, deuda total y por persona, stock, cuentas abiertas e historial con un cálculo independiente. Verifica que todos los asientos tengan débitos y créditos iguales.

### Resultado esperado y comprobado por jornada

Todos estos importes son sintéticos; no corresponden a los saldos reales de Valinor.

| Concepto | Resultado |
|---|---:|
| Cuentas vendidas | 20 |
| Venta de productos e inscripciones | COP 75.000 |
| Parte vendida a Deudas | COP 20.000 |
| Cartera inicial de prueba | COP 10.000 |
| Abonos recibidos | COP 400 |
| Cartera final | COP 29.600 |
| Caja final | COP 34.700 |
| Nequi final | COP 20.100 |
| Transferencia interna | COP 200 |
| Egresos monetarios: evento y aseo | COP 600 |
| Stock inicial | 310 unidades |
| Premios retirados al crear el evento | 2 unidades |
| Productos vendidos | 60 unidades |
| Stock final | 248 unidades |
| Costo FIFO del stock restante | COP 248.000 |

Reportes debe coincidir con ventas, ventas a deuda, abonos, transferencias, egresos y deuda al cierre. La integridad SQLite y las claves foráneas deben terminar correctas.

## Interfaz y pestañas

`business_navigation_test.dart` conecta los widgets reales con SQLite. Abre cinco cuentas, cobra 2 y 4 usando los botones, abre una sexta con inscripciones a un evento y recorre Catálogo, Compras, Deudores, Tesorería, Eventos, Reportes y Ventas tres veces. Comprueba que permanecen los identificadores, las líneas, la cantidad y el titular, que el evento aparece en Catálogo y que sus inscripciones están disponibles en Ventas. Luego reconstruye la interfaz y comprueba otra vez los borradores persistidos y los dos cobros confirmados.

## Regresión y alcance

Se ejecuta la suite completa para añadir cobertura de compras de contado, gastos, fondos insuficientes, competencia por stock, agotados, errores con rollback, recuperación, bloqueos e historia inmutable.

Estas son pruebas automatizadas de servicios con SQLite y de interfaz Flutter. Las reaperturas son cierres ordenados y recuperación de operaciones preparadas; no simulan fallos físicos del disco ni cortes eléctricos. No son una medición de rendimiento con múltiples equipos conectados.

La suite completa terminó con **755 pruebas aprobadas, cero fallos y tres omitidas** porque el host no permite crear los enlaces simbólicos necesarios para esas pruebas de rutas. No se encontraron inconsistencias en los escenarios comerciales ejecutados. El formato de 192 archivos Dart no requirió cambios.

Tras agregar dos pares de llaves que pidió el analizador en los archivos nuevos de prueba, se repitieron los cuatro casos nuevos: todos aprobados. No se modificó código de la aplicación.

Análisis estático final sin incidencias. Se conservan las pruebas como regresión y se publican con este informe en Git; no se genera una versión ni un bundle nuevos. Evidencia sanitizada en `docs/evidence/business-stress.json`.
