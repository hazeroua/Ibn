---
name: valider
description: Lance la chaîne de vérification du reboot Terrain3D et corrige jusqu'au vert. Pour le ticket #62, valide le prototype sous Vulkan et D3D12 ; après #63, suit le pipeline documenté du nouveau socle.
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

## Après le ticket #63

Le ticket #63 doit créer une commande unique de validation et la documenter dans `Docs/05-technologies.md`. Tant que cette commande n'existe pas, l'ancien pipeline ne constitue pas une preuve du reboot.

## Règles

- Corriger toute erreur, puis relancer la chaîne complète.
- Ne jamais filtrer un message d'erreur légitime.
- Ne jamais assouplir un budget sans accord explicite.
- Les mesures de l'ancien projet dans `Mesures/` ne valident aucun ticket #62 à #68.
