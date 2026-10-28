# Forma de pago de la cuenta — 0.30.0

La forma de pago se elige junto al total de cada cuenta de Ventas. Se retiran los selectores de las líneas para evitar que varios controles compitan por el mismo pago.

## Uso

El selector **Efectivo / Transferencia / Deudas** aplica a toda la cuenta. Las líneas nuevas heredan esa selección. **Dividir cuenta** permite repartir su total entre esos medios y hereda la persona del encabezado para la parte fiada.

Al guardar el reparto, el selector queda deshabilitado con **Pago dividido**. **Editar división** abre los importes guardados. **Volver a pago único** elimina el reparto, conserva el titular y habilita el selector vacío: es necesario elegir un medio antes de registrar. Cancelar el cuadro no cambia los pagos.

Cambiar productos, cantidades, precios o líneas después de dividir deja el reparto pendiente de revisión. **Registrar venta** queda bloqueado hasta guardar nuevamente la división o volver a pago único. Esta condición se conserva al cambiar de sección y reabrir. El control compara el contenido de la cuenta, no solo su total; detecta modificaciones que mantienen la misma suma. Si se restaura exactamente el consumo revisado, vuelve a coincidir con su revisión.

Mientras se revisa, se ocultan los resúmenes del reparto anterior para no confundirlos con el nuevo total. Editar o volver a seleccionar un producto conserva los importes guardados para su revisión.

La deuda requiere una persona activa asociada en el encabezado. No se vuelve a pedir dentro del cuadro. Transferencia sigue abonando a Nequi. La confirmación conserva una venta y un descuento de stock, con dinero y deuda atómicos e idempotentes. No cambia Eventos.

## Datos y compatibilidad

El esquema18 conserva las69 tablas. Añade a `quick_sales_accounts` las columnas `payment_mode`, `account_payment_option_id` y `payment_split_basis`. La última guarda los identificadores, productos, cantidades y precios revisados. El modo distingue pago único, dividido y borradores anteriores.

La migración no modifica importes ni líneas anteriores. Los registros existentes reciben el modo de compatibilidad; los borradores mixtos se muestran como **Pago dividido**, conservando sus cantidades por medio. La primera modificación de su consumo exige una revisión. Las solicitudes ya preparadas conservan sus documentos canónicos y pueden confirmarse; su configuración de pago no se puede alterar. Las migraciones1–17 permanecen intactas. Se crea y verifica un respaldo SQLite antes de migrar.

Los pagos se siguen guardando en las estructuras de la versión anterior para mantener Reportes e historial. El reparto proporcional interno por producto conserva importes exactos; no representa una nueva salida de existencias.

## Verificación y entrega

La evidencia de las comprobaciones y la entrega está en `docs/evidence/account-payment-mode.json`.

- Suite completa ejecutada:783 pruebas aprobadas, tres omitidas por enlaces del host y un fallo en la nueva prueba de volver a seleccionar un producto. Se corrigió la pérdida del reparto al editar/seleccionar el producto.
- Repetición enfocada posterior:28 pruebas de aplicación y dos de render aprobadas. Cubre pago único global, líneas nuevas, medios, crédito, retorno a pago único, selector bloqueado, revisión del consumo, reapertura real de SQLite, compatibilidadv17 y rechazo SQL específico. Estos conteos incluyen repeticiones; no representan otra suite completa.
- Seis imágenes sintéticas de los estados único/dividido/revisión a1200 y400 píxeles inspeccionadas. Total y selector aparecen juntos cuando hay espacio y se distribuyen verticalmente en ventana estrecha.
- Ensayo de migración17→18 en una copia privada:69 tablas con todos sus valores anteriores y17 migraciones conservados, defaults de compatibilidad correctos, integridad correcta, cero violaciones de claves foráneas y respaldo automático verificado por contenido completo.

La revisión final del aviso de consumo ocultó los resúmenes antiguos mientras se revisa. Se repitieron después la prueba de interfaz con SQLite y los dos renders, todos aprobados. Análisis limpio,201 archivos Dart formateados y Release de desarrollo0.30.0+45 compilada sin overrides de Sanctum.

ZIP y bundle estable verificados:18 archivos idénticos, sin bases ni perfiles privados. El empaquetador excluye el manifiesto temporal `native_assets.json` que puede generar Dart CLI con rutas absolutas; conserva el manifiesto de Flutter Release y sus DLL. La primera comprobación detectó ese archivo, se corrigió la exclusión y se regeneró el paquete antes de abrirlo. Distribuciones anteriores eliminadas según la retención autorizada; dryrun posterior sin pendientes. No se generó un instalador local.

La base activa de desarrollo se actualizó con respaldo manual verificado y respaldo automático SQLite verificado por contenido. Después de iniciar la app, se compararon en solo lectura los valores anteriores de las69 tablas, las17 migraciones y los defaults nuevos: todos conservados, integridad correcta y cero violaciones FK. La base de Documentos conserva su SHA256. Sin operaciones comerciales de prueba en la activa ni ejecución/escritura en el original.

La ventana queda abierta y responde, con versión PE0.30.0+45 y título comprobados por proceso. La primera consulta de arranque precedió a la creación de la ventana; una segunda confirmó su handle visible. La revisión visual corresponde a imágenes sintéticas, sin atribuir inspección de cuentas reales.
