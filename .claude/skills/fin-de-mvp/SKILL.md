---
name: fin-de-mvp
description: Clôture d'un MVP - vérification de tous les critères de fin, journal, captures comparatives, vidéo, fusion, passage au MVP suivant et proposition des tickets du jalon suivant. À utiliser quand toutes les fonctionnalités d'un MVP sont faites.
disable-model-invocation: true
---
# Clôturer le MVP en cours

1. Relire la section du MVP dans `Docs/06-roadmap-mvp.md` : chaque livrable coché doit être réellement fait et vérifiable.
2. Lancer la skill `valider` sur la machine de développement (budgets vérifiés) ; puis `Scripts/Pipeline/video.ps1` pour chaque carte.
3. Faire passer l'agent `verificateur` sur l'ensemble du MVP : verdict ACCEPTÉ obligatoire.
4. Dérouler le **critère « Terminé quand »** du MVP et le décrire précisément.
5. Remplir la ligne du MVP dans le **Journal** de `Docs/06-roadmap-mvp.md` : date, mesures du pire cas (images par seconde, millisecondes par image), mémoire, difficultés, décisions.
6. Comparer les captures avec celles du MVP précédent (mêmes points de vue) et le résumer.
7. Ouvrir la demande de fusion de la branche du MVP vers `main`, avec le résumé, les mesures et les captures.
8. Après fusion : passer `ibn/projet/mvp_en_cours` au MVP suivant dans `Game/project.godot`.
9. Proposer au porteur du projet les tickets du MVP suivant (un ticket par livrable, avec tâches à cocher, pires cas et critères d'acceptation), et ne les créer qu'après son accord.
