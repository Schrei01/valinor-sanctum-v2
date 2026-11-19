# Compras: conservar el PVP anterior — Desarrollo 0.53.0

Al seleccionar un producto existente, Compras carga su PVP unitario registrado y lo conserva al cambiar costo total o unidades. Antes, lo cargaba pero lo dejaba en modo automático, de modo que el siguiente cambio de costo o cantidad lo sustituía por la sugerencia calculada.

El precio precargado se trata como una elección, igual que al pulsar **Usar valor**. Puede editarse libremente y la edición manual se conserva. Seleccionar otro producto carga el precio registrado de ese producto, incluido cero. La sugerencia sigue visible como referencia; los productos nuevos mantienen el cálculo automático hasta que el operador escribe su PVP.

Versión `0.53.0+93`, esquema29 sin migración ni cambios de almacenamiento. Este ajuste solo afecta el formulario; los precios, compras, dinero e inventario se modifican al registrar una compra mediante el flujo existente. Se preserva Producción1.11.0 y sus datos; la entrega de Desarrollo y el PR quedan para revisión antes de integrar.

La prueba existente de reposición reprodujo el reemplazo del precio antes de la corrección. Tras el ajuste se aprobaron24 pruebas locales de Compras y etiquetas de edición: precio anterior conservado con costo/cantidad cambiantes, edición manual y recarga, precio previo cero, cambio de producto, nuevos productos con sugerencia, compras múltiples y recuperación de solicitudes. La suite completa corresponde al CI del PR; las24 pruebas locales no la sustituyen.
