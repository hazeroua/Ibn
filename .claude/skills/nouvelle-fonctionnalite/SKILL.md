---
name: nouvelle-fonctionnalite
description: Méthode obligatoire pour réaliser une fonctionnalité du MVP en cours, de la branche Git au rapport final (pires cas écrits, code définitif, test de charge, mesures, captures, vérification indépendante). À utiliser au début de toute tâche de développement.
---
# Réaliser une fonctionnalité

1. **Cadrer** : reformuler la tâche en une phrase ; vérifier qu'elle appartient au MVP en cours (`Docs/06-roadmap-mvp.md`, réglage `ibn/projet/mvp_en_cours` de `Game/project.godot`). Sinon, s'arrêter et le signaler.
2. **Brancher** : `git switch -c <mvp>-<fonctionnalite>` depuis la branche du MVP.
3. **Écrire les pires cas** en tête de la description de commit et dans le test de charge : nombres maximaux, puce intégrée, partie de 100 heures, galop en zone dense, tous systèmes actifs. Pour tout système par image ou à grand nombre d'objets, consulter l'agent `garant-performance`.
4. **Coder la version définitive** : données en JSON, GDScript typé, C++ pour les chemins chauds, aucun `TODO`/provisoire (un hook le bloque). Scènes complexes = constructeur dans `Game/tools/builders/` + données.
5. **Tester** : tests GUT dans `Game/tests/unit/` (logique et test de charge du pire cas, avec mesure imprimée par `gut.p`).
6. **Valider** : skill `valider` (chaîne complète, captures relues avec Read).
7. **Faire vérifier** : agent `verificateur` ; pour l'histoire, agent `historien` ; pour le visuel, agent `directeur-artistique`. Corriger tout point bloquant puis revalider.
8. **Committer** : un commit clair par fonctionnalité, terminé par les lignes d'attribution demandées.
9. **Rendre compte** au porteur du projet, en français simple :
   - ce qui a changé ;
   - les pires cas traités et leurs mesures ;
   - **la commande unique pour essayer** (ex. `lancer.bat`) ;
   - les ressources à télécharger, s'il y en a.
