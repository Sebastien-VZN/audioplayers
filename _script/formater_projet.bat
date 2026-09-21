@echo off
setlocal enabledelayedexpansion

echo ---------------------------------------------------
echo Formatage Automatique Axomind (Dart)
echo ---------------------------------------------------

:: Vérification si Flutter/Dart est bien dans le PATH
where dart >nul 2>nul
if %ERRORLEVEL% neq 0 (
    echo [ERREUR] La commande 'dart' est introuvable dans le PATH.
    echo Assurez-vous que Flutter est bien installé.
    pause
    exit /b 1
)

echo.
echo Formatage de tous les fichiers .dart dans 'lib' et 'test'...
echo.

:: On lance le formatage sur tout le projet
dart format -l 150 .

echo.
echo ---------------------------------------------------
echo Analyse du code (Linter)...
echo ---------------------------------------------------

:: On lance l'analyse statique pour voir si tout est OK
flutter analyze .

echo.
echo ---------------------------------------------------
echo TerminÃ© !
echo ---------------------------------------------------
pause
