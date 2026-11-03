# Compras: recuperar el PVP anterior — Desarrollo 0.39.0

Al seleccionar un producto existente, **Usar valor** aparece junto a **PVP anterior**. Copia ese precio al campo PVP unitario y lo conserva al cambiar unidades o costo total. El PVP sigue siendo editable. Para un producto nuevo no aparece esta acción, porque todavía no tiene un precio anterior.

Se retira **Usar sugerido**. El importe sugerido y su fórmula siguen visibles; el cálculo automático previo se conserva hasta que se escriba un PVP o se pulse **Usar valor**. El botón queda deshabilitado cuando hay un ingreso pendiente que bloquea el formulario.

Esta entrega es **Desarrollo 0.39.0+68**, portable y con su base independiente en `data/development/valinor/sanctum2.sqlite3`. Se abre con **Iniciar Valinor Sanctum.cmd**. Producción sigue en **1.4.2**.

La mejora de interfaz no agrega tablas ni una migración. Esta es la primera portable de Desarrollo que incorpora el esquema 23, ya publicado en Producción 1.4.2: corrige el validador de Compras para excluir gastos anulados del saldo y de la cronología. Al abrir Desarrollo se respalda y migra su base 22 a 23, conservando los valores de sus 74 tablas. Los ejecutables antiguos no pueden abrir una base más nueva.

## Validación

- 20 pruebas existentes de Compras y apertura aprobadas, incluida la recuperación del PVP anterior con dos decimales y su conservación al cambiar costo y cantidad.
- Dos renders sintéticos aprobados e inspeccionados, en anchos 1280 y 400, con COP sin decimales. No hubo inspección visual nativa.
- Análisis sin incidencias; formato de 217 archivos sin cambios. No se ejecutó otra suite financiera ni una suite completa.
- Ensayo privado de la migración 22→23, comparando todas las filas y definiciones de las 74 tablas; integridad, claves foráneas y contenido del respaldo automático verificados.
- Inicio nativo de Desarrollo: migración 22→23 y respaldo automático verificados, con las 74 tablas y sus valores anteriores conservados. Ventana abierta y responde, con título Desarrollo; no se registraron operaciones de prueba en la base activa.
- ZIP y bundle estable: 19 archivos idénticos y sin datos privados. Se retiró la portable anterior de Desarrollo y la limpieza no dejó pendientes. Las 43 huellas de Producción, instalación vigente y selector/JSON de Desarrollo coinciden; la ventana productiva del propietario sigue abierta y su base no fue consultada.

Los archivos privados de ensayo, bases, respaldos y capturas permanecen fuera de Git y del paquete. La evidencia final de publicación está en [use-previous-pvp-039.json](evidence/use-previous-pvp-039.json).
