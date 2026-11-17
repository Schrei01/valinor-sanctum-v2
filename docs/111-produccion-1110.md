# Producción 1.11.0

Publica Desarrollo 0.52.0: en Ventas, **Deuda al registrar** suma el saldo actual de la persona y el nuevo importe asignado a Deudas. Por ejemplo, con COP10.000 anteriores y una compra de COP8.000, pagando COP5.000 y dejando COP3.000 fiados, muestra COP13.000. Excluye pagos inmediatos y cobertura con bono; se actualiza al cambiar persona o consumo. Es una proyección informativa y conserva las reglas de registro.

Compilación `1.11.0+92` con `SANCTUM_ENV=installed`. Conserva cumpleaños, membresías, ventas y demás funciones anteriores. `pubspec.yaml` y la distribución de Desarrollo permanecen en `0.52.0+91`, con almacenamiento y configuración independientes. Esquema29 sin migraciones nuevas; una instalación antigua conserva el respaldo y las migraciones existentes al arrancar.

El instalador `dist/Valinor-Sanctum-1.11.0-Produccion-Instalar.exe` no contiene bases ni historial privados. La edición instalada usa Documentos del usuario. Preparar esta entrega no actualiza la instalación operativa ni abre sus datos con escritura: el propietario ejecuta el instalador cuando corresponda.

La preparación usa una rama temporal desde `origin/main`, PR y `verify-and-build` completo aprobado antes de integrar. La entrega final se reconstruye desde el commit integrado y aprobado y se identifica con la etiqueta inmutable `prod-1.11.0`. Las verificaciones de instalación, arranque, actualización, reapertura y desinstalación usan únicamente ubicaciones privadas dentro de `tmp`; Desarrollo se conserva.
