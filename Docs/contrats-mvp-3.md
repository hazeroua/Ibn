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
