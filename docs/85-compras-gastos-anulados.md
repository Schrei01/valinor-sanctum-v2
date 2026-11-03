# Compras después de anular un gasto

Producción 1.4.2 corrige un bloqueo al confirmar compras cuando existe un gasto anulado. Caja y Reportes calculaban el saldo con documentos confirmados (`posted`), pero el control SQL de pagos también incluía los documentos anulados (`reversed`). Esto podía mostrar saldo suficiente y rechazar el pago durante la confirmación, conservando la solicitud preparada para reintentar.

La migración 23 cambia el filtro de saldo y cronología de ese control a documentos `posted`. Conserva las protecciones contra saldo insuficiente, desbordamientos, pagos anteriores a movimientos vigentes y duplicados. Las operaciones anuladas conservan sus datos históricos y dejan de afectar tanto el saldo mostrado como el control del pago.

Cerrar Producción, instalar `Valinor-Sanctum-1.4.2-Produccion-Instalar.exe` y volver a abrir Compras. El ingreso pendiente se conserva; usar **Reintentar el mismo ingreso**. La instalación no reemplaza la base ni el JSON de Documentos; la app respalda y actualiza la base al abrirla.

Se conserva Desarrollo portable 0.38.2 y su base independiente en esquema 22. El source de Desarrollo avanza a 0.38.3; no se publica un nuevo portable de Desarrollo en esta entrega urgente.

La incidencia se reprodujo sobre una copia privada de la solicitud preparada. Con esquema 22, el pago fallaba en el control SQL de saldo y la transacción se revertía entera, sin compras confirmadas ni movimientos parciales. Con esquema 23 se confirmó la misma solicitud y un segundo intento devolvió el resultado existente sin duplicar inventario ni dinero. Esta recuperación se ensayó únicamente en la copia; la fuente operativa y su ingreso pendiente no se modificaron.

Se aprobaron 55 pruebas distintas entre las ejecuciones seleccionadas de compras, pagos, migración de deudores, interfaz y almacenamiento instalado. La regresión nueva cubre Efectivo, Nequi, una operación anulada con fecha posterior al ingreso, rollback antes de corregir, conservación de la preparación al migrar, respaldo por contenido y confirmación idempotente. Los importes del test público son sintéticos. No se repitió la suite general ni se generaron renders por este cambio de validación. Análisis limpio y formato de 217 archivos sin cambios.

El ejecutable installed migró una copia 22→23 en Documentos privados. Conservó los valores de las 74 tablas, el gasto anulado y las solicitudes preparadas, además del JSON, durante el proceso y después de cerrarlo. Respaldo automático, integridad y claves foráneas verificados. La instalación aislada comprobó 19 archivos, arranque/reapertura, rechazo de actualización abierta, reinstalación y desinstalación conservando datos; el modo de ensayo omite registro y accesos reales.

ZIP, bundle y payload del instalador coinciden en 19 archivos sin privados. Se preservaron 43 huellas de la última distribución de Desarrollo, su ZIP/acceso/selector/historial y la instalación productiva existente. Se retiraron los dos artefactos productivos anteriores; la limpieza quedó sin pendientes. La ventana operativa permaneció abierta; no se ejecutó instalación ni migración sobre su base real. Las pruebas nativas usaron procesos ocultos propios, detenidos al terminar, sin inspección visual nativa.

Ver [evidencia sanitizada](evidence/production-142.json). Copias, verificadores y datos de la solicitud permanecen en carpetas privadas ignoradas por Git.
