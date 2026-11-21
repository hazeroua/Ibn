---
name: nouvelle-fonctionnalite
description: Réaliser une fonctionnalité du MVP en cours, depuis le cadrage et la branche Git jusqu'aux tests, mesures, vérification indépendante et rapport final. À utiliser au début de toute tâche de développement du jeu.
---

# Réaliser une fonctionnalité

1. Lire `CLAUDE.md`, `Docs/01-vision-et-attentes.md`, la section du MVP courant dans `Docs/06-roadmap-mvp.md` et le réglage `ibn/projet/mvp_en_cours` de `Game/project.godot`.
2. Vérifier que la demande appartient au périmètre courant et travailler sur une branche dédiée sans écraser les changements locaux existants.
3. Écrire les pires cas avant le code : volumes maximaux, Intel Arc intégré, partie de 100 heures, galop en zone dense et systèmes simultanés.
4. Livrer la version définitive : données JSON, GDScript typé, C++ pour les chemins chauds, scènes complexes générées par constructeur, aucun raccourci provisoire.
5. Ajouter les tests fonctionnels et de charge pertinents. Mesurer les chemins critiques sans assouplir les budgets.
6. Utiliser le skill `valider`. Relire les captures lorsque la tâche touche au rendu.
7. Obtenir une revue indépendante du diff si les sous-agents sont disponibles ; ajouter une revue historique, artistique, gameplay ou performance lorsque le domaine l'exige.
8. Rendre compte en français simple : changements, pires cas, mesures, commande unique d'essai et ressources manuelles éventuelles.

Sous Windows, la commande d'essai est `lancer.bat`. Sous macOS Apple silicon, c'est `./lancer.command`.
