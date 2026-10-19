# Valinor Sanctum 2.0

Repositorio independiente para la nueva aplicación de gestión comercial de Valinor.

**Estado: primera fundación compilada, empaquetada y validada para Windows (0.1.0).** Configuración de perfil, SQLite independiente, dinero exacto, FIFO y pruebas ya disponibles. Se instaló el toolchain C++ con autorización expresa. El propietario confirmó la creación del perfil sintético y cuatro indicadores correctos; se comprobó su recuperación al reabrir y su persistencia con dos inspecciones SQLite de solo lectura. El ejecutable del paquete final también abrió con un espacio vacío y diagnóstico correcto.

Consulta [la validación Windows y los artefactos](docs/11-validacion-windows.md), [el incremento 01 histórico](docs/10-incremento-01.md), o la [vista previa renderizada mediante pruebas](docs/images/bootstrap.png).

Para abrir esta entrega usa `dist/ValinorSanctum2/valinor_sanctum_2.exe`. El paquete completo está en `dist/valinor-sanctum-2-0.1.0-windows-x64.zip`; conserva las DLL y la carpeta data junto al ejecutable. Esta versión de desarrollo guarda sus datos dentro de `C:/proyectos/valinor_sanctum_2` y no está habilitada para producción.

## Separación de proyectos

| Proyecto | Ruta | Tratamiento |
|---|---|---|
| POS original | `C:\proyectos\valinor_ludoteca` | Solo lectura; continúa operando sin cambios |
| Valinor Sanctum 2.0 | `C:\proyectos\valinor_sanctum_2` | Nuevo repositorio Git; ubicación confirmada por el propietario |

La auditoría se hizo sobre el código del original, revisión `b94861326bcd9936a9515c104897703cb4f65347`, el 18 de octubre de 2026, fecha local de Bogotá. No se abrió ninguna base productiva ni se ejecutaron migraciones o la aplicación original.

## Documentación de este incremento

1. [Diagnóstico técnico, alcance y reutilización](docs/01-diagnostico.md).
2. [Auditoría del esquema, migraciones y persistencia](docs/02-auditoria-datos.md).
3. [Auditoría funcional de la operación](docs/03-auditoria-operacion.md).
4. [Arquitectura propuesta y aislamiento](docs/04-arquitectura.md).
5. [Modelo financiero y esquema preliminar de datos](docs/05-modelo-financiero.md).
6. [Preguntas de negocio, métricas y recomendaciones](docs/06-matriz-negocio.md).
7. [Compatibilidad e importación futura](docs/07-migracion.md).
8. [Prioridades, pruebas y criterios de aceptación](docs/08-plan-validacion.md).
9. [Evidencia y límites de la verificación](docs/09-verificacion.md).
10. [Fundación implementada y verificaciones del corte anterior](docs/10-incremento-01.md).
11. [Toolchain instalado, ejecutable Windows y paquete completo](docs/11-validacion-windows.md).

## Decisiones aprobadas

- Conservar Flutter Desktop y SQLite, con Windows como primer destino y operación offline.
- Construir módulos de presentación, aplicación, dominio y persistencia, manteniendo Provider como opción inicial de inyección y estado de interfaz.
- Confirmar cada operación comercial y sus efectos financieros/inventario en una sola transacción; manejar dinero en enteros y conservar precios y costos históricos.
- Usar un libro financiero interno de asientos balanceados, generado automáticamente, para distinguir ventas, cobros, compras, gastos, transferencias y capital.
- Proponer FIFO por capas para valoración de productos; aprobar esta política antes de implementarla y mostrar por separado los costos desconocidos.
- Persistir cuentas abiertas; registrar venta a crédito cuando se entrega/consume, con cobros posteriores separados.
- Crear almacenamiento e identificadores exclusivos para 2.0; inicialización vacía y saldos iniciales declarados por el usuario.
- Mantener objetivos y umbrales de negocio configurables, sin cifras de ventas, salarios o beneficios preestablecidas.

El propietario aprobó el diseño el 18 de octubre de 2026. El desarrollo usa datos sintéticos y bases exclusivas dentro del repositorio. La transición a producción requerirá otra validación expresa. No existe sincronización con el POS original.

## Ejecutar las verificaciones

El SDK portable y sus cachés están en .tooling, ignorados por Git. Los scripts restauran el entorno del proceso y no cambian PATH global.

~~~powershell
./scripts/flutter.ps1 pub get --enforce-lockfile
./scripts/flutter.ps1 analyze
./scripts/flutter.ps1 test --reporter expanded
./scripts/flutter.ps1 run -d windows
./scripts/flutter.ps1 build windows --release --no-pub
./scripts/package-windows.ps1
~~~

Resultados: 63 pruebas aprobadas y tres omitidas por falta de permiso del host para crear enlaces simbólicos; análisis y formato limpios. Guardado y reapertura del perfil sintético verificados, con huellas coincidentes y cero cambios durante la segunda lectura. El paquete final se reconstruyó sin overrides de prueba, se verificaron sus 17 archivos y se abrió/cerró correctamente con sus cuatro indicadores en Correcto. Se usó confirmación manual del propietario y observación por accesibilidad; la captura de imagen falló y no se presenta como prueba visual automática. Los módulos operativos permanecen pendientes según el plan.
