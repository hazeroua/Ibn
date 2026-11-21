# 00 — Installation et exécution

## Récupérer le dépôt

La configuration Git du projet utilise SSH :

```powershell
git clone git@github.com:hazeroua/Ibn.git C:\Projets\IbnKhaldoun
```

Utiliser un chemin court, hors OneDrive.

## Installer les outils

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File C:\Projets\IbnKhaldoun\Tools\installer.ps1
```

Le script est relançable. Les versions sont figées dans `Tools/versions.json` et les chemins détectés sont écrits dans `Tools/outils.json`.

Principaux composants : Godot 4.7.2, modèles d'export Windows, Python et gdtoolkit, outils de compilation, Blender et dépendances Godot dont Terrain3D 1.1.0.

## Exécuter le prototype actif

```powershell
Set-Location C:\Projets\IbnKhaldoun\Reboot\Terrain3DValidation
powershell -NoProfile -ExecutionPolicy Bypass -File .\run-validation.ps1 -Renderer vulkan -DurationSeconds 30 -ToolchainRoot C:\Projets\IbnKhaldoun
```

Pour D3D12, remplacer `vulkan` par `d3d12`. Sans `-DurationSeconds`, le protocole final dure 1 800 secondes.

Les rapports, journaux, captures et exports sont placés dans les dossiers ignorés `reports/` et `build/` du prototype.

## Projet historique

Les anciennes commandes sous `Scripts/Pipeline/` concernent le projet archivé dans `Game/`. Elles ne valident pas le reboot et ne doivent pas être utilisées pour fermer un ticket #62 à #68.

## En cas d'échec

- Lire le journal associé au moteur de rendu dans `reports/`.
- Toute ligne `ERROR:`, `SCRIPT ERROR:` ou `CRASH` invalide l'exécution.
- Ne pas assouplir un budget pour obtenir un résultat vert.
- Corriger, exporter à nouveau et relancer le protocole complet.
