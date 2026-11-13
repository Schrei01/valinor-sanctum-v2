# Mes de nacimiento — Desarrollo 0.50.0

Registrar persona y Editar datos en Membresías ofrecen **Enero** a **Diciembre**, además de **Sin especificar**. Al abrir una persona o seleccionarla del listado se carga el mes que ya tenía. La base sigue guardando un número1–12 o null; no hay migración, conversiones de cumpleaños previos ni cambios de esquema29. Se conserva la validación conjunta de día/mes del almacén.

Los dos widgets existentes, a1120/400 píxeles, comprueban selección de Marzo y envío del valor3, precarga de Junio en edición y limpieza a null al elegir Sin especificar y borrar el día. Se inspeccionaron el menú en ventana estrecha y el formulario amplio. Formato/análisis y Release se verifican antes de entregar el portable. Producción1.9.0 permanece independiente; esta revisión se entrega en Desarrollo para revisión y mediante PR hacia main, con CI completo requerido antes de integrar.

Portable0.50.0+88 publicado y abierto para revisión; formato247 sin cambios, análisis limpio y Release correcta. Se retiró el ZIP anterior de Desarrollo y se preservaron39 huellas de la distribución/instalación productiva. [Evidencia](evidence/membership-month-050.json).
