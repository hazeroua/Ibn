# Le cheval jouable (ticket #106)

Ce document explique comment le cheval du ticket #106 est devenu montable dans le jeu, ce qui vient de la première version du jeu, et où chercher en cas de bug.

## Ce que fait le joueur

Dans le Sahara, le cheval attend à côté du personnage.

| Touche | Manette | Action |
|---|---|---|
| E | X | monter (par le flanc gauche, à moins de 3,5 m) ou descendre (à l'arrêt, flanc gauche dégagé) |
| H | croix gauche | siffler : le cheval vient par un chemin praticable, au galop de loin, au pas en approchant |
| ZQSD | stick gauche | conduire, dans la direction regardée par la caméra |
| Maj | clic du stick gauche | galop de course (endurance limitée, récupère au pas) |
| Espace | A | sauter (en mouvement) |

Quatre allures : pas, trot, galop, galop de course. Sabots et pas sonnent selon le sol (sable, terre, galets du reg, pierre), empreintes sur le sable, souffle au galop, hennissement au saut.

## D'où viennent les pièces

| Pièce | Origine | Où |
|---|---|---|
| Forme du cheval, selle, tapis, bride | cheval original du ticket #106 (Codex, itération 2) | `Projet/outils/blender/cheval/forme.py` |
| Textures (robe, muscles, cuir, laine, fer, corne, crins) | itération 3 | `Projet/outils/blender/cheval/textures.py` |
| Squelette et animations (Idle, WalkSlow, Walk, Run, Jump, Death) | cheval de Quaternius (CC0), celui de Barq dans la première version | `Projet/sources/cheval/animations_quaternius.glb`, posé par `Projet/outils/blender/cheval/squelette.py` |
| Conduite, allures, endurance, prudence (pentes, à-pics, obstacles, marches), saut, sifflet, monte et descente, empreintes, sons | première version du jeu (`Game/horse/`), copiée à la demande du porteur du projet | `Projet/horse/` |
| Sons de pas (sable, terre, pierre) | première version (`Game/audio/footsteps/`), sons CC0 de Fantozzi et Kenney | `Projet/audio/`, `data/audio/footsteps.json`, `data/ressources.json` (dossier « sons ») |
| Souffle et hennissement | BigSoundBank (CC0), déjà utilisés par la première version | `Projet/sources/sons/` |
| Animations du cavalier (monter, en selle, galop penché, descendre) | personnage repris au ticket #65 | `Projet/player/`, `data/player/personnage.json` |

## Préparation du modèle (valider.bat, étape 2)

`Build-Horse` (dans `Projet/outils/valider.ps1`) lance Blender trois fois :

1. `forme.py --sortie generated/chevaux/travail` → `forme.blend` (environ 30 s) ;
2. `textures.py --entree …/forme.blend --sortie generated/chevaux/travail` → 21 textures cuites et `textures.blend` (environ 1 min 30) ;
3. `squelette.py --entree …/textures.blend --animations sources/cheval/animations_quaternius.glb --sortie generated/chevaux/cheval_sahara/cheval_sahara.glb` (environ 10 s).

Rien n'est refait tant que les trois scripts, la source d'animations et la version de Blender ne changent pas (empreinte `cheval_sahara.glb.empreinte`). Le dossier de travail porte un `.gdignore` : sans lui, Godot essaierait d'importer les `.blend` (et réclamerait Blender). Journaux : `rapports/<date>/cheval-forme.log`, `cheval-textures.log`, `cheval-squelette.log` et `cheval.json` (triangles, os, animations).

### Comment le squelette est posé (squelette.py)

- Le squelette de Quaternius regarde vers −Y et mesure 4,11 unités au garrot ; il est tourné de 90° et mis à l'échelle 1,55/4,11 (garrot du cheval : 1,55 m). Les translations des animations sont multipliées par la même échelle.
- Chaque os est ensuite replacé sur l'anatomie de `forme.py` (table `P` du script) : épaule, genou et sabot des antérieurs, hanche, jarret et sabot des postérieurs, dos, croupe, encolure, tête, quatre os de queue. L'orientation (roulis) de chaque os est conservée pour que les rotations des animations gardent leur sens.
- Poids : la pondération automatique de Blender échoue sur cette peau (aucun poids). Chaque sommet reçoit donc un poids selon sa distance aux trois os les plus proches (∝ 1/d⁵), lissé six fois le long des arêtes. Crins : encolure, tête ou queue ; sabots : bas de la jambe ; selle, tapis, galon et coutures : os « Torso » ; yeux et oreilles : tête ; cuir et fer : tête, encolure ou dos selon la pièce.
- Les os de pied (cibles d'inverse cinématique de Quaternius), la racine, « Body » et les os d'épaule et de hanche ne déforment pas la peau.

## Dans Godot

- `HorseVisual` charge `generated/chevaux/cheval_sahara/cheval_sahara.glb` (`data/horse/horse.json › model`) : échelle 1 (le modèle est en mètres, `height_m` = 2,503 m au bout des oreilles), tourné de 90° (le modèle regarde vers +X, Godot vers −Z). Sans section `coat`, le modèle garde ses textures (la robe peinte par shader de la première version n'est plus utilisée).
- `HorseGround` remplace la heightfield de la première version : hauteur et normale lues dans Terrain3D, surface sonore d'après la carte de contrôle (sable, terre, galets, pierre), pas d'eau dans le Sahara.
- La scène du Sahara crée un seul `FootstepSystem` (nœud « Pas ») et le système de monte (nœud « Monte ») ; elle répond à `surface_at()` pour les pas sur le terrain.
- Vitesses de référence des animations (`horse.json › animations`) : celles de Barq × 1,25 (membres plus longs) ; à affiner si les sabots glissent.
- Point de selle : os « Torso » au repos (1,36 m) + 0,44 m vers le haut, 5 cm vers l'avant (`rider › seat_offset_m`).

## Mesure

Pendant la mesure du Sahara, le personnage est en selle dès le départ et le cheval suit le corps de test, piloté comme au clavier (`HorseMountSystem.simulate`) : pas, trot, galop, rattrapage s'il est distancé à 70 m/s. Son coût (physique, animations, sons, empreintes, cavalier) entre donc dans les budgets.

## Tests (Projet/tests/unit/)

- `test_horse_model.gd` : modèle préparé, squelette et cinq animations, tête vers −Z, hauteur, point de selle sur la selle, une surface sonore par sol.
- `test_horse_barq.gd`, `test_horse_mount_system.gd`, `test_horse_camera.gd` : repris de la première version (10 min de galop de course parmi 1 000 obstacles, 6 000 montes et descentes, cadrage indépendant de la fréquence d'image…).
- `test_horse_call.gd` : grille du sifflet sur le vrai Sahara (4 km) et chemin d'un coin à l'autre (640 ms dans un fil de travail sous Linux).
- `test_footsteps_*.gd` : 200 marcheurs simultanés, vrais sons chargés.
- `tests/support/avant_tests.gd` déclare les actions du jeu avant tous les tests, comme au démarrage.

## Essais faits avant la fusion

Sous Linux (conteneur, rendu logiciel) : validation complète (Blender par le module `bpy` 5.0.1, 209 tests GUT réussis), puis monte et galop filmés image par image : cavalier en selle, cheval au galop animé.

**Non essayé** : la validation Windows et la mesure sur Intel Arc (à faire par `valider.bat`), le son (machine sans carte son), la monte au clavier (E) et l'animation de montée du cavalier.

## Limites connues

- L'animation de montée du personnage a été réglée pour Barq (selle à 1,50 m) : sur ce cheval (selle à 1,78 m), le cavalier finit sa montée 28 cm trop bas, puis glisse en selle en 0,22 s.
- Trot : même animation que le pas (comme dans la première version), accélérée ; les sabots peuvent glisser au trot rapide.
- 109 000 triangles (dont 20 000 de crins) et des textures de 2048 au plus : à vérifier par la mesure.

## En cas de bug

| Symptôme | Où regarder |
|---|---|
| « Barq : modèle introuvable » | étape 2 de la validation, `rapports/<date>/cheval-*.log` |
| Jambe ou tête qui se tord | position des os (table `P` de `squelette.py`) ou poids (`assign_weights`) |
| Animations trop grandes ou trop petites | échelle `S` de `squelette.py` (translations des animations) |
| Cavalier au-dessus ou dans la selle | `horse.json › rider › seat_offset_m` |
| Sabots qui glissent | `horse.json › animations › reference_speed_mps` |
| Pas toujours sur le sable | `HorseGround.surface_at` (carte de contrôle de Terrain3D), `Sahara.surface_at` |
| Aucun son | `generated/sons/` (copie par `outils/construire.gd`), `SoundLibrary` |
