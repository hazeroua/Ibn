---
name: valider
description: Lance la chaîne de vérification du reboot Terrain3D et corrige jusqu'au vert. Commande unique : `Projet/valider.bat`.
---
# Valider le reboot

## Ticket #62 — Terrain3D

Depuis `Reboot/Terrain3DValidation/` :

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\run-validation.ps1 -Renderer vulkan -DurationSeconds 30 -ToolchainRoot C:\Projets\IbnKhaldoun
powershell -NoProfile -ExecutionPolicy Bypass -File .\run-validation.ps1 -Renderer d3d12 -DurationSeconds 30 -ToolchainRoot C:\Projets\IbnKhaldoun
```

Cette vérification de 30 secondes doit être verte avant chaque commit. Le porteur du projet a décidé qu'elle suffit pour fermer #62 : les sessions de 30 minutes ne sont pas exigées.

Contrôler pour chaque moteur :

- code de sortie nul ;
- aucune ligne `ERROR:`, `SCRIPT ERROR:` ou `CRASH` ;
- `budgets_passed: true` dans le rapport JSON ;
- durée demandée réellement mesurée après préchauffage ;
- aucune collision manquée ;
- matériel Intel Arc attendu ;
- capture 1 920 × 1 080 ouverte et relue visuellement.

## Depuis le ticket #63 — commande unique

```powershell
Projet\valider.bat
```

Équivalent : `powershell -NoProfile -ExecutionPolicy Bypass -File Projet\outils\valider.ps1 [-Scene <id>] [-Renderer vulkan|d3d12] [-DurationSeconds 30]`.

Étapes : dépendances figées (Terrain3D, GUT), ressources libres vérifiées par empreinte, gdlint et gdformat, import, constructeurs des scènes, tests GUT, export Windows, mesure de chaque scène sur le GPU, captures, comparaison à `Projet/data/budgets/<scène>.json`. Le script s'arrête à la première erreur ou ligne `ERROR:` d'un journal.

Contrôler ensuite :

- `Projet/rapports/derniere-validation.txt` se termine par « VALIDATION RÉUSSIE » ;
- `rapport.json` : `budgets_passed: true`, matériel Intel Arc ;
- `capture.png` et les captures `vue_*.png` (1 920 × 1 080) ouvertes et relues visuellement.

## Règles

- Corriger toute erreur, puis relancer la chaîne complète.
- Ne jamais filtrer un message d'erreur légitime.
- Ne jamais assouplir un budget sans accord explicite.
- Les mesures de l'ancien projet dans `Mesures/` ne valident aucun ticket #62 à #68.
