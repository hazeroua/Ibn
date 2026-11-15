# CLAUDE.md — Les Chemins d'Ibn Khaldoun

Jeu d'action-aventure en monde ouvert sous **Godot 4.7** (GDScript typé + C++ via GDExtension) sur la vie d'Ibn Khaldoun (1332–1406). Développé entièrement par Claude Code : **tu fais tout** ; le porteur du projet ne fait que télécharger certaines ressources et jouer. Il ne lit pas le code : rends compte en français simple.

**Machine de développement = configuration minimale du jeu :** Windows, Intel Core Ultra 7, **puce graphique intégrée Intel Arc**, aucune carte graphique dédiée.

## ⛔ Règle absolue n° 1 : aucun raccourci
- Chaque système est écrit **directement dans sa version définitive**, avec **la meilleure optimisation possible pour le pire cas**. Interdits : version « provisoire », « pour l'instant », « on optimisera plus tard », `TODO`/`FIXME`/`HACK`, fonctions vides ou valeurs factices présentées comme terminées, solutions qui ne tiennent que le cas moyen. (Un hook refuse ces marqueurs dans le code.)
- Avant de coder, **écrire les pires cas** : nombre maximal de PNJ, cavaliers et objets visibles ; puce intégrée ; partie de 100 heures ; galop à pleine vitesse en zone dense ; tous les systèmes actifs en même temps.
- Structures de données et algorithmes choisis pour leur **complexité dans le pire cas** ; **zéro allocation** dans les chemins par image.
- Chaque système a un **test de charge** qui reproduit son pire cas, avec des mesures.
- Si une contrainte empêche la meilleure solution : **le dire et s'arrêter pour demander**, jamais livrer au rabais.
- **Un MVP limite le périmètre, jamais la qualité.**

## ⛔ Règle absolue n° 2 : le porteur du projet ne manipule rien
- Ne jamais lui demander d'ouvrir l'éditeur Godot, de cliquer, de régler une valeur ou de créer un fichier.
- **Les scripts sont la source de vérité** : scènes complexes construites par `Game/tools/builders/build_<carte>.gd` à partir de `Game/data/<carte>/` (les `.tscn` générés ne se modifient jamais, un hook l'interdit) ; modèles 3D par `Scripts/Blender/`.
- Ressources libres téléchargées par script ; seules celles derrière un compte vont dans `Docs/ressources-a-telecharger.md`, puis `Import/`.
- **Vérifie toi-même** : tests GUT, mesures, captures relues avec Read.

## Commandes
Toujours via les scripts (Windows : `powershell -NoProfile -ExecutionPolicy Bypass -File <script>`).

| Besoin | Commande |
|---|---|
| Installer / vérifier les outils | `Tools/installer.ps1` (versions figées : `Tools/versions.json`, chemins : `Tools/outils.json`) |
| **Tout valider** (lint, ressources, C++, import, scènes, tests, mesures, captures) | `Scripts/Pipeline/valider.ps1` |
| Compiler le C++ | `Scripts/Pipeline/compiler.ps1 [-Cible debug\|release]` |
| Construire une scène | `Scripts/Pipeline/construire.ps1 [-Constructeur <carte>]` |
| Tests GUT | `Scripts/Pipeline/tester.ps1` |
| Mesurer / capturer / filmer | `Scripts/Pipeline/mesurer.ps1`, `capturer.ps1`, `video.ps1` (`-Carte <carte>`) |
| Exporter le jeu Windows | `Scripts/Pipeline/exporter.ps1` |
| Lancer le jeu | `lancer.bat [-Scene res://…] [-Export]` |

Mesures et captures : `Mesures/<mvp>/<carte>/<date>/` ; journaux : `Mesures/journaux/`, `Mesures/tests/`.

## Où se trouvent les choses
- `Docs/` : conception (lire selon la tâche, ci-dessous). `Docs/06-roadmap-mvp.md` : **ne travailler que sur le MVP en cours** (réglage `ibn/projet/mvp_en_cours` de `Game/project.godot`).
- `Game/` : projet Godot. `core/` (démarrage, entrées, données JSON, pipeline), `world/` (cartes et leurs constructeurs), `data/` (toutes les données, **jamais de contenu codé en dur**), `tests/unit/` (GUT), `tests/perf/budgets/` (budgets par carte), `tools/builders/`.
- `Extensions/` : C++ (GDExtension), `src/` ; godot-cpp figé.
- `Scripts/Pipeline/` : tout le pipeline ; `.github/workflows/ci.yml` : CI Windows + Linux (rendu logiciel).

## Documents à lire selon la tâche
- Toujours : `Docs/01-vision-et-attentes.md`, la section du MVP en cours de `Docs/06-roadmap-mvp.md`.
- Technique : `Docs/05-technologies.md`.
- Contenu (mission, dialogue, Codex, livret) : `Docs/08-synopsis.md`, `Docs/04-missions.md`, `Docs/03-game-design.md`, `Docs/07-philosophie.md` (chaque mission sert au moins une des 20 idées), `Docs/02-histoire.md` (faits). **Jouer d'abord, apprendre ensuite** : jamais de texte explicatif imposé.

## Skills et agents du projet
- Skills : `nouvelle-fonctionnalite` (méthode obligatoire de chaque tâche), `valider`, `nouvelle-carte`, `ressource-libre`, `godot-gdscript`, `extension-cpp`, `nouvelle-mission`, `fin-de-mvp` (manuelle).
- Agents : `verificateur` (**obligatoire avant d'annoncer qu'un travail est fini**), `garant-performance` (avant tout système par image ou à grand nombre d'objets), `historien` (tout contenu historique), `directeur-artistique` (tout visuel), `concepteur-gameplay` (missions et systèmes de jeu).

## Code
- GDScript **typé statiquement partout** (y compris variables de boucle) ; formaté par gdformat (140 colonnes), analysé par gdlint (hook après chaque modification).
- C++ pour tout chemin chaud (streaming, foules, routines en masse, génération, cheval, tout ce qu'une mesure désigne) ; avertissements traités comme des erreurs.
- Pas de `_process` sans nécessité ; répétitions en `MultiMeshInstance3D` ; lointain en niveaux de détail et imposteurs ; occlusion dans les médinas ; maillages et matériaux partagés.
- Noms de code en anglais ; commentaires et textes du jeu en français (traduisibles).
- Toute ligne `ERROR:` ou `SCRIPT ERROR:` de Godot fait échouer le pipeline : corriger la cause, ne jamais filtrer le message.
- Version de Godot et des dépendances **figées** (`Tools/versions.json`) : ne rien changer sans le demander.

## Performance (non négociable)
**60 i/s en 1080p (FSR 2) sur la puce Intel Arc intégrée, dans le pire cas.** Budgets par carte dans `Game/tests/perf/budgets/` ; ne jamais assouplir un budget sans l'accord du porteur du projet ; signaler immédiatement tout dépassement.

## Fin de chaque tâche
Rapport en français simple : ce qui a changé ; pires cas traités et mesures ; **la commande unique pour essayer** ; ressources à télécharger éventuelles. Une fonctionnalité = une branche Git = un commit clair.

## Histoire
Ne jamais contredire `Docs/02-histoire.md` ; tout contenu inventé porte `"statut_historique": "F"` (fiction) ou `"P"` (plausible) ; peuples, religions et cultures représentés avec respect et nuance.
