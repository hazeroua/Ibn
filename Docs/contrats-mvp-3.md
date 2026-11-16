# Contrats du MVP 3 — Barq

La feuille de route ne contient pas d'issues MVP3 séparées dans ce dépôt. Les tickets de cette branche sont donc les sept livrables de `Docs/06-roadmap-mvp.md` :

1. monter et descendre avec une caméra de monte ;
2. pas, trot, galop et sprint avec endurance ;
3. suivi du relief, évitement des obstacles et refus des chutes dangereuses ;
4. sifflet d'appel depuis la position courante du cheval ;
5. caméra plus large et dynamique au galop ;
6. sabots et souffle, avec surface de sol ;
7. traces de sabots bornées dans le sable.

## Pires cas et budgets

- 36 000 ticks physiques pour 10 minutes de sprint à 60 i/s, avec l'endurance bornée dans `[0, 100]`.
- 1 000 obstacles de collision autour de Barq : une seule requête de balayage par tick, aucune liste d'obstacles en mémoire par image.
- Relief très accidenté : échantillon à 7 m, pente maximale 34 degrés, chute refusée au-delà de 1,15 m.
- Appel depuis 4 km : trajectoire à allure trot, arrêt à 2,6 m, sans téléportation.
- 128 traces maximum, réutilisées en anneau ; aucun nœud créé à l'émission d'une trace.

## Ressource équine

Le dépôt ne contient pas de cheval animé libre figé dans `Game/assets`. Le système reste jouable avec une silhouette procédurale recréable afin de valider la locomotion et les collisions. Une ressource équine CC0 doit être ajoutée avant de considérer la qualité visuelle du livrable comme validée ; elle ne doit pas être téléchargée silencieusement ni inventée dans le manifeste.

## Corrections du 16 novembre (retours du porteur du projet)

- **Taille, robe et sens de Barq** : le modèle est ramené à 2,2 m (tête haute) et tourné vers l'avant de Godot. Il marchait à reculons parce que le modèle regarde vers +Z. Il reçoit une robe baie : corps brun-roux, crins et bas des jambes noirs (`horse_coat.gdshader`). Le modèle source n'a ni texture ni couleurs de sommets, d'où le blanc. Son tronc est aminci (`width_scale`) pour que les jambes du cavalier restent visibles. Tout est réglé dans `horse.json > model`.
- **Animations de Barq** : arrêt, pas, galop et saut, en boucle. Leur vitesse de lecture suit la vitesse au sol, mesurée sur les sabots, pour que les sabots ne glissent pas (`horse.json > animations`). Pesanteur réelle et saut monté (`horse.json > jump`).
- **Animations du cavalier**, ajoutées au contrat « locomotion » (`characters.json`), toutes générées par `preparer_personnage.py` à partir de la bibliothèque CC0 Quaternius :
  - `ride_idle` : assise ;
  - `ride_gallop` : buste en avant aux allures rapides et pendant le saut ;
  - `mount` : montée par la gauche, pied à l'étrier puis jambe passée par-dessus ;
  - `dismount` : descente ;
  - `jump_start`, `jump_air`, `jump_land` : saut à pied.
- **Nouvelles recettes de génération** : `clip`, `pose_loop`, `loop_no_rise` et `sequence`. Retouches possibles : rotations d'os, ancrage du bassin et jambes posées par cinématique inverse de part et d'autre du cheval.
- **Monte** : approche, montée, conduite, saut et descente.
  - Le bassin du cavalier suit l'os du dos de Barq : le cavalier bouge avec le cheval.
  - Une demande de descente au galop arrête d'abord Barq.
- **Saut à pied** : barre d'espace ou bouton A. Il reste possible un court instant après avoir quitté le sol, et un appui juste avant l'atterrissage est gardé. L'atterrissage est animé.
- **Commandes** : monter et descendre avec E ou le bouton X, siffler avec H ou le bouton Y, sauter avec Espace ou le bouton A.
- **Contrainte de nommage** : l'importeur de Godot retire le suffixe `_loop` des noms d'animation. Aucune animation du contrat ne doit donc finir par `_loop`.
- **`desert.tscn` n'est plus versionné** : il est reconstruit à chaque lancement et bloquait `git pull`.

Reste à faire :
- les tests GUT de la monte et du saut ;
- les virages et le cabrage de Barq : le modèle n'a pas ces animations ;
- les rênes ;
- une mesure sur la puce Intel Arc.
