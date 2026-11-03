# Préstamos desde inversión — Desarrollo 0.38.0

En Deudores, la cuenta de la persona tiene el botón **Registrar préstamo**. El formulario pide valor positivo y origen **Inversión**. Al confirmar, aumenta la deuda individual y la inversión por recuperar por el mismo importe. Caja, Nequi, ventas e inventario no cambian.

Se permiten varios préstamos a la misma persona, incluso si ya tiene deuda anterior o compras fiadas. Una persona saldada se puede recuperar desde las sugerencias de Registrar persona → Ver cuenta. Si tiene fiado bloqueado, primero debe habilitarse.

La deuda aparece como «Préstamo desde inversión», con fecha, valor inicial y pendiente. Tesorería identifica la aportación en los movimientos de Inversión. Los informes reconstruyen el saldo del deudor a la fecha de cierre y mantienen los préstamos fuera de ventas y egresos de Caja/Nequi.

Para cobrar, se usa Registrar abono con Efectivo o Transferencia. El pago se aplica a las deudas más antiguas, entra a Caja o Nequi y reduce la cuenta por cobrar. No reduce la inversión por recuperar: devolver el dinero al propietario sigue siendo una devolución de inversión aparte.

El esquema 22 añade `debtor_loans`, amplía las solicitudes durables de Deudores y vincula cada préstamo a una cuenta por cobrar propia. El asiento es débito a Clientes por cobrar y crédito a Inversión por recuperar. Preparación, confirmación, historial y asiento se conservan atómicamente, con recuperación e idempotencia. La actualización crea y verifica un respaldo antes de migrar; no modifica la base productiva.

La edición productiva permanece en 1.3.0 y debe publicarse por separado cuando se solicite.

Se aprobaron 73 pruebas de aplicación distintas entre las ejecuciones de Deudores, Inversión, Reportes, compatibilidad, migración, ajustes, controladores e interfaz. Se aprobaron además dos pruebas de render y se inspeccionaron sus cuatro imágenes a 1280 y 400 píxeles. Incluyen préstamos repetidos, abonos mixtos, reintentos sin duplicar, rollback completo, importes inválidos/desbordamientos, bloqueo de fiado y recuperación después de cerrar/reabrir. No se repitió la suite general. El análisis final no presenta incidencias.

Se corrigió la reconstrucción de fixtures anteriores para conservar también la reserva de identificadores de ajustes y se inicializa Inversión al cargar Deudores, incluso sin haber abierto Tesorería. La migración conserva las solicitudes anteriores preparadas y los préstamos pendientes se recuperan al reabrir.

La copia privada y el ejecutable nativo verificaron la migración 21→22 sin alterar los valores de las 73 tablas anteriores. La base pasó a 74 tablas, con préstamos vacíos, integridad correcta y cero violaciones de claves foráneas. La misma comprobación pasó en la base de desarrollo después de su actualización respaldada. Una primera lectura se adelantó al inicio de la migración; se repitió tras completarse el arranque. No se ingresaron préstamos ni otras operaciones de prueba en la base activa.

La distribución Development 0.38.0+61 contiene 19 archivos, idénticos en ZIP y bundle estable y sin datos privados. Se conservaron 43 huellas de distribución/instalación productiva y selector/JSON de desarrollo. Se retiró el ZIP anterior de Desarrollo; Producción 1.3.0 permanece intacta, sin abrir su base. Desarrollo quedó abierta y respondiendo. La revisión visual corresponde a renders sintéticos; no se atribuye inspección visual nativa.

El acceso habitual es `Iniciar Valinor Sanctum.cmd`. Ver [evidencia sanitizada](evidence/debtor-loans-038.json). Respaldos, copias, hashes de datos y capturas permanecen en carpetas privadas ignoradas por Git.
