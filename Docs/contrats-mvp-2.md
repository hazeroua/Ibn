# Contrats du MVP 2 — Le désert

> Même principe que `Docs/contrats-mvp-1.md` : sept tickets indépendants, chacun dans son worktree (`mvp-2/<nom>`), plus l'intégration (#8). Un ticket ne modifie jamais un fichier possédé par un autre. Les tests de chaque ticket utilisent leurs propres doublures.

## Décision préalable : pas de Terrain3D
Terrain3D fait planter Godot 4.7.2 (voir `Docs/05-technologies.md`). Le désert reprend donc l'approche par tuiles de maillages de la carte « collines », étendue à 4 × 4 km grâce au streaming.

## Règles communes
- Partir de `main`, branche `mvp-2/<nom>`, skill `nouvelle-fonctionnalite`, pires cas écrits, code définitif, test de charge mesuré. Le C++ est obligatoire pour streaming et génération (`Extensions/src/`).
- La CI est désactivée : valider en local (gdlint, gdformat 140 colonnes, tests GUT). Ne pas fusionner dans `main` : le coordinateur fusionne.
- Monde : repère en mètres, désert centré en (0, 0), de −2000 à +2000 sur x et z. Cellule de streaming : **250 m** (grille 16 × 16, identifiant `Vector2i`).

## Terrain du désert (ticket #1)
- Classe `DesertHeightfield` (`res://world/desert/desert_heightfield.gd`) : `height_at(x: float, z: float) -> float`, `normal_at(x, z) -> Vector3`, `surface_at(Vector3) -> StringName` (`sable`, `pierre`, `terre`), déterministe (graine dans `res://data/desert/desert.json`).
- `DesertTerrainCell` : construit une cellule (maillage à 4 niveaux de détail, collision couche 1) : `build_cell(cell: Vector2i) -> Node3D`.
- Paysage : plans d'eau (`water_bodies`) et oueds (`wadis`) dans `desert.json`, lus par `LandscapeFeatures` (`DesertHeightfield.features`) ; le fond des plans d'eau est aplani, `surface_at` = terre autour.

## Streaming (ticket #2, C++)
- Classe C++ `WorldStreamer` : `register_provider(provider: Object)` avec un fournisseur qui expose `build_cell(cell: Vector2i) -> Node3D`; `set_focus(position: Vector3, velocity: Vector3)` ; charge de façon asynchrone, décharge hors rayon, **budget par image** (ms) dans `res://data/streaming/streaming.json`, anticipe selon la vitesse (galop 15 m/s).
- Signaux `cell_loaded(cell)`, `cell_unloaded(cell)`. Aucune allocation par image.

## Végétation (ticket #3, C++)
- Classe C++ `VegetationScatter` : `scatter(cell: Vector2i, heightfield: Object, seed: int) -> Dictionary` renvoyant, par espèce (`palmier`, `buisson`, `herbe_seche`), un `PackedFloat32Array` de transformées pour un `MultiMesh`. Règles (pente, altitude, distance à l'oasis, densité) dans `res://data/desert/vegetation.json`. Pire cas : oasis, densité maximale.

## Rochers, palmiers, eau (ticket #4)
- Modèles produits par `Scripts/Blender/` (rochers 3 variantes × 3 LOD, palmier 2 variantes × 3 LOD, imposteur lointain), manifeste `res://data/assets/desert_props.json`, dossier `res://assets/desert/`.
- Eau de l'oasis : `OasisWater` (`res://world/desert/oasis_water.gd`), shader d'eau peu coûteux, `build(center: Vector2, radius: float) -> Node3D`.
- Textures sable et roche Poly Haven : `Game/data/assets/polyhaven.json` (ajout de lignes seulement).

## Jour et nuit (ticket #5)
- Autoload `DayNight` (`res://world/sky/day_night.gd`) : `time_of_day: float` (0–24 h), `set_time(hours)`, `time_scale` ; pilote soleil (`DirectionalLight3D`), ciel procédural, étoiles, lune, brouillard et lumière ambiante. Courbes dans `res://data/sky/day_night.json`. Signal `time_changed(hours)`. Fournit `WorldEnvironment` via `DayNight.build_environment() -> Node`.

## Vent, poussière, chaleur (ticket #6)
- Autoload `Wind` (`res://world/wind/wind.gd`) : `direction: Vector2`, `strength: float` (0–1), `gust` ; expose les uniformes globaux de shader `wind_direction`, `wind_strength`, `wind_time` (utilisables par la végétation). Sable qui vole (particules GPU), brume de chaleur à l'horizon, son du vent (`Game/audio/`). Réglages `res://data/wind/wind.json`.

## Propriété des fichiers
| Ticket | Possède |
|---|---|
| #1 Terrain | `Game/world/desert/` (sauf `oasis_water.gd`), `Game/data/desert/desert.json`, `Game/tools/builders/build_desert.gd`, `Game/tests/unit/test_desert_*.gd`, budgets `desert.json` |
| #2 Streaming | `Extensions/src/world_streamer*`, `Game/data/streaming/`, `Game/tests/unit/test_streaming_*.gd` |
| #3 Végétation | `Extensions/src/vegetation_*`, `Game/data/desert/vegetation.json`, `Game/tests/unit/test_vegetation_*.gd` |
| #4 Props et eau | `Scripts/Blender/` (nouveaux scripts), `Game/assets/desert/`, `Game/data/assets/desert_props.json`, `Game/world/desert/oasis_water.*`, `Game/tests/unit/test_props_*.gd` |
| #5 Jour/nuit | `Game/world/sky/`, `Game/data/sky/`, `Game/tests/unit/test_daynight_*.gd` |
| #6 Vent | `Game/world/wind/`, `Game/data/wind/`, `Game/audio/wind/`, `Game/tests/unit/test_wind_*.gd` |
| #8 Intégration | `Game/project.godot`, `Scripts/Pipeline/valider.ps1`, la scène de jeu du désert, `Game/data/desert/route_joueur.json`, `Docs/06-roadmap-mvp.md` |

## Saisons et panneau de temps (ticket #16, demandé par le porteur du projet)
- Autoload `Seasons` (`res://world/seasons/seasons.gd`) : `season: StringName` (`printemps`, `ete`, `automne`, `hiver`), `set_season(id)`, `blend(from, to, t)` pour transition douce ; réglages dans `res://data/seasons/seasons.json` (par saison : teinte et intensité du soleil, hauteur maximale du soleil, durée du jour, densité du brouillard, couleur de l'herbe/des palmes, force moyenne du vent, quantité de poussière). Signal `season_changed(id)`. Fournit des multiplicateurs lus par `DayNight`, `Wind` et la végétation via les uniformes globaux de shader `season_*` (aucune dépendance directe de code).
- Panneau `TimePanel` (`res://ui/time_panel/time_panel.tscn` construit par script) : ouvert/fermé par la touche **F2** (action `toggle_time_panel`), curseur de l'heure (0–24 h), vitesse du temps (0, 1, 60, 600, 3600), boutons des 4 saisons, curseur de force du vent, utilisable à la souris et à la manette. Il appelle `DayNight`, `Seasons` et `Wind` uniquement par leurs méthodes publiques.
- Fichiers possédés : `Game/world/seasons/`, `Game/data/seasons/`, `Game/ui/time_panel/`, `Game/tests/unit/test_seasons_*.gd`, `test_time_panel_*.gd`.
