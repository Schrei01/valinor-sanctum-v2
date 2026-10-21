# Nequi en Compras y Transferencia en Ventas — 0.13.2

La aclaración del propietario sitúa el cambio de nombre en **Ventas**. Se restaura **Nequi** en Compras y se muestra **Transferencia** en la selección de pago por línea, el resumen por forma de pago y el historial de Ventas. Las otras opciones siguen siendo Efectivo y Deudas.

Compras muestra Nequi en selección, pendientes, saldo inicial, avisos e historial. Tesorería y Cobros también conservan Nequi.

Transferencia en Ventas usa la misma cuenta y medio de pago de Nequi. El alias se aplica al mostrar los datos: no modifica IDs, nombres guardados, snapshots, solicitudes preparadas ni respuestas históricas. No hay migración; el esquema sigue en v11 y el cambio no altera dinero, inventario ni deudas.

Las pruebas de formulario existentes seleccionan Transferencia y comprueban el resumen e historial de Ventas, mientras los IDs y etiquetas guardadas conservan Nequi. Compras vuelve a seleccionar y mostrar Nequi en esas mismas pruebas.

## Verificación y entrega

- **53 pruebas enfocadas aprobadas**, sin fallos: 52 de formularios/controladores de Ventas y Compras y una de almacenamiento que conserva snapshots preparados tras renombrar opciones. No se repitió la suite completa.
- Análisis limpio, nueve Dart modificados con formato limpio y revisión independiente sin hallazgos pendientes.
- Comparación de solo lectura antes y después en las **49 tablas** propias: todos los registros, saldos e inventario idénticos. Esquema v11 sin migración, integridad correcta y cero violaciones FK.
- Bundle Windows final **0.13.2+20**, sin configuraciones de prueba, publicado en **Iniciar Valinor Sanctum.cmd**, ZIP y copia versionada 0.13.2. Los 17 archivos extraídos del ZIP coinciden por SHA256 con la ruta estable; no incluyen bases ni datos privados.
- La app final abrió y mostró la navegación por accesibilidad. Los nombres por pantalla se comprobaron en widgets; no se repitió el recorrido nativo de formularios ni se capturaron imágenes. Sin operaciones de prueba en el perfil propio; ventana abierta para el propietario.

Evidencia: [sales-transfer-label.json](evidence/sales-transfer-label.json).
