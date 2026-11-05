# Producción 1.6.0 — mejoras de Ventas

Versión instalable con Desarrollo 0.41.0: al iniciar o entrar en Ventas sin cuentas, crea y guarda una cuenta vacía; la cabecera muestra el total del consumo de todas las cuentas abiertas y lo actualiza al editar, quitar o cobrar. Conserva cuentas existentes y preparaciones pendientes, y evita duplicados por cargas concurrentes o respuestas de guardado inciertas. En ventanas pequeñas el resumen se coloca debajo de los controles y sigue alineado a la derecha.

La interfaz productiva indica **Producción 1.6.0**. El ejecutable se compila con `1.6.0+74` y `SANCTUM_ENV=installed`. Desarrollo conserva su portable **0.41.0+73**, su acceso y sus datos independientes.

## Datos

La app instalada lee `%USERPROFILE%\Documents\sanctum2.sqlite3` y `legacy-treasury.json`. El esquema sigue en 23 y conserva 74 tablas. La base operativa actual ya está en 23: esta entrega no requiere migración ni recalcula ventas, saldos, deudas o inventario.

Si al abrir no hay cuentas abiertas, el único efecto nuevo previsto es el borrador vacío y su línea sin producto. Si hay cuentas, se conservan. El instalador no incorpora datos privados ni reemplaza la base; instalación, actualización y desinstalación conservan los archivos de datos. Si falta la base, el primer arranque configura Valinor/COP/0 y crea una cuenta vacía.

La preparación usa una copia consistente obtenida abriendo la fuente operativa exclusivamente en lectura. Se verifica el historial, la integridad y todas las filas anteriores. Los ensayos nativos con Documentos aislados permiten únicamente el borrador inicial previsto y comparan nuevamente los datos después de cerrar el programa. El ensayo de instalación espera a que estén listos tanto el perfil como la cuenta automática antes de detener la aplicación.

## Publicación

El PR de Ventas se amplía con esta publicación. La solicitud del propietario de pasar el incremento a Producción confirma su aceptación de la versión de Desarrollo ya entregada y autoriza integrar el PR cuando apruebe el CI completo. No hacer push directo a main ni eludir su protección.

Antes de la entrega definitiva deben estar aprobados el CI y los ensayos privados del instalador, y el commit debe estar integrado. El cuerpo del PR registra los resultados finales, hashes, procedencia y etiquetas. Preparar el instalador no modifica la instalación operativa ni su base real. Conservar Desarrollo y retirar solo las distribuciones productivas anteriores tras verificar la nueva entrega.

Validación previa a actualizar el PR: 12 pruebas específicas de almacenamiento instalado, apertura y rótulos aprobadas; formato de 217 archivos sin cambios y análisis limpio. Las 63 pruebas de aplicación del incremento de Ventas ya estaban aprobadas. La aprobación final de la suite completa corresponde al nuevo commit del PR, sin reutilizar un resultado de otro commit.

La suite completa del primer commit de Desarrollo detectó dos expectativas antiguas: el escenario de navegación agregaba cinco cuentas además de la nueva cuenta automática, y la prueba de catálogo esperaba que Ventas no guardara ningún borrador al iniciar. Se actualizan para utilizar la cuenta inicial entre las cinco, verificar su persistencia, y asegurar que visitar Catálogo no la cambia ni añade otra. La navegación con SQLite comprueba además el total abierto después de cobros fuera de orden y al reabrir. Las 10 pruebas de ambos archivos pasan localmente; se mantienen todas las comprobaciones financieras previas. Esta corrección solo afecta pruebas, sin cambios adicionales al comportamiento de la app.

Artefacto: `dist/Valinor-Sanctum-1.6.0-Produccion-Instalar.exe`. Para instalar, el propietario cierra Producción y ejecuta el instalador; los archivos de Documentos se conservan.
