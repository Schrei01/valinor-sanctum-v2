# Cuentas nuevas primero y correcciones de existencias — Desarrollo 0.34.0

Las cuentas nuevas de Ventas aparecen al principio. Su posición usa una fecha de creación independiente de la última edición: escribir, guardar, cobrar otras cuentas, navegar o reabrir no cambia su orden. La interfaz conserva los editores de las cuentas existentes al insertar una arriba. Las cuentas anteriores conservan sus datos y se ordenan entre sí por su orden de registro, sin inventar una fecha histórica de creación.

## Correcciones de Catálogo

El menú reservado de Catálogo, accesible por Ctrl+D, acepta un cambio con signo: `1` o `+1` suma una unidad; `-1` la resta. Muestra el saldo resultante antes de confirmar. Rechaza cero, fracciones, valores fuera de rango y descuentos que dejen existencias negativas. Permite descontar todas las unidades y recuperar existencias de un producto agotado. Los agotados siguen ocultos en el Catálogo normal y en Ventas; pueden elegirse dentro del menú para corregirlos. Servicios y eventos ilimitados quedan fuera.

Es una corrección de cantidad: no registra compras, ventas, pagos, deudas ni inversión, y no cambia el PVP, categoría o proveedor. Al sumar se conserva el último costo unitario registrado en una compra o apertura, redondeado a la unidad monetaria del perfil. No se ofrece otro campo al operador. Los costos cero expresamente registrados siguen siendo cero. Si un producto carece de todo antecedente de costo, se pide registrar su primer ingreso desde Compras en vez de inventar un costo.

Las unidades retiradas siguen consumiendo FIFO. Las sumadas generan una nueva capa FIFO al final del inventario, que puede venderse, usarse como premio o descontarse después. Las capas, precios y ventas anteriores conservan su historia. Los ajustes de valor usan la cuenta de Ajustes de inventario como contrapartida de Inventario; no son egresos de Caja/Nequi ni financiación del propietario. La corrección conserva el motivo opcional y la fecha.

Las solicitudes se guardan antes de confirmar. Reintentar recupera el mismo ajuste sin repetir unidades. Se revisan existencias, costo de referencia y cronología al confirmar. Un fallo revierte documento, capa, movimiento y asiento juntos; una solicitud pendiente puede descartarse si cambió su referencia. El atajo permanece limitado a Catálogo y no se anuncia en las pantallas normales.

## Persistencia y entrega

Esquema 21, 73 tablas. Añade `stock_additions` y `inventory_movements.stock_addition_id`, con tipo de movimiento `adjustment` sin línea de compra. Reutiliza las capas y asignaciones FIFO existentes. La migración reconstruye el padre de las capas difiriendo temporalmente sus claves foráneas dentro de la transacción, sin desactivarlas, y repone sus índices y guardas de inmutabilidad. Conserva todos los registros y solicitudes previos; las referencias nuevas son NULL para los movimientos anteriores.

`quick_sales_accounts.created_at_utc` es inmutable para cuentas nuevas. Las anteriores quedan con NULL, preservando la información existente. Las migraciones 1–20 y sus verificaciones permanecen intactas; la actualización de Desarrollo crea y verifica un respaldo SQLite anterior antes de aplicar 21.

Portable **Desarrollo 0.34.0+52** en `dist/ValinorSanctum2`, con la base de desarrollo independiente y acceso raíz habitual. Sustituye la entrega anterior de Desarrollo y conserva la última Producción 1.1.0, su instalador y archivos instalados. Este incremento no abre ni migra la base operativa de Documentos.

Las verificaciones ejecutadas se registran en [la evidencia sanitizada](evidence/corrections-034.json). Los respaldos, ensayos con datos locales, rutas privadas y capturas sintéticas quedan fuera de Git y del paquete.

La suite general terminó con 827 aprobadas, tres omitidas por permisos de enlaces y cuatro fallos. Se corrigió la copia de columnas hacia la fixture v12, se actualizaron las expectativas de posición, se conservó el editor con una clave en su contenedor y se completó el guardado en la prueba de su temporizador. La repetición final de todos esos casos y los módulos afectados aprobó 59 pruebas de aplicación más cuatro renders. No se atribuye una segunda suite completa verde. Las cuatro imágenes a 1280/400 píxeles fueron inspeccionadas. Análisis limpio y formato de 211 archivos sin cambios.

El ensayo privado y la migración activa 20→21 conservaron los valores anteriores de las 72 tablas, incluso tras abrir el ejecutable. Los respaldos manual y automático se verificaron por contenido; integridad correcta y cero violaciones de claves foráneas. No se ingresaron operaciones comerciales de prueba en la base activa. La consulta inmediatamente posterior al inicio encontró el bloqueo normal de arranque; se repitió en solo lectura con tiempo de espera y coincidió íntegramente.

El ZIP y el bundle coinciden en 19 archivos sin privados. Se retiró el ZIP anterior de Desarrollo y la limpieza quedó sin pendientes. Los 21 archivos de la entrega productiva, los 20 de su instalación y el selector/historial de desarrollo conservaron sus huellas. No se abrió la base de producción ni se cerró su ventana. Desarrollo quedó abierto y respondiendo con su título; la revisión visual utilizó renders sintéticos y no una inspección visual nativa nueva.
