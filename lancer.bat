@echo off
rem Lance le jeu. Exemples :
rem   lancer.bat
rem   lancer.bat -Scene res://world/sandbox/sandbox.tscn
rem   lancer.bat -Export
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Scripts\Pipeline\lancer.ps1" %*
