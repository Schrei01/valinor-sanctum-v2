# Compras: orden de unidades, costo total y PVP — 0.22.1

Solicitud del propietario del 27/10/2026: mostrar de izquierda a derecha unidades, costo de las unidades y PVP; quitar el botón deshabilitado de saldo inicial y dejar la app abierta para revisar.

- Se reordena la fila: **Unidades → Costo total de las unidades → PVP unitario**. En ventanas estrechas conserva ese orden al pasar a la siguiente línea.
- «Saldo inicial» se oculta cuando ninguna cuenta activa permite una apertura. Se conserva para espacios nuevos que todavía deben declarar dinero real, y se conserva la recuperación de aperturas pendientes.
- Sin cambios en cálculo de sugerencia, costo total, pagos, stock, precios ni persistencia. Sin migración: esquema 15.

Verificación: 11 pruebas existentes de Compras aprobadas, análisis sin incidencias y compilación release sin overrides. ZIP, bundle estable y copia versionada coinciden en 17 archivos y excluyen datos privados; metadato del ejecutable 0.22.1+35. Se eliminaron los artefactos anteriores de dist.

Respaldo verificado en `backups/purchase-form-20261027`; las 64 tablas activas, todas sus filas y el esquema quedaron exactamente conservados, tanto después de publicar como después de iniciar la app. Integridad correcta y cero violaciones FK. No se ingresaron operaciones de prueba reales ni se modificó el POS original.

Se inició el ejecutable estable y se detectó su ventana, con proceso respondiendo. La navegación automática a Compras falló con `coordinate input geometry is unavailable`; la recuperación/captura falló con `FrameArrived timed out: timed out waiting on channel`. No afirmar revisión visual nativa del formulario; se dejó abierta la app como pidió el propietario. La lectura de accesibilidad encontró además el rótulo estático preexistente «Versión 0.21.0»; el metadato verificado del ejecutable es 0.22.1+35. Ese rótulo debe sincronizarse en la próxima publicación.

Evidencia: `docs/evidence/purchase-form.json`.
