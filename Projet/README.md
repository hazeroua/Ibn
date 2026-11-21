# Projet — socle du reboot Terrain3D

Nouveau projet Godot du jeu, créé par le ticket [#63](https://github.com/hazeroua/Ibn/issues/63). Il ne dépend d'aucun fichier de l'ancien dossier `Game/`.

## Essayer

- `valider.bat` : commande unique. Elle installe Terrain3D et GUT aux versions figées, analyse le GDScript, importe le projet, lance les tests, exporte le jeu Windows, puis mesure la scène de test sur la machine et la compare à son budget.
- `lancer.bat` : lance le dernier export. La scène de test s'ouvre directement, avec une caméra libre :
  - ZQSD ou flèches : se déplacer ;
  - souris : regarder ;
  - Maj : aller très vite ;
  - E ou Espace : monter ;
  - A ou Ctrl : descendre ;
  - Échap : libérer la souris.

Options de `valider.bat` : `-Renderer d3d12`, `-DurationSeconds 60`, `-Scene <id>`, `-SansMesure`.

## Organisation

```text
Projet/
├── project.godot         Forward+, Vulkan, Jolt, 1080p, FSR 2 à 67 %
├── core/
│   ├── boot/             Démarrage, options de lancement, catalogue des scènes
│   ├── config/           Configuration graphique
│   ├── data/             Lecture et validation des JSON
│   ├── input/            Actions clavier, souris et manette
│   ├── log/              Journal (user://logs/ibn.log)
│   └── perf/             Mesure automatique, statistiques, budgets
├── world/terrain_test/   Scène de test Terrain3D (4 × 4 km)
├── data/                 Toutes les données : config, scènes, budgets
├── tests/unit/           Tests GUT
├── outils/valider.ps1    Pipeline complet
├── addons/               Terrain3D et GUT, installés par le pipeline (non versionnés)
├── build/                Export Windows (non versionné)
└── rapports/             Journaux, rapports JSON et captures (non versionnés)
```

## Lancement en ligne de commande

```text
IbnKhaldoun.exe -- [--scene=<id>] [--measure --report-dir=<dossier> [--duration=30] [--warmup=5]]
```

Codes de sortie : 0 = réussi, 1 = erreur de configuration ou d'exécution, 2 = budget dépassé.

## Pires cas couverts par la scène de test

- terrain complet de 4 096 × 4 096 m à 2 m entre sommets, 16 régions de 1 024 m ;
- déplacement continu à 70 m/s, soit environ quatre fois un galop, en mesure automatique comme en caméra libre ;
- collisions dynamiques autour de la caméra, vérifiées une fois par seconde ;
- rendu 1 920 × 1 080 avec FSR 2 à 67 %, synchronisation verticale coupée pendant la mesure ;
- aucune allocation par image dans la sonde de mesure ni dans la caméra.

Budget : `data/budgets/terrain_test.json`.
