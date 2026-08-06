@echo off
setlocal

:: --- Copie miroir du repo vers sa destination E: ---
set "SRC=C:\Devs\01_client_project\audioplayers_stable"
set "DST=E:\Projets Dev\plugin_flutter\audioplayers_stable"

echo.
echo === Copie miroir : audioplayers_stable ===
echo   Source : %SRC%
echo   Cible  : %DST%
echo.

for %%I in ("%DST%") do if not exist "%%~dpI" mkdir "%%~dpI"

robocopy "%SRC%" "%DST%" /MIR /XF "nul" /R:1 /W:1 /NFL /NDL /NJH /NJS
set "RC=%errorlevel%"

if %RC% LSS 8 (
    echo [audioplayers_stable] : OK ^(robocopy code %RC%^)
) else (
    echo [audioplayers_stable] : ECHEC ^(robocopy code %RC%^)
)

echo ---
echo Termine.
endlocal
pause