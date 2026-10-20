# Valinor Sanctum 2.0

Repositorio independiente para la nueva aplicación de gestión comercial de Valinor.

**Estado: ventas de mostrador (0.6.1, esquema v6).** En Ventas abre varias cuentas, agrega líneas de productos y elige Efectivo o Nequi en cada una. **Registrar venta** guarda entrega, costo y cobro inmediato en una sola operación. Los borradores se guardan automáticamente. Ventas es la única pantalla de ventas y no pide cliente ni vencimiento. Aperturas, ajustes y caja/arqueo siguen pendientes; producción permanece deshabilitada.

Consulta [el incremento 06 y sus verificaciones](docs/21-incremento-06.md), [su contrato](docs/20-contrato-incremento-06.md) y [la pantalla de mostrador con datos sintéticos](docs/images/quick-sales.png). Los incrementos anteriores conservan sus cortes históricos.

Para abrir el programa, haz doble clic en **Iniciar Valinor Sanctum.cmd** en la raíz del proyecto. Inicia la entrega vigente de `dist/ValinorSanctum2`; esa ruta se actualiza al empaquetar. La copia versionada 0.6.1 está en `dist/0.6.1/ValinorSanctum2/valinor_sanctum_2.exe` y su ZIP en `dist/valinor-sanctum-2-0.6.1-windows-x64.zip`. Conserva las DLL y la carpeta data junto al ejecutable. Esta versión de desarrollo guarda sus datos dentro de `C:/proyectos/valinor_sanctum_2` y no está habilitada para producción. Las bases propias v1–v5 se actualizan con respaldo SQLite previo; las versiones anteriores no pueden abrir v6.

Si aparece `database v6 is newer than supported v5` u otro aviso de base más nueva, se ha abierto un bundle antiguo. Cierra esa ventana e inicia el programa con el archivo de la raíz; no borres ni reinicies la base para resolver un ejecutable antiguo.

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
12. [Contrato del incremento de catálogo y recepción](docs/12-contrato-incremento-02.md).
13. [Catálogo, compras a crédito y validación 0.2.0](docs/13-incremento-02.md).
14. [Contrato de cuentas abiertas y ventas a crédito 0.3.0](docs/14-contrato-incremento-03.md).
15. [Cuentas abiertas, ventas a crédito y validación 0.3.0](docs/15-incremento-03.md).
16. [Contrato de cobros y abonos 0.4.0](docs/16-contrato-incremento-04.md).
17. [Cobros, saldos y validación 0.4.0](docs/17-incremento-04.md).
18. [Contrato de pagos a proveedores 0.5.0](docs/18-contrato-incremento-05.md).
19. [Pagos a proveedores y validación 0.5.0](docs/19-incremento-05.md).
20. [Contrato de ventas de mostrador 0.6.1](docs/20-contrato-incremento-06.md).
21. [Mostrador y validación 0.6.1](docs/21-incremento-06.md).

## Decisiones aprobadas

- Conservar Flutter Desktop y SQLite, con Windows como primer destino y operación offline.
- Construir módulos de presentación, aplicación, dominio y persistencia, manteniendo Provider como opción inicial de inyección y estado de interfaz.
- Confirmar cada operación comercial y sus efectos financieros/inventario en una sola transacción; manejar dinero en enteros y conservar precios y costos históricos.
- Usar un libro financiero interno de asientos balanceados, generado automáticamente, para distinguir ventas, cobros, compras, gastos, transferencias y capital.
- Proponer FIFO por capas para valoración de productos; aprobar esta política antes de implementarla y mostrar por separado los costos desconocidos.
- Persistir cuentas abiertas. La prioridad del MVP es registrar venta y cobro inmediato desde una única pantalla llamada Ventas; se retiró el acceso al formulario anterior.
- Crear almacenamiento e identificadores exclusivos para 2.0; inicialización vacía y saldos iniciales declarados por el usuario.
- Mantener objetivos y umbrales de negocio configurables, sin cifras de ventas, salarios o beneficios preestablecidas.

El propietario aprobó el diseño el 18 de octubre de 2026. El desarrollo usa datos sintéticos y bases exclusivas dentro del repositorio. La transición a producción requerirá otra validación expresa. No existe sincronización con el POS original.

## Ejecutar las verificaciones

El SDK portable y sus cachés están en .tooling, ignorados por Git. Los scripts restauran el entorno del proceso y no cambian PATH global.

~~~powershell
./scripts/flutter.ps1 pub get --enforce-lockfile
./scripts/flutter.ps1 analyze
./scripts/flutter.ps1 test --reporter expanded
./scripts/dart.ps1 run tool/verify_sales_flow.dart
./scripts/dart.ps1 run tool/verify_collections_flow.dart
./scripts/dart.ps1 run tool/verify_supplier_payments_flow.dart
./scripts/dart.ps1 run tool/verify_quick_sales_flow.dart
./scripts/flutter.ps1 run -d windows
./scripts/flutter.ps1 build windows --release --no-pub
./scripts/package-windows.ps1
~~~

El empaquetador también publica la entrega en la ruta estable. Para publicar un ZIP ya generado: `./scripts/publish-local-bundle.ps1 -ArchivePath dist/valinor-sanctum-2-0.6.1-windows-x64.zip`. Conserva el bundle previo bajo tmp y rechaza versiones anteriores al proyecto o a la entrega vigente. Hay que cerrar todas las copias de la aplicación de este proyecto antes de actualizarla.

Resultados 0.6.1: 317 pruebas aprobadas y tres omitidas por falta de permiso del host para crear enlaces simbólicos; análisis y formato limpios. El flujo independiente pasó 30 comprobaciones de varias cuentas, pagos por línea, venta y cobro atómicos, reapertura, reintentos, stock y saldos exactos. Los formularios se ejercitaron en widgets y la imagen actualizada se inspeccionó; los límites y artefactos están en el informe del incremento.
