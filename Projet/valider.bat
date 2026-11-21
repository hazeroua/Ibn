@echo off
rem Commande unique du socle : dépendances, analyse, import, tests, export, mesure.
rem Les paramètres sont transmis à outils\valider.ps1 (ex. : valider.bat -Renderer d3d12).
chcp 65001 >nul
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0outils\valider.ps1" %*
set RESULTAT=%ERRORLEVEL%
echo.
echo Compte rendu complet : %~dp0rapports\derniere-validation.txt
pause
exit /b %RESULTAT%
