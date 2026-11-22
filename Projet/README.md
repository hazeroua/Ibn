# Projet — le jeu

Projet Godot du jeu, créé par le ticket [#63](https://github.com/hazeroua/Ibn/issues/63). Il ne dépend d'aucun fichier de l'ancien dossier `Game/`.

## Essayer

- `valider.bat` : commande unique. Elle installe Terrain3D et GUT aux versions figées, télécharge et vérifie les textures libres, analyse le GDScript, importe le projet, construit les scènes, lance les tests, exporte le jeu Windows, puis mesure chaque scène sur la machine et la compare à son budget.
- `lancer.bat` : lance le dernier export. Le Sahara s'ouvre directement, avec une caméra libre :
  - ZQSD ou flèches : se déplacer ;
  - souris : regarder ;
  - Maj : aller très vite ;
  - E ou Espace : monter ;
  - A ou Ctrl : descendre ;
  - T (bouton Y de la manette) : passer au matin, à midi ou à la fin de journée ;
  - Échap : libérer la souris.

Options de `valider.bat` : `-Scene <id>` (par défaut, toutes les scènes du catalogue), `-Renderer d3d12`, `-DurationSeconds 60`, `-SansMesure`.

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
├── world/
│   ├── common/             Atmosphère (Sky3D, poussière, chaleur), aide, corps de test des collisions
│   ├── sahara/             Sahara : réglages, générateur, sols, constructeur, scène
│   └── terrain_test/       Scène de test du socle (#63)
├── data/                   Toutes les données : config, scènes, budgets, ressources
├── tests/unit/             Tests GUT
├── outils/                 valider.ps1 (pipeline) et construire.gd (constructeurs)
├── ressources/telechargees/  Textures téléchargées (non versionnées)
├── generated/              Régions Terrain3D et textures construites (non versionnées)
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
- aucune allocation par image dans la sonde de mesure, la caméra et le corps de test.

Budgets : `data/budgets/<scène>.json`.
