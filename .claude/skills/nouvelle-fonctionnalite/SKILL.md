---
name: nouvelle-fonctionnalite
description: Méthode obligatoire pour réaliser un ticket du reboot Terrain3D, de la branche Git au rapport final (pires cas écrits, code définitif, test de charge, mesures, captures, vérification indépendante).
---
# Réaliser un ticket du reboot

1. **Cadrer** : reformuler la tâche en une phrase ; vérifier qu'elle correspond au premier ticket non bloqué de `Docs/06-roadmap-mvp.md`. Sinon, s'arrêter et le signaler.
2. **Brancher** : créer une branche `codex/<ticket>-<fonctionnalite>` depuis `main` dans un worktree propre.
3. **Écrire les pires cas** en tête de la description de commit et dans le test de charge : nombres maximaux, puce intégrée, partie de 100 heures, galop en zone dense, tous systèmes actifs. Pour tout système par image ou à grand nombre d'objets, consulter l'agent `garant-performance`.
4. **Coder la version définitive** : données versionnées, GDScript typé, C++ seulement pour les chemins chauds démontrés, aucun `TODO`/provisoire. Travailler exclusivement dans `Projet/` (structure : `Projet/README.md`).
5. **Tester** : tests GUT dans `Projet/tests/unit/`, budget dans `Projet/data/budgets/`, mesure par `Projet/valider.bat`.
6. **Valider** : skill `valider` (chaîne complète, captures relues avec Read).
7. **Faire vérifier** : agent `verificateur` ; pour l'histoire, agent `historien` ; pour le visuel, agent `directeur-artistique`. Corriger tout point bloquant puis revalider.
8. **Committer** : un commit clair par fonctionnalité, terminé par les lignes d'attribution demandées.
9. **Rendre compte** au porteur du projet, en français simple :
   - ce qui a changé ;
   - les pires cas traités et leurs mesures ;
   - **la commande unique du pipeline actif pour essayer** ;
   - les ressources à télécharger, s'il y en a.
