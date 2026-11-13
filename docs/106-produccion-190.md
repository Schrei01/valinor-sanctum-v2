# Producción 1.9.0

Incluye Desarrollo0.49.2: Mensualidad Élfica de COP109.000 por mes calendario, acceso ilimitado y bono de COP30.000 por período, canje por línea desde Ventas y pago normal/dividido/Deudas del excedente. Conserva inscripción con correo y día/mes de nacimiento, avisos de vencimiento y renovación. Deudores muestra el saldo anterior a cada fiado y el formulario de inscripción separa persona existente y nombre.

Compilación instalada1.9.0+87 con SANCTUM_ENV=installed. El portable y pubspec de Desarrollo conservan0.49.2+86. Usa Documents/sanctum2.sqlite3 y legacy-treasury.json del usuario de Windows. El primer arranque respalda antes de migrar27→29, conserva las80 tablas anteriores y agrega siete de membresías/bonos (87 totales). No convierte beneficios antiguos en bonos adicionales; no hubo mensualidades reales en la edición anterior de Producción.

El instalador no contiene ni reemplaza bases ni JSON privados. Una instalación nueva crea Valinor/COP/0 decimales. Reinstalar y desinstalar conservan los datos. El propietario cierra Producción y ejecuta dist/Valinor-Sanctum-1.9.0-Produccion-Instalar.exe; la preparación solo usa usuarios privados y snapshots obtenidos con fuente en lectura.

Se entrega mediante PR13 a main, integrado exclusivamente tras CI completo aprobado del HEAD actualizado. El paquete final se reconstruye desde el commit integrado, se verifica y se identifica con prod-1.9.0. Se conserva la última distribución de Desarrollo y la instalación operativa actual; se retiran solo antiguos paquetes de Producción después de verificar la entrega nueva. Los resultados y huellas finales se registran en el PR y evidencia privada.
