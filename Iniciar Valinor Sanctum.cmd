@echo off
setlocal
set "SANCTUM_APP=%~dp0dist\ValinorSanctum2\valinor_sanctum_2.exe"
if not exist "%SANCTUM_APP%" (
    echo No se encuentra la entrega actual en dist\ValinorSanctum2.
    echo Consulta README.md para preparar el paquete de Windows.
    pause
    exit /b 1
)
start "" /D "%~dp0dist\ValinorSanctum2" "%SANCTUM_APP%"
