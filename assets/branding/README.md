# Marca de Valinor

`valinor-original.png` es el logo del barco y las montañas tomado del recurso `assets/logo_valinor.png` del proyecto original, que se consultó exclusivamente en lectura. El propietario confirmó su uso para el programa y la interfaz.

`tool/build_brand_assets.ps1` conserva el dibujo y sus textos, recorta únicamente el margen blanco exterior y genera:

- `valinor-logo.png`: recurso de interfaz de 512 px de ancho.
- `windows/runner/resources/app_icon.ico`: icono de Windows con imágenes PNG de 16, 20, 24, 32, 40, 48, 64, 128 y 256 px.

El proceso usa System.Drawing de Windows; no instala paquetes ni modifica el original. Solo el PNG optimizado se incluye como asset de Flutter. El ICO se incorpora al ejecutable mediante Runner.rc.
