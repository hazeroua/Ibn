# CLAUDE.md — Les Chemins d'Ibn Khaldoun

Jeu d'action-aventure en monde ouvert sous **Godot 4.7** sur la vie d'Ibn Khaldoun (1332–1406). Le projet est reconstruit depuis zéro autour de Terrain3D ; la seule feuille de route active est `Docs/06-roadmap-mvp.md`. L'ancien projet dans `Game/` est une archive et ne doit pas être repris automatiquement. Développé par Claude Code ou Codex : **l'agent fait tout** ; le porteur du projet ne fait que télécharger certaines ressources et jouer. Il ne lit pas le code : rends compte en français simple.

**Machine Windows de développement = configuration minimale du jeu :** Intel Core Ultra 7, **puce graphique intégrée Intel Arc**, aucune carte graphique dédiée. macOS Apple silicon est aussi pris en charge pour développer et lancer le jeu, sans remplacer la cible ni les budgets Windows.

## ⛔ Règle absolue n° 1 : aucun raccourci
- Chaque système est écrit **directement dans sa version définitive**, avec **la meilleure optimisation possible pour le pire cas**. Interdits : version « provisoire », « pour l'instant », « on optimisera plus tard », `TODO`/`FIXME`/`HACK`, fonctions vides ou valeurs factices présentées comme terminées, solutions qui ne tiennent que le cas moyen. (Un hook refuse ces marqueurs dans le code.)
- Avant de coder, **écrire les pires cas** : nombre maximal de PNJ, cavaliers et objets visibles ; puce intégrée ; partie de 100 heures ; galop à pleine vitesse en zone dense ; tous les systèmes actifs en même temps.
- Structures de données et algorithmes choisis pour leur **complexité dans le pire cas** ; **zéro allocation** dans les chemins par image.
- Chaque système a un **test de charge** qui reproduit son pire cas, avec des mesures.
- Si une contrainte empêche la meilleure solution : **le dire et s'arrêter pour demander**, jamais livrer au rabais.
- **Un ticket limite le périmètre, jamais la qualité.**

## ⛔ Règle absolue n° 2 : le porteur du projet ne manipule rien
- Ne jamais lui demander d'ouvrir l'éditeur Godot, de cliquer, de régler une valeur ou de créer un fichier.
- **Les scripts et données versionnés sont la source de vérité** : scènes complexes construites par script à partir de `Projet/data/`, sans réglage manuel dans l'éditeur.
- Ressources libres téléchargées par script ; seules celles derrière un compte vont dans `Docs/ressources-a-telecharger.md`, puis `Import/`.
- **Vérifie toi-même** : tests GUT, mesures, captures relues avec Read.

## Commandes actives
Toujours via les scripts (Windows : `powershell -NoProfile -ExecutionPolicy Bypass -File <script>`).

| Besoin | Commande |
|---|---|
| Installer / vérifier les outils | `Tools/installer.ps1` (versions figées : `Tools/versions.json`, chemins : `Tools/outils.json`) |
| **Tout valider** (dépendances, gdlint/gdformat, import, tests GUT, export Windows, mesure, capture, budget) | `Projet/valider.bat` ou `Projet/outils/valider.ps1 [-Scene <id>] [-Renderer vulkan\|d3d12] [-DurationSeconds 30] [-SansMesure]` |
| Lancer le dernier export | `Projet/lancer.bat` |

Rapports, journaux et captures : `Projet/rapports/<scène>/<date>-<moteur>/` ; compte rendu de la dernière validation : `Projet/rapports/derniere-validation.txt`.

Les commandes de `Scripts/Pipeline/` concernent l'ancien projet et ne valident pas le reboot.

Sous macOS Apple silicon, utiliser `Tools/installer-macos.command`, `./lancer.command` et `pwsh -NoProfile -File <script>`. Les scripts Windows et macOS coexistent ; ne jamais supprimer l'un pour adapter l'autre.

## Où se trouvent les choses
- `Docs/` : sources de vérité actives ; `Docs/archive/` : ancien projet, non contractuel.
- `Docs/06-roadmap-mvp.md` : **ne travailler que sur le premier ticket non bloqué**.
- `Projet/` : **le jeu** (socle créé par #63). `core/` (démarrage, données JSON, configuration, commandes, journal, mesure), `world/<scène>/` (scènes construites par script), `data/` (toutes les données, dont `data/budgets/<scène>.json`), `tests/unit/` (GUT), `outils/` (pipeline). Détails : `Projet/README.md`.
- `Reboot/Terrain3DValidation/` : prototype du ticket #62, conservé comme référence de mesure.
- `Game/`, `Extensions/`, `Scripts/Pipeline/` : ancien projet conservé pour consultation, sans réutilisation automatique.
- `Tools/` : outils et versions figées partagés.

## Documents à lire selon la tâche
- Toujours : `Docs/README.md`, `Docs/reboot-terrain3d.md` et le ticket actif de `Docs/06-roadmap-mvp.md`.
- Technique : `Docs/05-technologies.md`.
- Vision ou contenu futur : `Docs/01-vision-et-attentes.md`, puis les documents de conception concernés.
- Contenu (mission, dialogue, Codex, livret) : `Docs/08-synopsis.md`, `Docs/04-missions.md`, `Docs/03-game-design.md`, `Docs/07-philosophie.md` (chaque mission sert au moins une des 20 idées), `Docs/02-histoire.md` (faits). **Jouer d'abord, apprendre ensuite** : jamais de texte explicatif imposé.

## Skills et agents du projet
- Skills : `nouvelle-fonctionnalite` (méthode obligatoire de chaque tâche), `valider`, `nouvelle-carte`, `ressource-libre`, `godot-gdscript`, `extension-cpp`, `nouvelle-mission`, `fin-de-mvp` (manuelle).
- Claude Code charge les skills depuis `.claude/skills/` ; Codex charge leurs équivalents depuis `.agents/skills/` et les règles de `AGENTS.md`. Maintenir les deux variantes.
- Agents : `verificateur` (**obligatoire avant d'annoncer qu'un travail est fini**), `garant-performance` (avant tout système par image ou à grand nombre d'objets), `historien` (tout contenu historique), `directeur-artistique` (tout visuel), `concepteur-gameplay` (missions et systèmes de jeu).

## Code
- GDScript **typé statiquement partout** (y compris variables de boucle) ; formaté par gdformat (140 colonnes), analysé par gdlint (hook après chaque modification).
- C++ pour tout chemin chaud démontré par profilage ; avertissements traités comme des erreurs.
- Pas de `_process` sans nécessité ; répétitions instanciées ; lointain en niveaux de détail et imposteurs ; maillages et matériaux partagés.
- Noms de code en anglais ; commentaires et textes du jeu en français (traduisibles).
- Toute ligne `ERROR:` ou `SCRIPT ERROR:` de Godot fait échouer le pipeline : corriger la cause, ne jamais filtrer le message.
- Version de Godot et des dépendances **figées** (`Tools/versions.json`) : ne rien changer sans le demander.

## Performance (non négociable)
**60 i/s en 1080p (FSR 2) sur la puce Intel Arc intégrée, dans le pire cas.** Budgets par scène dans `Projet/data/budgets/`. Ne jamais assouplir un budget sans l'accord du porteur du projet ; signaler immédiatement tout dépassement.

## Fin de chaque tâche
Rapport en français simple : ce qui a changé ; pires cas traités et mesures ; **la commande unique pour essayer** ; ressources à télécharger éventuelles. Un ticket = une branche Git = un ou plusieurs commits clairs.

## Histoire
Ne jamais contredire `Docs/02-histoire.md` ; tout contenu inventé porte `"statut_historique": "F"` (fiction) ou `"P"` (plausible) ; peuples, religions et cultures représentés avec respect et nuance.
