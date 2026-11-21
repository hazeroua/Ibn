---
name: fin-de-mvp
description: Clôture un jalon du reboot après vérification de tous ses tickets, mesures, captures, export et décision de passage au jalon suivant.
disable-model-invocation: true
---
# Clôturer un jalon du reboot

1. Relire `Docs/06-roadmap-mvp.md` et vérifier chaque critère du jalon.
2. Lancer la skill `valider` sur la machine de développement avec les budgets actifs.
3. Faire passer l'agent `verificateur` sur l'ensemble du jalon : verdict ACCEPTÉ obligatoire.
4. Comparer les captures, rapports et exports du pire cas.
5. Mettre à jour la roadmap avec la date, les mesures, les difficultés et la décision.
6. Fusionner la branche vers `main` avec le résumé et les preuves.
7. Proposer les tickets du jalon suivant et ne les créer qu'après accord du porteur du projet.
