# AGENTS.md — Les Chemins d'Ibn Khaldoun

Ce dépôt accepte **Codex et Claude Code**. `CLAUDE.md` reste la référence complète des contraintes du projet ; Codex doit le lire avec les documents qu'il indique et ne doit ni supprimer ni contourner les fichiers `.claude/`.

## Plateformes conservées

- Windows reste la cible minimale du jeu et de la CI, avec Intel Arc intégré, 1080p, FSR 2 et 60 images par seconde.
- macOS Apple silicon est une plateforme de développement et d'exécution supplémentaire. Elle ne remplace ni les scripts, ni l'export, ni les budgets Windows.
- Utiliser `lancer.bat` sous Windows et `./lancer.command` sous macOS.
- Le pipeline partagé reste dans `Scripts/Pipeline/*.ps1`. Sous macOS, l'appeler avec PowerShell 7 (`pwsh`) ; ne pas créer une seconde implémentation divergente en shell.

## Skills Codex

Les skills de projet sont dans `.agents/skills/`. Sélectionner le skill pertinent avant d'agir :

- `nouvelle-fonctionnalite` pour toute tâche de développement ;
- `valider` avant de rendre la main ;
- `godot-gdscript`, `extension-cpp`, `nouvelle-carte`, `nouvelle-mission` ou `ressource-libre` selon le domaine ;
- `fin-de-mvp` uniquement lorsque le porteur demande de clôturer un MVP.

Les équivalents Claude dans `.claude/skills/` restent volontairement présents. Lorsqu'une règle commune évolue, maintenir les deux variantes cohérentes sans remplacer l'une par l'autre.

## Vérification

Préserver les changements locaux sans rapport avec la tâche. Avant d'annoncer un travail terminé, faire une revue indépendante du diff si les outils de sous-agent sont disponibles, corriger les points bloquants, puis relancer la validation adaptée à la plateforme.
