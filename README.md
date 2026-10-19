# Valinor Sanctum 2.0

Repositorio independiente para la nueva aplicación de gestión comercial de Valinor.

**Estado: catálogo y recepción de compras a crédito implementados (0.2.0, esquema v2).** Categorías, proveedores, productos, stock/costo por movimientos y compras atómicas con deuda y asiento balanceado. La fundación 0.1.0 y su validación se conservan como antecedentes. Pagos, ventas y ajustes siguen pendientes; producción permanece deshabilitada.

Consulta [el incremento 02 y sus verificaciones](docs/13-incremento-02.md), [el catálogo renderizado mediante pruebas](docs/images/inventory-catalog.png), o [el historial de compras renderizado](docs/images/inventory-purchases.png). La [validación Windows de la fundación](docs/11-validacion-windows.md) conserva el corte anterior.

Para abrir esta entrega usa `dist/0.2.0/ValinorSanctum2/valinor_sanctum_2.exe`. El paquete completo está en `dist/valinor-sanctum-2-0.2.0-windows-x64.zip`; conserva las DLL y la carpeta data junto al ejecutable. Esta versión de desarrollo guarda sus datos dentro de `C:/proyectos/valinor_sanctum_2` y no está habilitada para producción. Las bases propias v1 se actualizan con respaldo SQLite previo; la versión anterior no puede abrir v2.

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

Resultados 0.2.0: 114 pruebas aprobadas y tres omitidas por falta de permiso del host para crear enlaces simbólicos; análisis y formato limpios. El flujo sintético verifica recepción/reintento, stock/costo y deuda al reabrir, balance y snapshots históricos. En Windows se observaron catálogo, historial y diagnóstico v2 mediante accesibilidad y teclado; los formularios se ejercitaron en pruebas de widgets. No se presenta esa observación como entrada manual nativa de compras. Los límites y artefactos están en el informe del incremento.
