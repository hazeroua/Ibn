@echo off
rem Lance la dernière version exportée du jeu (produite par valider.bat).
if not exist "%~dp0build\IbnKhaldoun.exe" (
    echo Aucun export trouve : lancez d'abord valider.bat.
    pause
    exit /b 1
)
start "" "%~dp0build\IbnKhaldoun.exe" %*
