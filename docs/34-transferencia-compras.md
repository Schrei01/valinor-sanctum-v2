# Transferencia en Compras — 0.13.1

El historial de Compras todavía mostraba **Pagada · Nequi**, incluso para ingresos nuevos. Ahora presenta **Pagada · Transferencia**, igual que el selector **Pagar desde**, los formularios pendientes y el saldo inicial. El aviso de cuenta no disponible también usa Transferencia.

El cambio se aplica al mostrar los datos: las compras nuevas y anteriores conservan su etiqueta original en SQLite, la misma cuenta monetaria y el mismo medio de pago. No se reescribe el historial ni se modifican saldos, inventario o documentos. El esquema sigue en v11. Ventas, Tesorería y Cobros conservan el nombre Nequi.

La prueba de formulario existente comprueba que se vea **Pagada · Transferencia** y que el dato guardado siga siendo **Nequi**.

## Verificación y entrega

- **39 pruebas enfocadas aprobadas**, sin fallos: formularios, controlador y almacenamiento de Compras. No se repitió la suite completa para esta corrección de texto.
- Análisis limpio y cuatro Dart modificados con formato limpio.
- Base propia comparada antes y después en modo lectura: las **49 tablas** y todos sus registros permanecen idénticos; esquema v11, saldos e inventario intactos. Integridad correcta y cero violaciones FK.
- Bundle Windows final **0.13.1+19** publicado en **Iniciar Valinor Sanctum.cmd**, ZIP y copia versionada 0.13.1. Los 17 archivos extraídos del ZIP coinciden con la ruta estable; se excluyen datos privados.
- La app final abrió y se observó su navegación por accesibilidad. El foco permaneció en la ventana y no se pudo confirmar el recorrido por teclado hasta Compras; el comportamiento del formulario y el historial se verificó en widgets. No se capturaron imágenes ni se enviaron operaciones de prueba. Ventana abierta para el propietario.

Evidencia: [purchase-transfer-label.json](evidence/purchase-transfer-label.json).
