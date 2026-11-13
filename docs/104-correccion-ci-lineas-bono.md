# Corrección de CI — Desarrollo 0.49.1

La ejecución completa de [GitHub Actions del PR #12](https://github.com/Schrei01/valinor-sanctum-v2/actions/runs/43378785036) aprobó formato y análisis, pero terminó con 964 pruebas aprobadas y una fallida: `account_payment_split_test`, caso `controller inherits the header person and a later line selection changes only that line`.

El cálculo de bonos copiaba todas las líneas de una cuenta al editar cualquiera, incluso sin bono o sin cambios en su cobertura. Los importes seguían iguales, pero se perdía la identidad de las otras líneas que comprueba la prueba existente. Se reprodujo el fallo localmente antes de corregirlo.

Ahora una línea cuya cobertura/período permanece igual conserva su instancia. La cobertura se descuenta del presupuesto antes de continuar con la siguiente línea, incluso cuando se conserva la instancia. Cambios en el saldo o la vigencia siguen recalculando las líneas afectadas. Se mantiene la comprobación anterior y se añade un caso con dos líneas marcadas y presupuesto normal, reducido y vencido, para comprobar que ninguna omita consumir su porción.

Desarrollo 0.49.1+85 conserva el esquema 29 y las reglas de 0.49.0; no hay migración ni correcciones de datos. La actualización se entrega en el mismo PR #12. Producción 1.8.0 y sus datos permanecen independientes. La integración sigue requiriendo revisión del propietario y CI completo aprobado; no se integra ni etiqueta durante esta corrección.

La validación incluye la prueba reproducida, las asignaciones de pago, las ventas con bono total/parcial/dividido, concurrencia, reintentos, Reportes y los widgets de Membresías/Ventas. Los resultados y el paquete se registran en [evidencia](evidence/ci-voucher-lines-0491.json).
