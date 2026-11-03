# Espacio de Registrar préstamo

Desarrollo 0.38.2 y Producción 1.4.1 corrigen la distribución de las acciones en la ficha del deudor. El botón Registrar préstamo tiene separación respecto al saldo, mayor espacio interno y una altura mínima de 48. Las acciones quedan alineadas y mantienen una separación vertical cuando pasan a otra fila.

La corrección solo modifica presentación. No cambia préstamos, pagos, saldos ni el esquema 22.

Desarrollo conserva su acceso habitual. El parche de Producción se entrega como `Valinor-Sanctum-1.4.1-Produccion-Instalar.exe`; cerrar Producción antes de instalar. La base y el JSON de Documentos se conservan y no necesitan reemplazarse.

Se aprobaron 22 pruebas existentes de interfaz y dos renders, con cuatro imágenes inspeccionadas a 1280 y 400 píxeles. El análisis quedó limpio y el formato de 216 archivos no requirió cambios. No se agregaron pruebas que reproduzcan el margen ni se repitieron pruebas financieras, dado que la corrección es de presentación.

Se compilaron y publicaron Development 0.38.2+64 e installed 1.4.1+65. Cada ZIP y su bundle estable coinciden en 19 archivos sin datos privados. En Desarrollo se conservaron las definiciones y filas de las 74 tablas, y 43 huellas de Producción/instalación/selector/historial durante su publicación.

La fuente productiva ya estaba en esquema 22: su copia consistente, tomada en solo lectura, conservó las 74 tablas y el JSON y no requirió migración. La instalación aislada comprobó arranque, reapertura, rechazo de actualización abierta, reinstalación y desinstalación conservando los datos. El modo de ensayo omite registro y accesos reales. En la publicación productiva se preservaron 43 archivos de Desarrollo e instalación existente. No se instaló el parche operativamente ni se modificó la base real; la ventana de Producción del propietario permaneció abierta. La comprobación visual corresponde a renders sintéticos; no se inspeccionó la ventana nativa.

Se retiró el ZIP anterior de Desarrollo y los dos artefactos productivos anteriores. La limpieza quedó sin pendientes en ambas ediciones. Ver [evidencia sanitizada](evidence/loan-button-spacing-0382.json).
