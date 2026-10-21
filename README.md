# Valinor Sanctum 2.0

Repositorio independiente para la nueva aplicación de gestión comercial de Valinor.

**Estado: inventario inicial vendible, catálogo con existencias, compras de contado y ventas de mostrador (0.13.1, esquema v11).** La carga inicial verificada deja productos y cantidades disponibles en **Ventas**, en un espacio limpio que conserva aparte las pruebas anteriores. **Catálogo** muestra solo productos con unidades, con filtros de **Categoría**, **Proveedor** y nombre o SKU; **Todos los productos** limpia los criterios. Sus columnas son **Producto, PVP, Unidades y Proveedor**, según el [ajuste 0.9.1](docs/28-proveedor-catalogo.md). No crea ni modifica registros. Los agotados permanecen guardados para reponerlos desde **Compras**, donde se ingresa costo unitario, PVP, proveedor, categoría, SKU opcional y cantidad. Al seleccionar un producto existente, Compras completa SKU, categoría, PVP, proveedor y último costo unitario conocido desde sus compras o su inventario inicial; los campos siguen siendo editables. Consulta [el autocompletado 0.11.1](docs/31-autocompletar-compras.md). **Ingresar producto** guarda catálogo, inventario y pago total desde Efectivo o Transferencia juntos. En Compras, Transferencia usa la misma cuenta de Nequi. **Ventas** conserva varias cuentas con varias líneas y pago por línea; Registrar venta confirma entrega y cobro juntos. Para fiar, selecciona **Deudas** en la línea y escribe el **Cliente de la deuda**; los productos vendidos se descuentan del inventario y el valor fiado queda por cobrar a su nombre. Puedes combinar líneas pagadas y fiadas. Consulta [ventas con Deudas](docs/33-ventas-deudas.md). **Tesorería** reemplaza Pagos con Caja, Nequi, Caja mayor, Deudas de clientes y movimientos por cuenta. El total disponible suma Caja + Nequi. **Registrar gasto** descuenta Caja o Nequi por motivo; **Transferir dinero** mueve fondos entre cuentas, incluyendo Caja mayor, con saldo suficiente y recuperación de reintentos. Consulta [gastos y transferencias](docs/32-gastos-transferencias.md) y [el alcance de Tesorería](docs/29-tesoreria.md). Ajustes y arqueo siguen pendientes; el entorno sigue siendo local de desarrollo.

La [apertura de inventario 0.9.0](docs/27-inventario-inicial.md) usa la copia ajustada con categoría/proveedor, con costos cero confirmados, conversión monetaria exacta y conciliación. Es una apertura de Inventario contra Patrimonio: no crea compras, deudas ni pagos. La [apertura financiera 0.11.0](docs/30-apertura-tesoreria.md) incorpora los saldos de Caja, Nequi, Caja mayor y cartera anterior desde la misma copia verificada. El historial anterior es consulta separada y no vuelve a mover dinero. Los perfiles, el selector local y el JSON de origen quedan privados en `data`, fuera de Git y ZIP. La [consulta separada de 0.8.0](docs/26-inventario-copia.md) sigue disponible para perfiles con un snapshot local. No hay sincronización con el POS original.

Consulta [el incremento 07 y sus verificaciones](docs/23-incremento-07.md), [su contrato](docs/22-contrato-incremento-07.md), [el nuevo formulario de Compras](docs/images/stock-intake.png) y [la pantalla de Ventas](docs/images/quick-sales.png). Ambas imágenes usan datos sintéticos. Los incrementos anteriores conservan sus cortes históricos.

El ajuste 0.7.2 se describe en [Filtros del catálogo](docs/25-filtros-catalogo.md), con [lista de categorías](docs/images/catalog-category-options.png) y [productos filtrados](docs/images/catalog-filtered.png). Son vistas de pruebas con datos sintéticos. La entrega 0.7.1 se conserva como antecedente en [Catálogo de consulta](docs/24-catalogo-consulta.md).

Para abrir el programa, haz doble clic en **Iniciar Valinor Sanctum.cmd** en la raíz del proyecto. Inicia la entrega vigente de `dist/ValinorSanctum2`; esa ruta se actualiza al empaquetar. La copia versionada 0.13.1 está en `dist/0.13.1/ValinorSanctum2/valinor_sanctum_2.exe` y su ZIP en `dist/valinor-sanctum-2-0.13.1-windows-x64.zip`. Conserva las DLL y la carpeta data junto al ejecutable. El selector local abre el perfil `valinor`; las pruebas siguen conservadas en `development`. Las bases propias v1–v10 se actualizan con respaldo SQLite previo; las versiones anteriores no pueden abrir v11. El almacenamiento sigue dentro de `C:/proyectos/valinor_sanctum_2`.

Si aparece `database v10 is newer than supported v9` u otro aviso de base más nueva, se ha abierto un bundle antiguo. Cierra esa ventana e inicia el programa con el archivo de la raíz; no borres ni reinicies la base para resolver un ejecutable antiguo.

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
22. [Contrato de compras de contado e ingreso al catálogo](docs/22-contrato-incremento-07.md).
23. [Compras, historial de ingresos y validación 0.7.0](docs/23-incremento-07.md).
24. [Catálogo de consulta y validación 0.7.1](docs/24-catalogo-consulta.md).
25. [Filtros combinados del catálogo 0.7.2](docs/25-filtros-catalogo.md).
26. [Consulta separada de inventario 0.8.0](docs/26-inventario-copia.md).
27. [Inventario inicial disponible para vender 0.9.0](docs/27-inventario-inicial.md).
28. [Columna Proveedor en Catálogo 0.9.1](docs/28-proveedor-catalogo.md).
29. [Tesorería, saldos y movimientos 0.10.0](docs/29-tesoreria.md).
30. [Saldos e historial de la copia en Tesorería 0.11.0](docs/30-apertura-tesoreria.md).
31. [Autocompletar productos en Compras 0.11.1](docs/31-autocompletar-compras.md).
32. [Gastos y transferencias en Tesorería 0.12.0](docs/32-gastos-transferencias.md).
33. [Ventas con Deudas y Transferencia en Compras 0.13.0](docs/33-ventas-deudas.md).
34. [Transferencia en todo Compras 0.13.1](docs/34-transferencia-compras.md).

## Decisiones aprobadas

- Conservar Flutter Desktop y SQLite, con Windows como primer destino y operación offline.
- Construir módulos de presentación, aplicación, dominio y persistencia, manteniendo Provider como opción inicial de inyección y estado de interfaz.
- Confirmar cada operación comercial y sus efectos financieros/inventario en una sola transacción; manejar dinero en enteros y conservar precios y costos históricos.
- Usar un libro financiero interno de asientos balanceados, generado automáticamente, para distinguir ventas, cobros, compras, gastos, transferencias y capital.
- Proponer FIFO por capas para valoración de productos; aprobar esta política antes de implementarla y mostrar por separado los costos desconocidos.
- Persistir cuentas abiertas. La prioridad del MVP es registrar venta y cobro inmediato desde una única pantalla llamada Ventas; se retiró el acceso al formulario anterior.
- Compras registra mercancía pagada de contado y su salida de Efectivo/Transferencia, creando el producto desde el mismo formulario. No exige un recorrido de crédito ni un pago posterior.
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
./scripts/dart.ps1 run tool/verify_stock_intake_flow.dart
./scripts/flutter.ps1 run -d windows
./scripts/flutter.ps1 build windows --release --no-pub
./scripts/package-windows.ps1
~~~

El empaquetador también publica la entrega en la ruta estable. Para publicar un ZIP ya generado: `./scripts/publish-local-bundle.ps1 -ArchivePath dist/valinor-sanctum-2-0.13.1-windows-x64.zip`. Conserva el bundle previo bajo tmp y rechaza versiones anteriores al proyecto o a la entrega vigente. Hay que cerrar todas las copias de la aplicación de este proyecto antes de actualizarla.

Resultados 0.11.0: 500 pruebas aprobadas y tres omitidas por permisos de enlaces del host. Incluyen apertura financiera, reintentos, precisión, historial y conservación de registros; análisis limpio y formato de 121 Dart sin cambios. Esquema v9 aditivo con respaldo previo y migraciones v1–v8 intactas.

Actualización 0.11.1: autocompletado de Compras también desde la apertura de inventario, con datos editables y limpieza al cambiar de producto. 50 pruebas específicas aprobadas, análisis limpio y seis Dart modificados con formato limpio. Esquema v9 sin cambios.

Actualización 0.13.0: Ventas permite líneas en Deudas a nombre del cliente y cuentas mixtas; Compras presenta Transferencia como alias local de Nequi. 601 pruebas aprobadas, tres omitidas por enlaces del host, análisis y formato limpios. Esquema v11 con respaldo previo y conservación verificada de datos, saldos e inventario. La verificación y sus límites se registran en [la entrega 0.13.0](docs/33-ventas-deudas.md).

Corrección 0.13.1: el historial y los avisos de Compras también muestran Transferencia. Se conserva Nequi en los registros guardados y en las demás secciones; [ver alcance y validación](docs/34-transferencia-compras.md).
