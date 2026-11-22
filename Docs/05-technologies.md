# 05 — Technologies et architecture du reboot

## État actuel

Le jeu se trouve dans `Projet/`, socle créé par le ticket #63. Le prototype `Reboot/Terrain3DValidation/` du ticket #62 est conservé comme référence de mesure. Le projet historique dans `Game/`, ses extensions C++ et ses scènes restent présents pour consultation, mais ne sont pas des dépendances autorisées du nouveau projet.

## Versions figées

| Élément | Version ou choix |
|---|---|
| Godot | 4.7.2 stable |
| Terrain3D | 1.1.0 |
| Sky3D | 2.1.0 (ciel, soleil, nuages ; empreinte dans `Tools/versions.json`) |
| Rendu | Forward+ sous Vulkan (choisi au ticket #62) |
| Physique | Jolt |
| Mise à l'échelle | FSR 2, rendu interne à 67 % |
| Résolution cible | 1 920 × 1 080 |
| Plateforme minimale | Windows, Intel Arc intégrée |
| Langage principal | GDScript typé statiquement |
| Chemins chauds futurs | C++ via GDExtension uniquement si une mesure le justifie |

Les versions sont définies dans `Tools/versions.json`. Elles ne changent pas sans décision explicite.

## Architecture

```text
Projet/                       Le jeu (Godot 4.7.2, Terrain3D 1.1.0)
├── project.godot             Forward+, Vulkan, Jolt, 1080p (FSR 2 à 67 % appliqué à la fenêtre par data/config/graphics.json)
├── core/
│   ├── boot/                 Démarrage, options de lancement, catalogue des scènes
│   ├── config/               Configuration graphique (data/config/graphics.json)
│   ├── data/                 Lecture et validation des JSON
│   ├── input/                Actions clavier, souris, manette (data/config/input.json)
│   ├── log/                  Journal du jeu (user://logs/ibn.log)
│   └── perf/                 Sonde de mesure, statistiques d'image, budgets
├── world/<scène>/            Scènes, générateurs et constructeurs (data/<scène>/)
├── world/common/             Éclairage, aide, corps de test des collisions
├── data/                     Toutes les données ; budgets dans data/budgets/<scène>.json
├── tests/unit/               Tests GUT
├── outils/                   valider.ps1 (pipeline, lancé par valider.bat), construire.gd
├── ressources/telechargees/  Textures libres téléchargées et vérifiées (non versionnées)
├── generated/<scène>/        Régions Terrain3D et textures construites (non versionnées)
├── addons/, build/, rapports/   Générés, non versionnés
└── README.md                 Organisation, commandes et pires cas

Reboot/Terrain3DValidation/   Prototype du ticket #62, référence de mesure
Docs/                         Sources de vérité et conception durable
Game/, Extensions/, Scripts/  Ancien projet, non réutilisé automatiquement
Tools/                        Outils et versions figées partagés
```

### Démarrage

`core/boot/boot.tscn` est la scène principale. Elle lit les options passées après `--`, applique `data/config/graphics.json` et `data/config/input.json`, puis ouvre la scène demandée du catalogue `data/config/boot.json` (scène par défaut : `terrain_test`). Toute donnée invalide est signalée par une erreur explicite et ferme le jeu avec le code 1.

```text
IbnKhaldoun.exe -- [--scene=<id>] [--measure --report-dir=<dossier> [--duration=30] [--warmup=5]]
```

En mode `--measure`, la sonde `PerformanceProbe` attend que la scène soit prête, laisse passer le préchauffage, enregistre une capture, mesure chaque image sans allocation (histogramme préalloué de 0,1 ms), écrit `rapport.json`, le compare au budget de la scène et ferme le jeu : code 0 si le budget est respecté, 2 sinon. Les scènes ajoutent leurs propres mesures (par exemple les collisions manquées) avec `report_metric`.

## Responsabilités de Terrain3D

Terrain3D doit gérer :

- le relief de 4 × 4 km ;
- les niveaux de détail ;
- les textures de sol ;
- les collisions autour du joueur ;
- l'instanciation future de la végétation et des rochers.

Le relief est déterministe : une même graine et une même version doivent produire le même terrain. Aucun travail lourd ni allocation évitable ne doit être effectué à chaque image.

### Atmosphère (#66)

`world/common/atmosphere.gd` (classe `Atmosphere`) donne son identité visuelle à une scène extérieure, à partir de `data/<scène>/atmosphere.json` :

- **ciel, soleil, nuages** : Sky3D à heure fixe (temps arrêté), position solaire calculée pour 33° N, 8° E, le 15 avril 1352 ; lune, étoiles et Voie lactée éteintes ; ombres du soleil limitées à 250 m ;
- **brume sèche** : brouillard de profondeur de Godot (début, fin, courbe, opacité maximale, couleur, diffusion solaire, perspective aérienne par moment), calculé dans le rendu des objets ; le brouillard plein écran de Sky3D est désactivé (passe et copie de profondeur en moins) ;
- **moments** : matin, midi, fin de journée ; chacun fixe l'heure, l'énergie et les couleurs du soleil, les teintes du ciel, les nuages, la brume, l'étalonnage (saturation, contraste), la densité et la couleur de la poussière, et l'intensité de la chaleur ; touche T en jeu, `-- --moment=<id>` au lancement ;
- **poussière** : trois `GPUParticles3D` (voiles, grains, poussière fine, shader `dust_particle.gdshader` sans lecture de l'écran ni de la profondeur) de 96, 220 et 400 particules au plus, portés par le vent, avec fondu près de la caméra et au loin ; la densité d'un moment agit sur `amount_ratio`, sans réallocation ;
- **chaleur** : quadrilatère plein écran (`heat_haze.gdshader`) qui déforme l'image seulement au-delà de 180 m et près de l'horizon ; masqué quand l'intensité est nulle, ce qui supprime la copie de l'écran.

Seul `_process` déplace les trois émetteurs avec la caméra, sans allocation.

La mise à l'échelle 3D n'est **jamais** réglée dans `project.godot` : elle y deviendrait la valeur par défaut de toutes les `SubViewport`. La vue de 2 × 2 pixels que Terrain3D utilise pour viser le sol tomberait alors à 1 × 1 et, dès qu'un matériau lit l'écran (la chaleur), Godot échouerait à créer ses textures (« Too many mipmaps requested »). `graphics_settings.gd` l'applique à la seule fenêtre principale.

### Personnage joueur (#65)

Le personnage définitif est confié au binôme du porteur du projet. `Projet/player/` contient, à sa demande, une copie du personnage de la première version (`Game/player/`) : contrôleur `CharacterBody3D` (allures, arrêts, virages, saut, marches, pentes), machine d'animation, caméra à la troisième personne avec bras anti-collision. Le modèle est le mannequin de l'Universal Animation Library de Quaternius (CC0), préparé par Blender (`Projet/outils/blender/preparer_personnage.py`) pendant `valider.bat`. Blender est installé par `Tools/installer.ps1` (chemin noté dans `Tools/outils.json`) ; sa version entre dans l'empreinte qui décide de relancer la préparation. Pires cas repris de la première version : 1 000 obstacles autour du joueur (calcul d'une image : moyenne ≤ 1 ms, p95 ≤ 2 ms), images de 2 à 100 ms, changement de direction à chaque image.

## Pipeline : commande unique

```powershell
Projet\valider.bat [-Scene terrain_test] [-Renderer vulkan|d3d12] [-DurationSeconds 30] [-SansMesure]
```

Étapes, avec arrêt à la première erreur ou à la première ligne `ERROR:` d'un journal :

1. installation de Terrain3D et GUT aux versions de `Tools/versions.json` ;
2. téléchargement des ressources de `data/ressources.json` (textures à quatre cartes et fichiers isolés), vérifiées par leurs empreintes SHA-256 (`data/ressources.lock.json`, enregistrées au premier téléchargement) ;
3. gdlint et gdformat (140 colonnes) ;
4. import du projet ;
5. constructeurs des scènes (`outils/construire.gd`, clé `builder` du catalogue), puis import de ce qu'ils produisent ; un constructeur ne refait rien si ses données, ses ressources et son code n'ont pas changé ;
6. tests GUT ;
7. export Windows dans `Projet/build/` ;
8. mesure de chaque scène du catalogue sur le GPU de la machine, captures et comparaison au budget.

Résultats : `Projet/rapports/<date>-<moteur>/` (journaux du pipeline, puis un dossier par scène avec `jeu.log`, `rapport.json`, `capture.png` et les captures des points de vue) et `Projet/rapports/derniere-validation.txt`.

### Le Sahara (#64)

`SaharaBuilder` génère hors du jeu, en 15 s environ, le relief 2 048 × 2 048 (2 m entre sommets), la carte de contrôle Terrain3D (sol dominant, sol secondaire, mélange) et la carte de couleur, puis enregistre 16 régions dans `generated/sahara/terrain/`. Les textures Poly Haven sont empaquetées au format Terrain3D (albédo + hauteur, normale OpenGL + rugosité) en 2 048 px et importées en compression GPU avec mipmaps. La scène charge ces régions en environ 200 ms.

Contrôles de qualité du relief :

- torsion maximale d'une cellule praticable (pente < 45°) : 0,30 m, vérifiée par le constructeur. C'est l'écart maximal entre surface affichée et surface de collision, qui ne découpent pas les cellules selon la même diagonale ; les massifs reçoivent un léger flou gaussien pour qu'aucune arête ne soit plus fine qu'une cellule ;
- collisions : test GUT sur le vrai terrain (capsule à 1,6 m/s puis 70 m/s, aucune traversée ni blocage) et même parcours pendant la mesure.

Aucune extension C++ n'existe encore dans `Projet/`. La première extension justifiée par une mesure créera `Projet/extensions/<nom>/` et ajoutera sa compilation au pipeline.

## Pipeline du prototype #62

Depuis `Reboot/Terrain3DValidation/` :

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\run-validation.ps1 -Renderer vulkan -ToolchainRoot C:\Projets\IbnKhaldoun
powershell -NoProfile -ExecutionPolicy Bypass -File .\run-validation.ps1 -Renderer d3d12 -ToolchainRoot C:\Projets\IbnKhaldoun
```

Chaque exécution copie localement Terrain3D, importe le projet, produit un export Windows, lance le parcours automatique et écrit dans `reports/` :

- un rapport JSON ;
- le journal Godot ;
- une capture 1 920 × 1 080.

Les artefacts générés ne sont pas versionnés.

## Budgets

Le budget de chaque scène est dans `Projet/data/budgets/<scène>.json`. Ceux de `terrain_test` et `sahara` reprennent les limites du ticket #62 et ajoutent un temps de démarrage maximal de 5 secondes ; celui du Sahara exige en plus zéro traversée du sol et zéro blocage du corps de test, et au moins 500 m parcourus.

### Budgets du ticket #62

| Mesure | Limite |
|---|---:|
| Temps d'image p99 | 16,6 ms maximum |
| Image isolée après préchauffage | moins de 50 ms |
| Appels de rendu | 300 maximum |
| Mémoire vidéo du prototype | 512 Mio maximum |
| Collisions manquées | 0 |
| Erreurs Godot, crashs ou corruption | 0 |
| Durée de validation | 30 secondes par moteur de rendu après 5 s de préchauffage (décision du porteur du projet, 21/11/2026) |

Le rapport doit aussi conserver les temps CPU disponibles, la RAM résidente, les primitives et l'identité du GPU. Godot 4.7 n'expose pas le temps GPU par image : décision documentée pour #62, le temps d'image total (moyenne, p99, pire image) sert de mesure de référence.

## Règles pour le socle neuf

- Aucune dépendance implicite au dossier `Game/` historique.
- Toute réutilisation est examinée composant par composant après #68.
- Les scènes complexes sont générées par script à partir de données versionnées.
- GDScript reste typé et formaté ; le C++ est réservé aux chemins chauds démontrés par profilage.
- Les tests, budgets, captures et exports doivent être exécutables par une commande unique.
- La cible 60 images par seconde dans le pire cas n'est jamais assouplie pour faire passer un test.

## Décisions remplacées

L'ancienne décision d'abandonner Terrain3D reposait sur un crash du rendu logiciel Linux de l'ancien pipeline. Elle ne gouverne plus le projet : le reboot évalue Terrain3D nativement sous Windows sur la machine cible. Les documents et mesures de cette période sont conservés dans `Docs/archive/` uniquement pour l'historique.
