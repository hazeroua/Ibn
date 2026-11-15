# Contrats du MVP 1 — Premiers pas

> Ce document permet de réaliser les tickets du MVP 1 **en parallèle**, chacun dans son propre worktree, sans attendre les autres. Il fixe ce que chaque ticket **fournit**, ce qu'il peut **supposer** des autres et **quels fichiers il possède**. Un ticket ne modifie jamais un fichier possédé par un autre ; s'il en a besoin, il le signale dans sa demande de fusion. Le ticket d'intégration (#8) assemble le tout.
>
> Toute modification de ce contrat passe par le porteur du projet (ou par Claude qui fusionne), jamais par un ticket seul.

## Règles communes à tous les tickets

- Partir de `main` à jour. Branche : `mvp-1/<nom-court-du-ticket>`.
- Lire `CLAUDE.md` et suivre la skill **`nouvelle-fonctionnalite`** (pires cas écrits, version définitive, test de charge, `valider.ps1`, agent `verificateur`).
- **Tests autonomes** : chaque ticket teste son système avec ses propres scènes ou objets de test (doublures), sans dépendre du code d'un autre ticket du MVP 1.
- À la fin : pousser la branche et **ouvrir une demande de fusion vers `main`** (titre `[MVP1] …`, `Closes #<numéro>`), avec les pires cas, les mesures, les captures et la liste des fichiers touchés. **Ne pas fusionner soi-même.**

## Couches de collision (`Game/project.godot`, posées par le ticket #8)

| Couche | Nom | Contenu |
|---|---|---|
| 1 | `monde` | Tout le décor statique : terrain, rochers, murs, bâtiments |
| 2 | `joueur` | Le personnage joueur |
| 3 | `pnj` | Personnages non joueurs (à partir du MVP 5) |
| 4 | `obstacle_camera` | Décor qui bloque la caméra sans bloquer le joueur (rare) |

Les tickets utilisent ces **numéros** dans leur code et leurs données dès maintenant.

## Surfaces du sol

- Identifiants de surface : `sable`, `pierre`, `terre`, `bois`.
- Tout collisionneur statique du décor porte la métadonnée **`surface`** (`String`) : `collider.set_meta(&"surface", "pierre")`.
- Un terrain fournit la méthode **`surface_at(world_position: Vector3) -> StringName`** (la surface dépend de la texture à cet endroit).

## Personnage joueur (ticket #1)

- Classe **`PlayerCharacter`** (`extends CharacterBody3D`), fichier `res://player/player_character.gd`, dans le groupe **`player`**.
- Couche 2, masque 1.
- Déplacement **relatif à la caméra active** (`get_viewport().get_camera_3d()`), sans dépendre d'une classe de caméra précise.
- Réglages lus dans `res://data/player/locomotion.json`.
- Allures (`StringName`) : `idle`, `walk_slow`, `walk`, `run`.
- Signaux :
  - `gait_changed(gait: StringName)`
  - `footstep(foot: int, world_position: Vector3, speed: float, collider: Object)` (foot : 0 gauche, 1 droit ; `collider` = l'objet sous le pied, ou `null`)
- Animation : propriété `animation_player: AnimationPlayer` (facultative). Si elle est renseignée, le personnage joue les animations du contrat ci-dessous ; sinon il fonctionne sans visuel (tests).

## Animations du personnage (tickets #1 et #5)

- Bibliothèque d'animation **`locomotion`** dans l'`AnimationPlayer` du modèle, animations **sur place** (pas de déplacement à la racine) :
  `idle`, `walk_slow`, `walk`, `run`, `stop_walk`, `stop_run`, `turn_left_90`, `turn_right_90`, `turn_180`.
- Modèle : 1,75 m, pieds à l'origine, regard vers **−Z**, `Skeleton3D` humanoïde.

## Modèle 3D du joueur (ticket #5)

- `res://assets/characters/<id>/<id>.glb` (+ réglages d'import), décrit dans le manifeste `res://data/assets/characters.json` (id, source, licence, hauteur, liste des animations).
- Id du personnage du MVP 1 : **`ibn_khaldoun_jeune`**.

## Caméra (ticket #2)

- Classe **`ThirdPersonCamera`** (`extends Node3D`), fichier `res://player/camera/third_person_camera.gd`, avec sa `Camera3D` enfant (active).
- Propriété **`target: Node3D`** : le nœud suivi (n'importe quel `Node3D`).
- Collisions contre la couche 1 (et 4).
- Réglages lus dans `res://data/player/camera.json`.

## Actions d'entrée (ticket #3, qui possède `res://data/input/actions.json`)

Noms définitifs, utilisés par les autres tickets **sans les déclarer eux-mêmes** (leurs tests déclarent les actions dont ils ont besoin, ou passent par une abstraction d'entrée) :

| Action | Rôle |
|---|---|
| `move_forward`, `move_back`, `move_left`, `move_right` | Déplacement (analogique à la manette) |
| `sprint` | Courir (maintenu) |
| `walk_slow` | Marche lente (maintenu) |
| `look_left`, `look_right`, `look_up`, `look_down` | Regard au stick droit |
| `camera_zoom_in`, `camera_zoom_out` | Rapprocher, éloigner la caméra |
| `look_hold` | Regard à la souris pour la caméra libre du bac à sable |
| `quit_game` | Quitter |

Le regard à la souris de la caméra à la troisième personne se fait par les mouvements de la souris capturée (pas d'action).

## Sons de pas (ticket #6)

- Singleton **`Footsteps`** (autoload déclaré par le ticket #8) ; script `res://audio/footsteps/footsteps.gd`.
- Méthode **`connect_emitter(emitter: Object)`** : se connecte au signal `footstep` de l'émetteur (contrat du personnage ci-dessus).
- Résolution de la surface : métadonnée `surface` du `collider`, sinon `surface_at()` du terrain qui possède ce collider, sinon `sable`.

## Pilotage du joueur par le pipeline (ticket #7)

- Le pipeline pilote le joueur **par les actions d'entrée** (`Input.action_press` avec intensité), comme un vrai joueur.
- Parcours : `res://data/<carte>/route_joueur.json` (points de passage, allure, durée).
- Trouve le joueur par le groupe **`player`** et suppose seulement que c'est un `Node3D`.

## Propriété des fichiers

| Ticket | Possède (crée ou modifie) |
|---|---|
| #1 Personnage | `Game/player/` (sauf `camera/`), `Game/data/player/locomotion.json`, `Game/tests/unit/test_player_*.gd` |
| #2 Caméra | `Game/player/camera/`, `Game/data/player/camera.json`, `Game/tests/unit/test_camera_*.gd` |
| #3 Contrôles | `Game/core/input/`, `Game/data/input/`, `Game/tests/unit/test_input_*.gd` |
| #4 Collines | `Game/world/collines/`, `Game/data/collines/` (sauf `route_joueur.json`), `Game/tools/builders/build_collines.gd`, `Game/tests/perf/budgets/collines.json`, `Game/tests/unit/test_collines_*.gd` |
| #5 Modèle 3D | `Scripts/Blender/`, `Game/assets/characters/`, `Game/data/assets/characters.json`, `Game/tests/unit/test_characters_*.gd` |
| #6 Sons de pas | `Game/audio/`, `Game/data/audio/`, `Game/data/assets/sounds.json`, `Game/tests/unit/test_footsteps_*.gd` |
| #7 Pipeline joueur | `Game/core/pipeline/`, `Scripts/Pipeline/` (sauf `valider.ps1`), `Game/data/*/route_joueur.json`, `Game/tests/unit/test_pipeline_*.gd` |
| #8 Intégration | `Game/project.godot`, `Scripts/Pipeline/valider.ps1`, `.github/workflows/`, `Docs/06-roadmap-mvp.md`, la scène de jeu assemblée |

Fichiers partagés ajoutés en fin de liste par plusieurs tickets (`Game/data/assets/polyhaven.json`, `.gitignore`, `Docs/ressources-a-telecharger.md`) : ajout de lignes seulement, jamais de modification des lignes des autres.
