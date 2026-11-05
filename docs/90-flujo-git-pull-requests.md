# Flujo de cambios mediante Pull Requests

Aprobado por el propietario el 04/11/2026. Se sustituye el push directo a `main` por este proceso:

1. Crear una rama `codex/<incremento>` desde `origin/main`.
2. Implementar el cambio y ejecutar las verificaciones adecuadas.
3. Subir la rama y abrir un PR con el cambio y su validación.
4. Esperar que GitHub termine y apruebe `verify-and-build`. El check incluye formato, análisis, suite completa, compilación y empaquetado. La rama debe estar actualizada con `main`.
5. En cambios de aplicación, probar la compilación de Desarrollo y obtener la conformidad del propietario antes del merge. Un CI aprobado no autoriza por sí solo al agente a integrar.
6. Integrar el PR, identificar las versiones publicadas con etiquetas `dev-<versión>` o `prod-<versión>` y retirar la rama temporal cuando corresponda. Una corrección solo de documentación no genera una versión del programa.

Producción se publica cuando la solicite el propietario, desde un commit integrado y validado. Se conserva la última distribución de cada edición y la separación de sus datos.

La protección de `main` exige PR, check de GitHub Actions aprobado y rama actualizada; aplica también a administradores y bloquea force push y eliminación. No se exige una aprobación formal de una segunda cuenta: la cuenta Git usada por el agente es la del propietario y GitHub no permite que el autor apruebe su propio PR. La revisión del propietario se expresa en la conversación o al integrar personalmente desde GitHub.

La adopción del flujo no requiere modificar código de la app, compilaciones, bases ni ventanas abiertas.
