# Reglas de este repositorio

## Límites obligatorios

- Este repositorio es `C:\proyectos\valinor_sanctum_2`.
- `C:\proyectos\valinor_ludoteca` es referencia exclusivamente de lectura. No escribir archivos, temporales, configuraciones, `.git`, índices, dependencias ni bases allí. Para lecturas Git usar `git --no-optional-locks`.
- No abrir una base de producción con una herramienta o aplicación que pueda escribir. No ejecutar el POS original, migraciones, formateadores ni `flutter pub get` en el original.
- Solo escribir dentro del repositorio nuevo. No instalar herramientas globales, modificar perfiles ni alterar rutas ajenas sin autorización específica.
- No copiar `.git`, secretos, credenciales, instaladores o bases de producción del original.
- No compartir rutas de datos modificables con el original; desarrollo, pruebas y producción de 2.0 tendrán almacenamiento propio.

## Fase vigente

Diseño aprobado expresamente por el propietario el 18 de octubre de 2026, America/Bogota: «Sí lo apruebo». Está autorizada la etapa 3: primera estructura Flutter ejecutable, almacenamiento independiente y pruebas iniciales. Continuar en incrementos verificables con datos sintéticos. La aprobación no autoriza migraciones de producción ni modificar el POS original.

Fundación implementada y probada. El propietario autorizó expresamente instalar Visual Studio Build Tools con C++ mediante «Sí autorizo», en respuesta a la explicación de que modifica componentes compartidos y registro de Windows fuera del nuevo directorio. Está autorizado ejecutar scripts/install-build-tools.ps1 -Install, comprobar Flutter y compilar/validar el ejecutable con datos sintéticos. La excepción se limita a las herramientas de desarrollo necesarias; el POS original y sus datos siguen siendo solo lectura. No reiniciar Windows automáticamente.

Etapa 3 de fundación 0.1.0 completada el 19/10/2026: Build Tools instalado, ejecutable y ZIP generados, guardado confirmado manualmente por el propietario y perfil recuperado al reabrir, con dos verificaciones de solo lectura coincidentes. El bundle final de dist abrió un espacio vacío y mostró cuatro indicadores Correcto; se cerraron ambas aplicaciones. Consultar docs/11-validacion-windows.md y docs/evidence/windows-validation.json. La captura de imagen falló; las observaciones del agente se hicieron por accesibilidad y teclado. No confundir la compilación smoke de build con el bundle final de dist. Los módulos comerciales y la transición a producción siguen pendientes.

## Reglas del producto

- Flutter Desktop + SQLite offline como propuesta inicial; sin servicios externos obligatorios.
- Dinero en enteros con escala explícita; nunca `double` para cálculos financieros o persistencia monetaria.
- Operaciones que afectan venta, pagos, stock y libro financiero deben ser atómicas e idempotentes.
- Costos y precios históricos inmutables; reversas trazables en lugar de borrar operaciones confirmadas.
- Ausencia de costo o información no equivale a cero. Mostrar calidad y cobertura de métricas.
- Sin metas económicas particulares, saldos reales de ejemplo ni recomendaciones basadas en cifras ocultas.
- Pruebas con datos sintéticos y bases exclusivas dentro del nuevo proyecto.
- No hacer importaciones de producción ni sincronización bidireccional. Un importador futuro solo aceptará respaldos verificados y requerirá conciliación.

## Entregas

En cada incremento informar archivos cambiados, decisiones, verificaciones efectivamente realizadas y pendientes. No afirmar pruebas, compilación o validaciones que no se hayan ejecutado. Mantener los documentos consistentes con el código cuando exista.
