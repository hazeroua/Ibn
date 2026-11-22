# Projet — le jeu

Projet Godot du jeu, créé par le ticket [#63](https://github.com/hazeroua/Ibn/issues/63). Il ne dépend d'aucun fichier de l'ancien dossier `Game/` : le personnage joueur de `player/` en est une copie, faite à la demande du porteur du projet (voir plus bas).

## Essayer

- `valider.bat` : commande unique. Elle installe Terrain3D et GUT aux versions figées, télécharge et vérifie les ressources libres, prépare le personnage avec Blender (installé par `Tools/installer.ps1`), analyse le GDScript, importe le projet, construit les scènes, lance les tests, exporte le jeu Windows, puis mesure chaque scène sur la machine et la compare à son budget.
- `lancer.bat` : lance le dernier export. Le Sahara s'ouvre directement, avec le personnage joueur vu à la troisième personne :
  - ZQSD ou flèches (stick gauche) : marcher ; stick à moitié : marche lente ;
  - Maj (clic du stick gauche) : courir ;
  - Ctrl (bouton LB) : marche lente ;
  - Espace (bouton A) : sauter ;
  - souris (stick droit) : regarder ; molette (croix haut et bas) : rapprocher ou éloigner la caméra ;
  - T (bouton Y de la manette) : passer au matin, à midi ou à la fin de journée ;
  - Échap : libérer la souris ; un clic la reprend.

Options de `valider.bat` : `-Scene <id>` (par défaut, toutes les scènes du catalogue), `-Renderer d3d12`, `-DurationSeconds 60`, `-SansMesure`, `-SansExport`, `-SansSon`, `-BudgetsBloquants`.

Sous macOS et Linux : `pwsh -NoProfile -File Projet/outils/valider.ps1` (même script, mêmes étapes ; budgets affichés sans bloquer). Différences et dépannage : `Docs/validation-multi-os.md`.

## Organisation

```text
Projet/
├── project.godot           Forward+, Vulkan, Jolt, 1080p, FSR 2 à 67 %
├── core/
│   ├── boot/               Démarrage, options de lancement, catalogue des scènes
│   ├── config/             Configuration graphique
│   ├── data/               Lecture et validation des JSON, manifeste des ressources
│   ├── input/              Actions clavier, souris et manette
│   ├── log/                Journal (user://logs/ibn.log)
│   └── perf/               Mesure automatique, statistiques, budgets
├── player/                 Personnage joueur et caméra à la troisième personne (copie de la première version)
├── world/
│   ├── common/             Atmosphère (Sky3D, poussière, chaleur), aide, corps de test des collisions
│   ├── sahara/             Sahara : réglages, générateur, sols, constructeur, scène
│   └── terrain_test/       Scène de test du socle (#63)
├── data/                   Toutes les données : config, scènes, budgets, ressources
├── tests/unit/             Tests GUT
├── outils/                 valider.ps1 (pipeline), construire.gd (constructeurs), blender/ (préparation du personnage)
├── ressources/telechargees/  Textures et source du personnage téléchargées (non versionnées)
├── generated/              Régions Terrain3D, textures et personnage construits (non versionnés)
├── addons/, build/, rapports/  Dépendances, export et rapports (non versionnés)
└── README.md
```

## Le Sahara (ticket #64)

Carte de 4 × 4 km construite par `world/sahara/sahara_builder.gd` à partir de `data/sahara/sahara.json` :

- **reg** (plaine de gravier) au nord-ouest, ondulé, avec des voiles de sable et des plaques de terre sèche ;
- **erg** (champ de dunes) au sud-est : dunes transversales poussées par un vent de nord-est (face au vent douce, face sous le vent à environ 30°), dunes secondaires, crêtes irrégulières ;
- **repères** visibles de loin : la Gara de l'Ouest (plateau en gradins de 115 m), la Crête de l'Est, le Grand et le Petit Piton, la Grande Dune (dune étoilée de 105 m) ;
- **oueds** secs : l'oued principal et l'oued de la Gara, lits de terre craquelée, berges adoucies, dunes effacées à leur approche ;
- **sols** : sable, terre sèche, gravier, roche (textures Poly Haven CC0), choisis par sommet selon la zone et la pente, avec une teinte à grande échelle, une variation « macro » et une rotation aléatoire des textures contre la répétition.

Le constructeur refuse un relief dont une cellule praticable est trop tordue pour la grille de 2 m (`max_walkable_twist_meters`) : la surface affichée et la surface de collision ne coupent pas les cellules de la même façon, et l'écart entre les deux ne dépasse jamais cette valeur là où l'on marche.

Textures : `data/ressources.json` (adresses, licence) et `data/ressources.lock.json` (empreintes SHA-256 enregistrées au premier téléchargement, vérifiées ensuite).

## L'atmosphère (ticket #66)

Ciel, soleil, nuages et brume Sky3D, poussière portée par le vent et chaleur qui fait trembler l'horizon, réglés pour trois moments (matin, midi, fin de journée) dans `data/sahara/atmosphere.json`. Intention, palette et références : `Docs/direction-artistique-sahara.md` ; crédits : `Docs/credits.md`.

## Le personnage joueur (ticket #65)

Le personnage définitif est confié au binôme du porteur du projet (ticket #65). En attendant, `player/` contient **une copie du personnage de la première version du jeu** (`Game/player/`), reprise telle quelle à la demande du porteur du projet le 22 novembre 2026 :

- **contrôleur** (`player_character.gd`, `locomotion_motor.gd`, `locomotion_settings.gd`) : marche lente, marche, course, arrêts et virages marqués, saut, pentes jusqu'à 45°, marches de 30 cm, chocs contre les murs ; réglages dans `data/player/locomotion.json` ;
- **animations** (`player_animator.gd`, `foot_contacts.gd`) : fondus entre allures, vitesse de lecture calée sur la vitesse réelle, appuis des pieds lus dans les animations ;
- **caméra** (`camera/`) : orbite, bras qui ne traverse pas le décor, suivi lissé, champ élargi en course ; réglages dans `data/player/camera.json` ;
- **modèle** : mannequin de l'Universal Animation Library de Quaternius (CC0), téléchargé par `valider.bat` (`data/ressources.json`, dossier `quaternius_ual`) puis préparé par Blender (`outils/blender/preparer_personnage.py`, recettes dans `data/player/personnage.json`) en `generated/personnages/ibn_khaldoun_jeune/ibn_khaldoun_jeune.glb`. Blender n'est relancé que si le script, le manifeste, la source ou la version de Blender changent.

Les sons de pas, l'eau et la monte de la première version ne sont pas repris : le signal `footstep` du personnage n'a pas encore d'auditeur.

Pendant la mesure du Sahara, le personnage suit le corps de test du parcours, piloté comme au clavier : son coût (physique, animation) entre dans les budgets.

## Lancement en ligne de commande

```text
IbnKhaldoun.exe -- [--scene=<id>] [--moment=<matin|midi|fin_de_journee>] [--measure --report-dir=<dossier> [--duration=30] [--warmup=5]]
```

Codes de sortie : 0 = réussi, 1 = erreur de configuration ou d'exécution, 2 = budget dépassé.

En mesure, le Sahara fait d'abord une tournée de captures : chaque moment depuis chaque point de vue (`vue_<moment>_<point>.png` : vue générale, erg au sol, oued, gara, reg), chronométrée, et une planche comparative `planche_moments.png`. Il fait ensuite un parcours de collision qui passe par les trois moments : une capsule de personnage marche, court puis file à 70 m/s sur une boucle qui traverse dunes, oued et éboulis, caméra en poursuite.

## Pires cas couverts

- terrain complet de 4 096 × 4 096 m à 2 m entre sommets, 16 régions de 1 024 m, quatre sols ;
- déplacement à 70 m/s (environ quatre fois un galop) au ras du sol, collisions reconstruites en continu autour du corps ;
- collisions à pied et à 70 m/s sur le vrai terrain, dans les tests GUT et pendant la mesure : aucune traversée, aucun blocage ;
- rendu 1 920 × 1 080 avec FSR 2 à 67 %, synchronisation verticale coupée pendant la mesure ;
- aucune allocation par image dans la sonde de mesure, la caméra et le corps de test ;
- personnage : 1 000 obstacles autour de lui, changements de direction à chaque image à pleine vitesse, pentes à l'angle limite, images de 2 à 100 ms (tests `test_player_worst_cases.gd` et voisins, repris de la première version).

Budgets : `data/budgets/<scène>.json`.
