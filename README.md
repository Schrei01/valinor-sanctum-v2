# Valinor Sanctum 2.0

Repositorio independiente para la nueva aplicación de gestión comercial de Valinor.

**Estado: inventario inicial vendible, catálogo con existencias, compras de contado y ventas de mostrador (0.26.0, esquema v16).** La carga inicial verificada deja productos y cantidades disponibles en **Ventas**, en un espacio limpio que conserva aparte las pruebas anteriores. **Catálogo** muestra eventos activos y productos físicos con unidades, con filtros de **Categoría**, **Proveedor** y nombre o SKU; **Todos los productos** limpia los criterios. Sus columnas son **Producto, PVP, Unidades y Proveedor**, según el [ajuste 0.9.1](docs/28-proveedor-catalogo.md). No crea ni edita productos; los eventos pueden desactivarse conservando su historial. Los agotados permanecen guardados para reponerlos desde **Compras**, donde se ingresa el costo total de las unidades, cantidad, PVP, proveedor, categoría Comestible o Artículo y SKU opcional. Se sugiere un PVP unitario de total/cantidad/0,65, editable incluso por debajo de la sugerencia, y se muestra el PVP anterior. El precio elegido aplica a todas las existencias y sus cambios quedan guardados. Al seleccionar un producto se completan SKU, categoría, PVP y proveedor; el costo total de la nueva compra se ingresa expresamente. Consulta [Compras por costo total e historial de PVP](docs/50-compras-total-historial-pvp.md). **Ingresar producto** guarda catálogo, inventario y pago total desde Efectivo o Nequi juntos. **Ventas** conserva varias cuentas con varias líneas y pago por línea: Efectivo, Transferencia o Deudas. Transferencia usa la misma cuenta de Nequi; el nombre aparece en selección, resumen e historial de Ventas. Registrar venta confirma entrega y cobro juntos. En **Cuenta**, busca o elige una persona registrada en **Deudores** antes de elegir los pagos. Su nombre llena la cuenta y queda vinculado a ella. Para fiar, marca **Deudas** en las líneas correspondientes; los productos vendidos se descuentan del inventario y el valor fiado queda por cobrar a su nombre. Puedes combinar líneas pagadas y fiadas. **Deudores** reemplaza Cobros: registra personas, deuda anterior y abonos parciales o totales por Efectivo o Transferencia, actualizando deuda y caja juntos. Consulta [Deudores 0.16.0](docs/39-deudores.md). **Tesorería** reemplaza Pagos con Caja, Nequi, Caja mayor, Deudas de clientes y movimientos por cuenta. El total disponible suma Caja + Nequi. **Registrar gasto** descuenta Caja o Nequi por motivo; **Transferir dinero** mueve fondos entre cuentas, incluyendo Caja mayor, con saldo suficiente y recuperación de reintentos. Consulta [gastos y transferencias](docs/32-gastos-transferencias.md) y [el alcance de Tesorería](docs/29-tesoreria.md). **Eventos** crea pasadías, torneos o ligas con categoría Evento, PVP manual y PU calculado. Permite varios productos y costo fijo desde Caja o Nequi; exige mínimo positivo cuando hay costos o productos. Crear descuenta una sola vez los insumos y el costo fijo. Las inscripciones se venden desde Ventas sin stock propio ni costos repetidos. [Guía de Eventos 0.15.0](docs/38-eventos-operativos.md). **Reportes** presenta un comprobante compacto con saldos iniciales/finales de Caja y Nequi, ingresos por ventas a Caja y Nequi/Transferencia, ventas a Deudas, Total vendido y egresos de Caja/Nequi con su total. Incluye las transferencias entre cuentas del rango, agrupadas por origen/destino con cantidad de movimientos y total trasladado, separadas de ventas y egresos. Suma las formas de pago registradas en ventas confirmadas, sin duplicar abonos ni transferencias internas. Abre sin fecha inicial y espera a que se elija; la fecha final predeterminada es la fecha y hora actuales de Bogotá. Cada selector abre primero la fecha y luego la hora AM/PM. Debajo del comprobante muestra los ítems vendidos del rango, de a 10 por página, incluyendo ventas antiguas y nuevas. Todos los campos de importes y cantidades separan miles con punto al escribir, conservando la coma decimal en perfiles que la admiten. [Fechas, listado y formato de números 0.22.0](docs/51-reportes-items-numeros.md). Las ventas antiguas se calculan por cantidad × PVP archivado, identificadas como estimadas. Cuando faltan productos o precios, los valores calculables se marcan parciales y se indican los registros Sin información. [Transferencias en el reporte compacto 0.20.1](docs/49-transferencias-reporte.md). Ajustes y arqueo siguen pendientes; el entorno sigue siendo local de desarrollo.

**Valinor** se configura automáticamente al crear una base vacía y abre Ventas. El logo del barco y las montañas identifica la interfaz y el icono nativo de Windows. [Inicio y marca 0.25.0](docs/56-inicio-valinor-identidad.md).

**Reportes** incorpora el saldo por deudor y su total al cierre seleccionado, junto a las transferencias; las notas explicativas quedan al final. Los totales de los módulos comparten estilo y tipografía. [Detalle 0.24.0](docs/55-reporte-deudores-totales.md).

**Catálogo** muestra el estimado total de existencias físicas a PVP, independiente de búsqueda, filtros y paginación. Solo **Pasadía** es un servicio ilimitado fuera de Compras: conserva su precio e historial y sus ventas registran las cantidades en Reportes. [Guía 0.23.0](docs/53-catalogo-ajustes-pasadia.md).

La [apertura de inventario 0.9.0](docs/27-inventario-inicial.md) usa la copia ajustada con categoría/proveedor, con costos cero confirmados, conversión monetaria exacta y conciliación. Es una apertura de Inventario contra Patrimonio: no crea compras, deudas ni pagos. La [apertura financiera 0.11.0](docs/30-apertura-tesoreria.md) incorpora los saldos de Caja, Nequi, Caja mayor y cartera anterior desde la misma copia verificada. Desde 0.18.0, la conversión conserva las ocho tablas originales completas y permite consultar saldos anteriores desde Reportes sin volver a mover dinero. Las ventas antiguas se archivan con sus datos originales, sin inventar precios/costos que no guardaban. [Conversión de la base](docs/44-conversion-base.md). Los perfiles, el selector local y el JSON de origen quedan privados en `data`, fuera de Git y ZIP. La [consulta separada de 0.8.0](docs/26-inventario-copia.md) sigue disponible para perfiles con un snapshot local. No hay sincronización con el POS original.

Consulta [el incremento 07 y sus verificaciones](docs/23-incremento-07.md), [su contrato](docs/22-contrato-incremento-07.md), [el nuevo formulario de Compras](docs/images/stock-intake.png) y [la pantalla de Ventas](docs/images/quick-sales.png). Ambas imágenes usan datos sintéticos. Los incrementos anteriores conservan sus cortes históricos.

El ajuste 0.7.2 se describe en [Filtros del catálogo](docs/25-filtros-catalogo.md), con [lista de categorías](docs/images/catalog-category-options.png) y [productos filtrados](docs/images/catalog-filtered.png). Son vistas de pruebas con datos sintéticos. La entrega 0.7.1 se conserva como antecedente en [Catálogo de consulta](docs/24-catalogo-consulta.md).

Para abrir el programa, haz doble clic en **Iniciar Valinor Sanctum.cmd** en la raíz del proyecto. Inicia directamente en **Ventas** desde la entrega vigente de `dist/ValinorSanctum2`; esa ruta se actualiza al empaquetar. El menú ya no contiene Inicio ni Sistema. Las bases nuevas se configuran automáticamente como Valinor, COP, 0 decimales y hora de Bogotá, sin formulario de alta. La copia versionada 0.26.0 está en `dist/0.26.0/ValinorSanctum2/valinor_sanctum_2.exe` y su ZIP en `dist/valinor-sanctum-2-0.26.0-windows-x64.zip`. Conserva las DLL y la carpeta data junto al ejecutable. El selector local abre el perfil `valinor`; las pruebas siguen conservadas en `development`. Las bases propias v1–v15 se actualizan con respaldo SQLite previo; las versiones anteriores no pueden abrir v16. El almacenamiento sigue dentro de `C:/proyectos/valinor_sanctum_2`.

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
34. [Transferencia en Compras 0.13.1 — alcance sustituido por 0.13.2](docs/34-transferencia-compras.md).
35. [Nombres de pago: Nequi en Compras y Transferencia en Ventas 0.13.2](docs/35-nombres-pago-ventas.md).
36. [Eventos vacío y categorías de Compras 0.14.0](docs/36-eventos.md).
37. [Requerimientos de la sección Eventos: acuerdos y pendientes](docs/37-requerimientos-eventos.md).
38. [Eventos operativos: creación, costos e inscripciones 0.15.0](docs/38-eventos-operativos.md).
39. [Deudores: personas, ventas fiadas y abonos 0.16.0](docs/39-deudores.md).
40. [Reportes: saldos, ventas, costos y gráficas 0.17.0](docs/40-reportes.md).
41. [Fecha y hora de Reportes 0.17.1](docs/41-horarios-reportes.md).
42. [Reportes básicos: Caja y Nequi, fecha y hora AM/PM 0.17.2](docs/42-reportes-basicos.md).
43. [Limpieza automática de entregas anteriores](docs/43-retencion-entregas.md).
44. [Conversión compatible e historial completo de saldos 0.18.0](docs/44-conversion-base.md).
45. [Menú simplificado y COP con 0 decimales 0.18.1](docs/45-menu-simplificado.md).
46. [Ventas por medio de pago en Reportes 0.19.0](docs/46-reportes-ventas.md).
47. [Ventas antiguas y nuevas en el rango 0.19.1](docs/47-ventas-historicas-rango.md).
48. [Reporte compacto con egresos 0.20.0](docs/48-reporte-compacto-egresos.md).
49. [Transferencias entre cuentas en Reportes 0.20.1](docs/49-transferencias-reporte.md).
50. [Compras por costo total e historial de PVP 0.21.0](docs/50-compras-total-historial-pvp.md).
51. [Reportes: fechas iniciales, ítems paginados y números con miles 0.22.0](docs/51-reportes-items-numeros.md).
52. [Orden del formulario de Compras y apertura condicional 0.22.1](docs/52-orden-compras.md).
53. [Estimado de catálogo y Pasadía ilimitado 0.23.0](docs/53-catalogo-ajustes-pasadia.md).
54. [SDK de GitHub Actions y asignación de cartera de ejemplo 0.23.1](docs/54-ci-cartera-ejemplo.md).
55. [Deudores al cierre y totales uniformes 0.24.0](docs/55-reporte-deudores-totales.md).
56. [Inicio automático y logo de Valinor 0.25.0](docs/56-inicio-valinor-identidad.md).
57. [Personas de Deudores en las cuentas de Ventas 0.26.0](docs/57-ventas-cuentas-deudores.md).

## Decisiones aprobadas

- Conservar Flutter Desktop y SQLite, con Windows como primer destino y operación offline.
- Construir módulos de presentación, aplicación, dominio y persistencia, manteniendo Provider como opción inicial de inyección y estado de interfaz.
- Confirmar cada operación comercial y sus efectos financieros/inventario en una sola transacción; manejar dinero en enteros y conservar precios y costos históricos.
- Usar un libro financiero interno de asientos balanceados, generado automáticamente, para distinguir ventas, cobros, compras, gastos, transferencias y capital.
- Proponer FIFO por capas para valoración de productos; aprobar esta política antes de implementarla y mostrar por separado los costos desconocidos.
- Persistir cuentas abiertas. La prioridad del MVP es registrar venta y cobro inmediato desde una única pantalla llamada Ventas; se retiró el acceso al formulario anterior.
- Compras registra mercancía pagada de contado y su salida de Efectivo/Nequi, creando el producto desde el mismo formulario. No exige un recorrido de crédito ni un pago posterior.
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

El empaquetador también publica la entrega en la ruta estable. Para publicar un ZIP ya generado: `./scripts/publish-local-bundle.ps1 -ArchivePath dist/valinor-sanctum-2-0.26.0-windows-x64.zip`. Tras publicar correctamente elimina el bundle anterior y las carpetas/ZIP de versiones inferiores de `dist`; conserva la versión vigente. Durante el reemplazo conserva temporalmente la anterior para rollback si falla. Rechaza retrocesos de versión y protege bases/perfiles. Hay que cerrar todas las copias de la aplicación de este proyecto antes de actualizarla. Para revisar la limpieza sin borrar: `./scripts/clean-old-distributions.ps1 -DryRun`.

Resultados 0.11.0: 500 pruebas aprobadas y tres omitidas por permisos de enlaces del host. Incluyen apertura financiera, reintentos, precisión, historial y conservación de registros; análisis limpio y formato de 121 Dart sin cambios. Esquema v9 aditivo con respaldo previo y migraciones v1–v8 intactas.

Actualización 0.11.1: autocompletado de Compras también desde la apertura de inventario, con datos editables y limpieza al cambiar de producto. 50 pruebas específicas aprobadas, análisis limpio y seis Dart modificados con formato limpio. Esquema v9 sin cambios.

Actualización 0.13.0: Ventas permite líneas en Deudas a nombre del cliente y cuentas mixtas; Compras presenta Transferencia como alias local de Nequi. 601 pruebas aprobadas, tres omitidas por enlaces del host, análisis y formato limpios. Esquema v11 con respaldo previo y conservación verificada de datos, saldos e inventario. La verificación y sus límites se registran en [la entrega 0.13.0](docs/33-ventas-deudas.md).

Corrección 0.13.1: el historial y los avisos de Compras también muestran Transferencia. Se conserva Nequi en los registros guardados y en las demás secciones; [ver alcance y validación](docs/34-transferencia-compras.md).

Corrección 0.13.2: Nequi permanece en Compras y Transferencia se muestra en Ventas (opciones, resumen e historial), usando la misma cuenta y conservando los registros. Esta aclaración sustituye el alcance de 0.13.0/0.13.1; [ver detalle](docs/35-nombres-pago-ventas.md).

Actualización 0.14.0: Compras deja de ofrecer Evento como categoría y Eventos tiene su propia sección vacía, antes de Sistema. Se conservan categorías, productos e historial existentes; [ver detalle](docs/36-eventos.md).
