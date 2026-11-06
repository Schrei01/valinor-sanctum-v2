# Producción 1.7.0 — Reportes, Compras y Bulk

Instalador de Windows con los incrementos entregados en Desarrollo 0.42.0–0.44.0:

- Reportes agrupa los ítems vendidos por nombre y medio de pago, suma cantidades/importes y ordena alfabéticamente.
- Compras permite varios productos de una misma categoría, con un total pagado independiente de los costos escritos y su diferencia visible.
- Ventas incorpora Bulk Magic, Bulk Pokémon y Bulk Yu-Gi-Oh! por valor vendido dentro de la misma cuenta que los productos físicos, con sus pagos, deudas y división habituales.

La ventana, interfaz y accesos identifican **Producción 1.7.0**. Se compila como `1.7.0+78` con `SANCTUM_ENV=installed`. Desarrollo conserva su portable **0.44.0+77**, su acceso y su base independiente; el `pubspec.yaml` mantiene esa versión de Desarrollo.

## Datos e instalación

Lee `%USERPROFILE%\Documents\sanctum2.sqlite3` y `legacy-treasury.json`. Una base en esquema 23 se actualiza a 25 con respaldo verificado antes de migrar. Se conservan los registros existentes; se agregan las dos tablas de compras completas y se amplía la clasificación de servicios para los bulks. El resultado tiene 76 tablas.

Al entrar en Ventas se agrega una sola vez la configuración de los tres bulks, con PVP inicial cero y categoría de artículos activa. No se modifica el inventario físico ni se registra dinero por ese alta. Si faltan cuentas abiertas se guarda únicamente la cuenta inicial vacía prevista; las existentes se conservan. Las compras y ventas preparadas anteriores siguen siendo compatibles.

El instalador no contiene ni reemplaza bases o historiales privados. Si no hay base, el primer arranque crea Valinor/COP/0 decimales. La instalación, reinstalación y desinstalación conservan los datos de Documentos. La preparación se verifica con un snapshot obtenido abriendo la fuente operativa exclusivamente en lectura y con ensayos nativos bajo un usuario privado dentro del repositorio; no instala ni migra operativamente la base real.

Artefacto de entrega: `dist/Valinor-Sanctum-1.7.0-Produccion-Instalar.exe`. El propietario cierra Producción y ejecuta el instalador. La app realiza el respaldo y la actualización de la base al abrirla.

## Publicación y validación

La solicitud «Saquemos producción» confirma la aceptación de los incrementos y autoriza integrar el PR de publicación después de que apruebe el CI completo. La rama se actualiza con `main`, conservando Desarrollo 0.44.0. No se integra por un resultado de otro commit ni se elude la protección de la rama.

La entrega definitiva requiere CI aprobado, integración, compilación de Producción y ensayos privados de migración/arranque e instalación. Se verifica que el ZIP y el instalador contengan el mismo programa, y que Desarrollo y la instalación operativa permanezcan intactas. Tras verificar la nueva entrega se retiran únicamente las distribuciones productivas anteriores y se registra `prod-1.7.0`.

El cuerpo del PR y la evidencia privada registran los resultados finales y hashes de los artefactos. No se publican snapshots, respaldos, capturas ni filas de datos operativos.
