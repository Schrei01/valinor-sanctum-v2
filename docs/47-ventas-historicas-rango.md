# Ventas antiguas y nuevas en el rango — 0.19.1

El propietario aclaró que busca consultar las ventas de ambas estructuras para obtener el importe vendido en el rango introducido. Este ajuste amplía la política de 0.19.0: para las antiguas con producto y precio disponible se calcula **cantidad × PVP conservado en la copia**, identificado como estimación. Las ventas nuevas siguen usando su importe exacto registrado.

La consulta une `legacy_source_rows` de sales con la fila de products correspondiente a su `productId` y conversión. Es una unión de lectura sobre el archivo inmutable ya incluido en la base de la app. No requiere abrir el archivo externo original, crear una tabla/vista persistente ni trasladar ventas al libro operativo. Un cambio del catálogo actual no modifica esta estimación.

Los dos orígenes alimentan el mismo resumen visible de Caja, Nequi/Transferencia, Deudas y Total vendido. Se filtran por el mismo rango de Bogotá, desde el comienzo del minuto inicial hasta terminar el minuto final. No se suman abonos, transferencias internas, aperturas, compras ni gastos como nuevas ventas. El detalle interno usado por las gráficas anteriores sigue siendo nativo; las gráficas y los listados detallados no se amplían en esta entrega.

El desglose conserva por separado importes nativos, estimados y cantidades de registros no calculables. La pantalla suma lo calculable y señala cuánto corresponde a estimaciones. Si faltan productos, cantidades válidas o precios representables, indica **parcial** y cuántos registros siguen **Sin información**; no presenta ese subtotal como un total completo. Cuando no hay ningún importe calculable y falta información, mantiene Sin información. Un rango sin ventas devuelve cero.

Para probar el historial de la copia, selecciona **18/10/2026, 12:00 AM** como inicio y **18/10/2026, 11:59 PM** como final, y pulsa Generar reporte. Ese rango contiene ventas antiguas calculables verificadas. Los rangos posteriores sin ventas registradas mostrarán cero.

La cantidad se multiplica con enteros de precisión arbitraria y el precio se convierte exactamente a la escala del perfil, sin redondear ni calcular dinero en coma flotante. Un PVP archivado cero es válido. Se rechazan desbordamientos del agregado. Los precios o cantidades inválidos quedan fuera del cálculo, con su falta de información identificada.

Esquema14, sin migración ni tablas nuevas. No se recalculan saldos ni se vuelven a descontar productos, dinero o deudas. La base operativa y el archivo histórico permanecen intactos.

## Verificación

43 pruebas enfocadas de integración, dominio, controlador e interfaz aprobadas. Después de añadir la comprobación de cambio del PVP actual, se aprobaron siete casos de conversión y una captura sintética. La ejecución final de dominio/interfaz y captura aprobó otros 13 casos; son repeticiones, no 64 casos distintos. Entre las ejecuciones se verificaron 43 casos distintos de aplicación y un render sintético. Se inspeccionaron imágenes amplia y estrecha y el análisis final no tiene incidencias. No se repitió la suite financiera completa ni se afirma un recorrido nativo nuevo.

Las pruebas incluyen cantidades por precio archivado, mezcla con ventas nuevas, precio actual modificado sin alterar historia, producto eliminado, canales de pago, abonos y transferencias excluidos, minutos límite, conservación del reporte anterior y desbordamiento del agregado nativo más estimado.

La base real se consultó únicamente mediante herramientas de solo lectura para obtener un respaldo consistente. El lector Flutter se ejercitó en esa copia privada. Siete rangos se contrastaron con un cálculo independiente: coinciden importes estimados, cantidades de registros y cobertura. Se pueden calcular 4.153 de las 4.305 ventas antiguas; 152 carecen de producto. Las 63 tablas y el esquema de la copia permanecen idénticos tras consultar. Detalles de datos y respaldos privados quedan fuera de Git y del ZIP.

## Entrega

Release Windows 0.19.1+30 compilado sin overrides y publicado después del cierre confirmado por el propietario. ZIP, acceso estable y copia versionada coinciden en sus 17 archivos; datos privados excluidos. La carpeta y el ZIP anteriores de 0.19.0 se eliminaron según la política de retención.

Respaldo consistente de la base cerrada verificado en `backups/report-history-20261027`. Tras publicar, las 63 tablas y el esquema permanecen íntegramente idénticos; integridad correcta, cero FK, esquema14 y escala0. La app se deja cerrada, sin operaciones de prueba sobre sus datos ni recorrido nativo nuevo. Abrir con `Iniciar Valinor Sanctum.cmd`. Ver [evidencia](evidence/report-history.json).
