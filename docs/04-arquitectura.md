# Arquitectura propuesta de Valinor Sanctum 2.0

Estado: diseño aprobado expresamente por el propietario el 18 de octubre de 2026. Este documento conserva el alcance de diseño; el estado de implementación y las decisiones concretadas están en [incremento 01](10-incremento-01.md).

## 1. Elección tecnológica y límites

Se propone conservar Flutter Desktop y SQLite. El original ya demuestra la adecuación funcional de una interfaz de escritorio y almacenamiento local; sus defectos se concentran en el modelado y coordinación de escrituras. Windows será el primer destino verificado. macOS/Linux serán extensiones condicionadas a pruebas y empaquetado propios, sin prometer compatibilidad por tener carpetas de plantilla.

Flutter documenta compilación nativa de escritorio para Windows/macOS/Linux. La separación de presentación y acceso a datos sigue sus recomendaciones, añadiendo casos de uso para operaciones financieras complejas. Fuentes: [Flutter Desktop](https://docs.flutter.dev/platform-integration/desktop) y [arquitectura de aplicaciones Flutter](https://docs.flutter.dev/app-architecture/recommendations).

Un monolito modular local es suficiente para el escenario inicial de una estación de trabajo. No se proponen backend, microservicios, cuenta cloud, red obligatoria ni IA generativa. Una futura operación de múltiples cajas simultáneas en máquinas distintas exigiría revisar concurrencia y arquitectura; no se compartirá una base SQLite por carpeta de red.

## 2. Responsabilidades y dependencias

~~~mermaid
flowchart TD
    UI[Views y ViewModels Flutter] --> APP[Casos de uso de aplicación]
    APP --> DOMAIN[Reglas de dominio y objetos inmutables]
    APP --> PORTS[Puertos de repositorio y unidad de trabajo]
    SQLITE[Adaptadores SQLite y migraciones propias] --> PORTS
    SQLITE --> DB[(SQLite exclusivo 2.0)]
    UI --> QUERY[Consultas de lectura y métricas]
    QUERY --> DB
    APP --> POLICY[Políticas de autorización e idempotencia]
~~~

- Presentación: navegación, formularios, teclado, selección por ID, formato, loading/error y accesibilidad. ViewModels invocan casos de uso y publican resultados confirmados.
- Aplicación: coordina autorización, validación, idempotencia y transacción completa; no decide layouts.
- Dominio: dinero/cantidades, estados, costos, clasificación de operaciones e invariantes. Dart puro, sin widgets, controllers, Provider ni SQLite.
- Datos: implementación de repositorios, consultas, migraciones, backups y transacciones. Una conexión controlada; sin singleton global mutable accesible desde cualquier widget.
- Lectura/analítica: consultas sobre registros confirmados. Proyecciones opcionales reconstruibles; no otra fuente de verdad.
- Infraestructura local: configuración por entorno, rutas, reloj, IDs, exportación y registros técnicos sin datos sensibles.

Provider/ChangeNotifier puede conservarse para inyección y ViewModels. La unidad de trabajo se inyectará explícitamente; repositorios dentro de una operación usarán el mismo ejecutor transaccional. No se creará una capa o paquete por cada tabla.

## 3. Módulos

| Dominio | Módulos | Límite y colaboración |
|---|---|---|
| Operación comercial | Catálogo/categorías; inventario; proveedores/compras; ventas; servicios; cuentas abiertas; eventos | Documentos con estados, catálogo por ID, stock/costos históricos |
| Gestión financiera | Cuentas monetarias/medios; cobros/pagos; CxC/CxP; gastos; capital; transferencias; arqueos | Libro interno de partidas balanceadas, obligaciones y conciliación |
| Inteligencia | Reportes; indicadores; rentabilidad; rotación; liquidez; tendencias; recomendaciones | Solo lee hechos; explicita cobertura y reglas |
| Planificación | Escenarios; supuestos; presupuestos; objetivos opcionales | Datos hipotéticos separados de hechos; nunca crea ventas ni movimientos |
| Transversal | Configuración; permisos/actor; auditoría; backups; importaciones | Sin secretos copiados ni vínculo modificable al original |

Compras de inventario y gastos tienen flujos distintos. Medio de pago describe el canal; cuenta monetaria representa dónde está el dinero. Nequi podrá configurarse como medio y como cuenta asociada, sin obligar a que ambos catálogos sean equivalentes.

## 4. Estructura propuesta para el siguiente incremento

Esta es una estructura futura. No se creó código ni un pubspec en este incremento.

~~~text
lib/
  app/                         arranque, composición y navegación
  core/
    domain/                    Money, Quantity, IDs, Clock, fallos tipados
    application/               UnitOfWork, actor, autorización e idempotencia
    infrastructure/            configuración, rutas, SQLite y backups
    presentation/              componentes y formato
  features/
    catalog/
    inventory/
    purchasing/
    sales/
    tabs/
    treasury/
    expenses/
    services_events/
    analytics/
    planning/
    import_export/
      domain/                  donde existan reglas propias
      application/             comandos y consultas
      data/                    adaptadores y SQL del módulo
      presentation/            Views y ViewModels
test/
  unit/
  integration/
  widgets/
integration_test/
docs/
~~~

Solo se crean las carpetas necesarias al implementar cada incremento. Los contratos compartidos financieros y de inventario se definen antes de sus consumidores, evitando importaciones circulares de pantallas.

## 5. Contratos de operaciones críticas

| Caso de uso | Efectos confirmados juntos | Fallos que no pueden dejar efectos parciales |
|---|---|---|
| Confirmar venta | Cabecera/líneas/snapshots, movimientos stock y costo, obligación y asiento; cobro inmediato opcional | Stock insuficiente, costo incompleto según política, monto inválido, doble ejecución |
| Recibir compra | Recepción/líneas, capas de costo, stock, obligación/asiento; pago aparte o conjunto | Recepción repetida, cantidades/costos inválidos |
| Cobrar deuda | Pago, componentes por cuenta, aplicación a obligación y asiento | Sobrepago no autorizado, obligación cerrada, moneda incompatible |
| Registrar gasto | Documento y obligación/asiento; pago si procede | Categoría inválida, cuenta sin fondos según política, fecha cerrada |
| Transferir | Operación, salida y entrada entre cuentas, asiento balanceado | Origen igual a destino, falta de fondos, fallo de segunda partida |
| Aporte/retiro | Documento, contraparte patrimonial y cuenta de dinero | Tratarlo como venta/gasto operativo, actor sin permiso |
| Anular/devolver | Documento de reversa, costo/stock cuando corresponde y obligación de reembolso o pago | Borrar venta confirmada, devolver más de lo vendido |
| Cerrar/arquear caja | Conteo, saldo esperado, diferencia y ajuste documentado si se confirma | Ocultar diferencia cambiando saldo directamente |

Flujo de comando: identificar solicitud estable → validar y autorizar → iniciar transacción de escritura → reconsultar estado/stock vigente → escribir documentos, costo, obligaciones y asientos → validar invariantes → marcar resultado en command_log → commit → emitir resultado a interfaz. Un fallo provoca rollback. Un reintento con la misma clave devuelve el mismo resultado; no vuelve a contabilizar. Reusar clave con otro contenido es error.

No se considerará exitosa una operación al mostrar snackbar ni al modificar memoria. El botón permanece ocupado hasta resultado; se conserva la cuenta editable si falla.

SQLite ofrece transacciones atómicas; la aplicación debe agrupar explícitamente los cambios y configurar las relaciones. Se activará y comprobará foreign_keys en cada conexión, antes de iniciar transacciones. Fuentes: [commit atómico](https://www.sqlite.org/atomiccommit.html), [claves foráneas](https://www.sqlite.org/foreignkeys.html).

## 6. Reglas financieras centrales

- Dinero: entero con moneda y escala; entradas desde texto decimal normalizado, límites comprobados y redondeo explícito. No valores no finitos ni floats para persistencia.
- Precio, descuento, impuesto aplicable, costo y categoría se conservan en snapshots de línea/documento. No se recalcula una venta pasada con el catálogo actual.
- FIFO por capas es la política propuesta; el costo total de cada capa debe conservarse exactamente aun al repartir residuos de redondeo. Política y motivo de ajustes quedan versionados.
- Cuentas abiertas editables y ventas a crédito son estados diferentes. Propuesta inicial: el borrador no descuenta stock; la entrega/consumo confirmado genera venta, costo y CxC aunque se cobre después. La interfaz debe hacer explícita esa transición.
- Cada saldo se deriva del libro; no hay setters arbitrarios de total. Las aperturas se registran como operaciones identificadas y aceptadas por el usuario.
- No se deduce que todo egreso sea gasto ni que todo ingreso de dinero sea venta.
- Lo confirmado se revierte mediante documentos vinculados, sin editar precios/costos originales.
- Métrica desconocida conserva estado desconocido y cobertura; costo cero solo significa cero cuando fue registrado expresamente.

El [modelo financiero](05-modelo-financiero.md) detalla entidades, valoración y asientos. El libro interno sirve para integridad de gestión; no se presenta como implementación de contabilidad fiscal, facturación electrónica o cumplimiento tributario.

## 7. Separación física e identidad

| Elemento | Original | Propuesta 2.0 |
|---|---|---|
| Raíz | C:/proyectos/valinor_ludoteca | C:/proyectos/valinor_sanctum_2 |
| Git | .git original intocable | .git nuevo, sin remotos ni historial copiados |
| Paquete/ejecutable | valinor_ludoteca_desktop | valinor_sanctum_2 |
| Identificador | Plantillas actuales | local.valinor.sanctum2, nuevo AppId de instalador al implementarlo |
| Base | Documentos/valinor.db | sanctum2.sqlite3, nunca buscar valinor.db por defecto |
| Desarrollo | No acceder a datos reales | <nuevo>/data/development/<profileId>/sanctum2.sqlite3 |
| Pruebas | Original no se ejecuta | <nuevo>/tmp/tests/<runId>/, sintético, o SQLite en memoria |
| Producción futura | Sigue independiente | ApplicationSupport/ValinorSanctum2/profiles/<profileId>/production/ |
| Backups/importación | No tocar respaldos existentes | Subdirectorios propios; nombres con ID/fecha; nunca sobrescribir fuente |

Las rutas de producción son propuestas y no se han creado. La resolución siempre añade el namespace exclusivo aunque la API de plataforma devuelva un directorio genérico. No habrá fallback al almacenamiento del original. Se comprobará que la ruta final no esté dentro del árbol original ni sea un alias/enlace al mismo archivo.

El entorno de desarrollo se identifica explícitamente; cualquier dataset de demostración debe poder distinguirse y no se carga en perfiles reales. No se incorporan los saldos iniciales codificados del original ni metas de ventas.

El instalador futuro usará nombre, AppId, carpeta, accesos directos y desinstalación independientes. Desinstalar 2.0 no eliminará datos de ninguna versión por defecto. Se verificará instalación simultánea sin lanzar el POS original durante esta auditoría.

## 8. Resiliencia, concurrencia y backups

Un escritor local coordinado; segunda instancia del mismo perfil bloqueada o activada en la primera. Las lecturas no comparten objetos mutables del dominio con formularios. Bloqueos/busy se manejan con límites y mensajes recuperables; no reintentos ciegos de comandos nuevos.

Se seleccionará journal_mode y política de sincronización mediante pruebas de cierre abrupto; no se desactivará durabilidad para acelerar. WAL es una opción a evaluar, no una condición asumida en la auditoría. Backups de bases activas se harán con mecanismo consistente soportado por el adaptador, sin copiar solo el archivo principal abierto. [API de backup SQLite](https://www.sqlite.org/backup.html).

Migraciones 2.0 versionadas, con checksums e historial propio, pruebas desde cada esquema soportado, backup de destino y rechazo de downgrade incompatible. Nunca ejecutarán las migraciones del código original sobre su base. Fallos de arranque se mostrarán con diagnóstico recuperable, sin recrear/borrar la base silenciosamente.

## 9. Usuarios, permisos y auditoría

Primera instalación: crear identidad local de propietario, sin contraseñas predeterminadas. Roles iniciales propuestos: propietario/administrador y operador. Permisos por acciones sensibles (ajustes, anulaciones, cierres, retiros, importación), aplicados en casos de uso, no solo ocultando botones. Registrar actor, instante, motivo, solicitud y origen documental.

La autenticación local no impide que un usuario con acceso completo al disco manipule archivos; el objetivo es control operativo y trazabilidad, sin prometer seguridad que SQLite por sí solo no aporta. Decidir protección del dispositivo, credenciales y respaldo al implementar; no copiar credenciales existentes.

## 10. Decisiones pendientes antes de programar

| Decisión | Propuesta para aprobación |
|---|---|
| Plataforma inicial | Windows, una estación operativa |
| Costeo | FIFO por capas; costo desconocido explícito para histórico |
| Unidad monetaria | COP inicialmente, escala explícita; decidir visualización y redondeo |
| Cantidades | Productos por unidades enteras; servicios con unidad/escala definida |
| Cuentas abiertas | Borrador persistido sin efecto; entrega/consumo confirma venta a cobrar |
| Deudas original | No asignar semántica automática; clasificar con propietario antes de importar |
| Permisos | Propietario/operador con permisos en aplicación |
| Impuestos/descuentos | Modelar snapshots; no habilitar tasas ni reglas fiscales supuestas |
| SDK y paquetes | Fijar versiones compatibles al crear ejecutable y correr pruebas, sin actualizar el original |

No es necesario resolver la importación productiva, todos los informes avanzados o todos los servicios para aprobar un primer núcleo. Los contratos que evitan pérdida o duplicación sí deben quedar aprobados y probados antes de uso real.
