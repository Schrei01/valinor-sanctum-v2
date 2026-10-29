@echo off
setlocal
set "SANCTUM_APP=%~dp0dist\ValinorSanctum2-Desarrollo-0.31.0\valinor_sanctum_2.exe"
if not exist "%SANCTUM_APP%" (
    echo No se encuentra la entrega Desarrollo 0.31.0.
    pause
    exit /b 1
)
start "" /D "%~dp0dist\ValinorSanctum2-Desarrollo-0.31.0" "%SANCTUM_APP%"
