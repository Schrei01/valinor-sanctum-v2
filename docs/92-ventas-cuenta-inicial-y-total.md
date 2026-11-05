# Ventas: cuenta inicial y total abierto — Desarrollo 0.41.0

Al abrir la app o entrar en Ventas, si no hay cuentas abiertas, se crea y guarda una cuenta vacía con una línea sin producto. Si ya hay una cuenta abierta, con cambios locales o pendiente de confirmación, se conserva. Entradas repetidas y cargas simultáneas no duplican el borrador. Si falla la lectura no se crea una cuenta por suposición; un guardado incierto conserva su identidad para reintentar.

La creación automática corresponde a la entrada en Ventas. Confirmar o quitar la última cuenta no crea otra inmediatamente: vuelve a aplicarse al entrar de nuevo. La acción manual Nueva cuenta sigue disponible y coloca las nuevas primero.

La cabecera muestra **Total cuentas abiertas** arriba a la derecha. Suma cantidad × precio de todas las líneas de las cuentas que aparecen abiertas, con sus cambios actuales, incluyendo pagos a deuda y divisiones. Se actualiza al editar, agregar, quitar o confirmar una cuenta. No suma el historial de ventas confirmadas ni confunde este total de consumo pendiente con dinero ya cobrado. Las líneas incompletas conservan el criterio de los totales de cada cuenta.

La suma usa BigInt para evitar desbordamientos; fuera del rango monetario muestra Revisa cantidades. En ventanas pequeñas el resumen pasa debajo de los controles, alineado a la derecha. Conserva el estilo común de los totales, con título e importe debajo.

Es Desarrollo **0.41.0+73**, esquema 23/74 tablas, sin migración. Producción **1.5.0** y su instalación permanecen separadas. El arranque puede añadir únicamente el borrador vacío y su línea cuando la base de Desarrollo no tenga cuentas abiertas; no registra una venta ni modifica caja, deuda o inventario.

Validación: pruebas de controlador, interfaz, navegación, recuperación de guardados y entradas concurrentes; renders sintéticos de 1280 y 400 píxeles. La prueba de conservación ensaya el controlador real con SQLite sobre una copia privada de Desarrollo, compara todas las filas y el esquema y permite únicamente el borrador inicial previsto. La fuente se respalda antes de publicar y se verifica otra vez al abrir el nuevo ejecutable. Evidencia final en [sales-041.json](evidence/sales-041.json).

Se entrega por rama y Pull Request para revisión del propietario. El CI completo y su conformidad son requisitos antes de integrar; preparar la portable de Desarrollo no implica publicar Producción.

Resultados locales: 63 pruebas de aplicación aprobadas, más ensayo privado y verificación del arranque activo con SQLite. En esta base ya había cuentas abiertas, por lo que se conservaron y no se creó ninguna adicional; filas y esquema de las 74 tablas idénticos después de abrir. Integridad y claves foráneas correctas. Dos renders inspeccionados; sin inspección visual nativa. Análisis limpio y formato de 217 archivos sin cambios; sin suite completa local nueva.

Release de Desarrollo compilada y publicada para revisión, con 19 archivos idénticos en ZIP y bundle estable, sin datos privados. Se retiró la portable anterior y la limpieza quedó sin pendientes. Las 43 huellas de archivos de Producción, instalación vigente y selector/JSON de Desarrollo permanecen iguales. Desarrollo quedó abierta y responde; la base productiva no fue consultada.
