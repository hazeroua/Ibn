# Cheval Sahara — itération visuelle 2

## Direction retenue

La planche fournie le 22 novembre 2026 par le porteur du projet fait référence :
sols rugueux ocre/rouille, ciel bleu franc, silhouettes lisibles et contrastes évoluant
avec l'heure. Les documents récents `direction-artistique-sahara.md` et
`direction-artistique-sahara-game-design.md` du checkout reboot-main précisent que
la stylisation vient de la palette et de la lumière, sans imposer une anatomie cartoon.

Le cheval reçoit une robe baie sombre, des membres inférieurs noirs, une crinière
et une queue sombres, du cuir brun et un tapis écru bordé de terre rouge. Le choix
de silhouette vise un cheval de voyage athlétique. Aucune race ni authenticité
historique du harnachement n'est revendiquée.

## Réalisation

Source indépendante : `Scripts/Blender/cheval_sahara.py` (devenu `Projet/outils/blender/cheval/forme.py`). Surfaces construites par
sections pour le thorax, l'encolure, la tête, les jambes et les sabots. Union de la
peau, naseaux évidés, lèvres et paupières, sabots plats, crins effilés, tapis drapé,
selle structurée et rênes. Pigmentation de la robe conservée dans les couleurs
de sommets du GLB. Aucun modèle tiers ni asset de l'ancien Barq importé.

Résultats locaux : `Mesures/cheval-sahara-v2/` : Blender éditable, GLB, vues matin,
midi, soir et profil, et compte exact des triangles après conversion des courbes.
Le décor des rendus est un banc d'essai Blender inspiré de la palette du jeu,
pas le terrain Godot ni une capture prouvant l'intégration.

## Limites vérifiables

Cette itération traite l'apparence. Rig, animations, LOD et intégration dans le jeu
restent absents ; le ticket 106 reste ouvert. Le grain procédural des matériaux
est visible dans Blender mais n'est pas converti en textures dans le GLB.
Les couleurs de sommets et les valeurs PBR uniformes sont exportées.
Les budgets Intel Arc et les déformations en mouvement ne sont pas validés.

Le pire cas futur comprend un cheval proche, plusieurs cavaliers distants, un
galop en zone dense et une partie longue. Les images fixes ne valident aucun de
ces scénarios. Ne pas intégrer cet export comme asset de production validé.

## Reproduction

Depuis la racine du dépôt, dans PowerShell :

    & 'C:\Program Files\Blender Foundation\Blender 5.3\blender.exe' --background --factory-startup --python-exit-code 1 --python Scripts/Blender/cheval_sahara.py

Les fichiers de la première étude restent conservés séparément.
