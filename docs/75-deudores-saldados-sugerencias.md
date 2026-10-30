# Deudores con saldo y nombres anteriores — Desarrollo 0.36.0

La lista principal y su búsqueda muestran solo personas con deuda pendiente. Pagar toda la deuda retira a la persona de esa lista, pero conserva su registro, historial y disponibilidad en Ventas según su estado de fiado. El total mantiene el mismo cálculo; también incluye la cartera pendiente sin asignar.

Registrar persona sugiere los nombres guardados, incluidas las personas con saldo cero y las que tienen el fiado bloqueado. Al seleccionar una sugerencia se muestra su saldo y la acción Ver cuenta. Esa acción consulta la cuenta original sin crear una persona, registrar una deuda ni habilitar fiado. Desde el detalle se conserva el acceso a historial y acciones existentes.

Escribir exactamente un nombre guardado produce el mismo resultado, ignorando mayúsculas y espacios repetidos de acuerdo con la normalización existente de la base. Si se cambia a un nombre nuevo, reaparecen el formulario de alta y la opción de deuda anterior, con sus validaciones habituales. Los campos de deuda anterior se ocultan al elegir una cuenta existente para evitar registrar otra apertura por accidente.

El cambio se limita a la presentación de Deudores. El almacenamiento sigue devolviendo todos los titulares para Ventas y las demás consultas. Sin migración ni cambios financieros: esquema 21, 73 tablas. Entrega portable Desarrollo 0.36.0+55, separada de Producción 1.2.0.

La evidencia de verificación y entrega está en [debtors-036.json](evidence/debtors-036.json). Capturas sintéticas, respaldos y datos locales permanecen fuera de Git y del paquete.

Pasaron 29 pruebas de aplicación y seis renders sintéticos, inspeccionados a 1280 y 400 píxeles. Cubren ocultar saldo cero en lista y búsqueda, conservar total e historial, sugerir personas saldadas/bloqueadas, abrir la identidad original sin comandos nuevos, mantener el bloqueo de fiado, reconocer nombres normalizados, registrar una persona nueva y reutilizar una cuenta tras pagarla por completo. También se verificó la selección de titulares en Ventas. Análisis limpio y formato de 213 archivos sin cambios finales; no se repitió la suite general.

Respaldo manual verificado por contenido; las definiciones y filas de las 73 tablas de desarrollo coinciden antes y después del inicio nativo. Integridad correcta, cero violaciones de claves foráneas y ninguna operación comercial de prueba en la base activa. ZIP y bundle coinciden en 19 archivos sin datos privados. Se retiró la entrega anterior de Desarrollo y la limpieza no tiene pendientes.

Los 21 archivos de distribución productiva, 20 de su instalación y el selector/historial de desarrollo conservaron sus huellas. No se abrió la base productiva ni se cerró su ventana. Desarrollo quedó abierto y respondiendo con su título; la revisión visual usa los renders sintéticos, sin atribuir una inspección visual nativa nueva.
