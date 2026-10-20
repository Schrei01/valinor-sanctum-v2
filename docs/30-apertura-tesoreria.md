# Saldos iniciales desde la copia — 0.11.0

Tesorería incorpora los saldos de la misma copia verificada que se utilizó para el inventario. Cada importe procede de la última fila por `id` de `cash`, `nequi`, `caja_mayor` y `deudas`: son saldos acumulados, por lo que no se suman las filas históricas.

La apertura establece Caja, Nequi y Caja mayor en sus cuentas correspondientes, conservando el saldo negativo de Caja mayor confirmado por el propietario. La contrapartida es patrimonio de apertura. El saldo de Deudas se registra como **cartera anterior sin detalle por cliente**, porque la fuente no contiene personas ni obligaciones individuales. No se crean ventas, clientes, cobros ni gastos ficticios. Esa cartera forma parte del total de Deudas y queda identificada en su tarjeta; su cobro individual necesita el detalle de cada cliente y no se habilita en esta entrega.

El Total disponible sigue siendo **Caja + Nequi**. La reserva y la cartera se muestran aparte. Compras y ventas posteriores utilizan las cuentas monetarias existentes y los saldos importados. No se vuelve a cargar inventario ni se reemplazan los registros propios.

## Apertura y procedencia

El esquema v9 añade una apertura única por perfil, vinculada a un comando canónico, documento y asiento exacto e inmutables. Los reintentos con el mismo contenido no duplican dinero; otro contenido o una segunda apertura se rechazan. La carga exige un perfil existente sin movimientos monetarios, cuentas por cobrar o aperturas manuales previas. Una apertura importada de cero también bloquea otra apertura manual.

La copia se abre solo en lectura y se verifica su huella antes y después de extraerla. Se rechazan auxiliares SQLite activos. Los importes decimales se convierten mediante BigInt a la escala del perfil sin redondeo implícito. El importador verifica la huella del mismo buffer JSON que analiza, la divisa, la escala, el perfil y la coincidencia con la procedencia del inventario. La base propia se respalda antes de migrar; las ocho migraciones publicadas se conservan intactas.

## Historial separado

**Historial de la copia** permite consultar ingresos, egresos y transferencias anteriores, con filtro por cuenta y paginación. Una transferencia se presenta una vez y puede encontrarse desde origen o destino. Se conserva la unión de los últimos 50 movimientos de cada cuenta, hasta 200 filas. Estos registros no generan asientos: sus efectos ya forman parte de los saldos iniciales.

Las fechas originales sin zona horaria se muestran como las guarda la copia. No acreditan un corte común ni se convierten por suposición a UTC. La fecha operativa de la apertura es la de incorporación, identificada como reconstruida. El JSON privado se carga solo si existe una apertura y su huella coincide con la registrada; no puede sustituirse silenciosamente por otro archivo.

El snapshot queda en el perfil local como `legacy-treasury.json`, fuera de Git y del ZIP, junto con las huellas, respaldos y comprobantes privados. El POS original y la copia permanecen sin modificar.

## Verificación

- **500 pruebas aprobadas** en la suite completa y tres omitidas por enlaces de archivos no disponibles en el host. Incluye 51 casos nuevos de apertura, esquema, lectura/exportación, historial y conciliación.
- Ocho migraciones publicadas comparadas con la entrega 0.10.0: nombres y verificaciones intactos. El respaldo v8→v9 y la reapertura se probaron con archivos propios.
- Se cubren reintentos tras cierre y archivo de una cuenta, importes negativos, cero, límites monetarios, transacciones atómicas, inmutabilidad y procedencia canónica. La fecha de corte se valida al confirmar documento y asiento, incluso si las líneas se crean después del documento.
- Análisis limpio y formato de 121 archivos Dart sin cambios. Revisión independiente de la implementación; el caso de cronología detectado quedó corregido y con prueba de regresión.
- Respaldo previo del perfil propio verificado en 45 tablas. El ensayo sobre una copia de ese perfil concilió los cuatro saldos, el asiento balanceado y un reintento sin duplicación. Conservó todos los registros anteriores de las 45 tablas y dejó intactos inventario y documentos comerciales. El perfil activo no se utilizó para ensayar.

La apertura real quedó aplicada y conciliada en el perfil activo: cuatro saldos exactos, reserva negativa conservada, asiento balanceado y reintento que recupera la misma apertura sin duplicar. Todos los registros anteriores de las 45 tablas permanecen; inventario y documentos comerciales siguen iguales. Integridad correcta y cero violaciones de claves foráneas. El respaldo automático v8 de la migración coincide además con el respaldo manual previo. La huella de la copia de origen no cambió.

El bundle Windows 0.11.0+15, sin defines de Sanctum, compiló en 67,71 s y se publicó en el acceso estable. Sus 17 archivos coinciden con el ZIP y la copia `dist/0.11.0/ValinorSanctum2`, sin bases, perfiles ni snapshots privados. La apertura nativa confirmó versión, cuatro importes, total disponible, nota de cartera anterior y acceso al historial, sin errores de carga, mediante accesibilidad y teclado. No se enviaron formularios financieros durante esa comprobación; la ventana quedó abierta en Tesorería para el propietario.

La evidencia está en [treasury-opening.json](evidence/treasury-opening.json). Las cifras, fechas de origen, nombres, huellas de datos y comprobantes completos permanecen privados.
