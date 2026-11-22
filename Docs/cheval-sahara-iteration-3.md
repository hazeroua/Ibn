# Cheval Sahara — itération 3 : textures (ticket #106)

## Demande

Retour du porteur du projet sur l'itération 2 : « le cheval est encore lisse, il n'y a aucune texture ; c'est le travail sur lequel tu dois te concentrer ». Cette itération ne touche pas à la forme du cheval (celle de l'itération 2) : elle lui donne de vraies textures, cuites dans des images et exportées dans le GLB.

## Ce qui a été fait

Script : `Projet/outils/blender/cheval/textures.py` (d'abord écrit sous `Scripts/Blender/cheval_sahara_textures.py`). Il ouvre le fichier Blender de la forme (`forme.blend`, écrit par `forme.py`), regroupe les pièces par matière, les déplie (UV automatiques), calcule chaque matière avec des nœuds procéduraux, puis **cuit** le résultat en trois images par matière : couleur, rugosité, normales. Les matériaux finaux n'utilisent plus que ces images : ce sont elles qui partent dans le GLB et qu'un moteur de jeu peut lire.

| Pièce | Texture | Taille |
|---|---|---|
| Robe | poil couché dans le sens du corps (vers l'arrière) et vers le bas sur les jambes ; reflets allongés du poil ; pommelures discrètes ; dos plus sombre, ventre plus clair ; bas des jambes, bout du nez et bord des oreilles noirs (baie) ; creux assombris et reliefs éclaircis | 2048 × 2048 |
| Relief musculaire (normales de la robe) | épaule, triceps, poitrail, avant-bras, sillon jugulaire, crête et muscles de l'encolure, fessier, biceps fémoral et son sillon, grasset, jambe, creux du flanc, côtes, joues ; fines veines au chanfrein et au bas des membres. Sculptés par champs ellipsoïdaux sur une copie de la peau, puis cuits en carte de normales | (dans la carte de normales) |
| Crins | mèches sombres, reflets bruns aux pointes, peu brillants | 1024 |
| Sabots | corne striée verticalement, plus sombre à la couronne | 512 |
| Cuir (selle, quartiers, bride, rênes, sangle) | grain du cuir, patine, rayures, arêtes usées plus claires, creux assombris | 1024 |
| Tapis | laine tissée (trame et chaîne visibles), bandes écru, terre rouge, indigo passé et ocre, salissures | 1024 |
| Galon | tissage en diagonale, terre rouge | 512 |
| Fer (étriers, mors) | fer bruni piqué de rouille | 512 |

Couleurs et lumière suivent `Docs/direction-artistique-sahara.md` : robe baie sombre, ocres et terre rouge reprises dans le tapis, indigo très passé en seul contrepoint froid.

## Résultats

Dossier `Mesures/cheval-sahara-v3/` :

- `cheval-sahara.glb` : modèle avec ses 21 textures intégrées (18 Mo) ;
- `textures/` : les 21 images PNG (15 Mo) ;
- `cheval-sahara.blend` : fichier Blender avec les matériaux texturés ;
- rendus `midi.png`, `soir.png`, `profil.png`, `gros-plan-tete.png`, `gros-plan-selle.png` (même banc d'essai que l'itération 2 : sol et ciel Blender, pas le jeu) ;
- `etat.json` : triangles par pièce (109 146 au total, inchangé), liste des textures, durée.

Durée : environ 13 minutes sur 2 cœurs, dont 3 minutes de cuisson et 10 minutes de rendus.

## Défauts encore visibles

- **Forme** : inchangée depuis l'itération 2. Le corps reste un assemblage de volumes lissés ; les textures donnent du poil et du relief, mais ne remplacent pas une vraie sculpture anatomique (tête trop tubulaire, jambes trop régulières, articulations peu marquées).
- **Coude antérieur** : un pli sombre déchiré est visible à la jonction de l'avant-bras et du corps. Il vient de la géométrie de l'itération 2 (union des volumes par remaillage), pas des textures ; il était déjà présent en plus discret.
- **Crins** : les mèches sont des tubes ; même assombries et matées, elles restent raides et un peu grises en lumière rasante.
- **Œil** : sans iris ni reflet humide détaillé.
- **Jeu** : depuis, le cheval est monté dans le jeu avec un squelette et des animations (`Docs/cheval-jouable.md`).

## Reproduction

`Projet/valider.bat` refait tout (voir `Docs/cheval-jouable.md`). À la main, avec les rendus de contrôle :

    blender -b --factory-startup --python-exit-code 1 --python Projet/outils/blender/cheval/forme.py -- --sortie <dossier> --rendus
    blender -b --factory-startup --python-exit-code 1 --python Projet/outils/blender/cheval/textures.py -- --entree <dossier>/forme.blend --sortie <dossier> --rendus

Essayé avec Blender 5.0.1 (module `bpy`).

## Pistes pour la suite

1. Reprendre la forme par sculpture (tête, jambes, articulations, coude) : c'est maintenant ce qui limite le plus le rendu.
2. Remplacer les mèches en tubes par des cartes de crins (plans texturés avec transparence), plus souples et moins coûteuses.
3. Œil : iris, pupille horizontale, reflet.
4. Import dans Godot et mesure du coût des textures, puis squelette et animations.
