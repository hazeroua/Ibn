---
name: nouvelle-mission
description: Conçoit et écrit une mission (principale, annexe, chaîne ou activité) en données JSON, en respectant « jouer d'abord, apprendre ensuite », le synopsis, la philosophie d'Ibn Khaldoun et la rigueur historique. À utiliser pour toute nouvelle mission ou dialogue (systèmes disponibles à partir du MVP 6).
---
# Écrire une mission

1. **Situer** : acte, lieu, année et place dans `Docs/08-synopsis.md` et `Docs/04-missions.md`.
2. **Concevoir** avec l'agent `concepteur-gameplay` : verbe fort, enjeu personnel, retournement, choix et conséquences (*'asabiyya*, Rachid), idée(s) servie(s) de `Docs/07-philosophie.md`.
3. **Écrire les données** au format de `Docs/05-technologies.md` (exemple de mission JSON) : objectifs typés, conséquences, déblocages, `statut_historique`.
4. **Pires cas de gameplay** : le joueur fuit, échoue, revient plus tard, sauvegarde et recharge à chaque étape, cumule toutes les missions annexes ouvertes.
5. **Faire relire** par l'agent `historien` (faits, statut, anachronismes, respect) : corriger tout point « à corriger ».
6. **Tester** : test GUT qui charge la mission, la joue étape par étape et vérifie conséquences et sauvegarde.
7. **Valider** (skill `valider`) et rendre compte avec la commande pour jouer la mission.
