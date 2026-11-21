---
name: nouvelle-carte
description: Crée une nouvelle carte dans `Projet/`, avec données, génération, points de vue, budgets et tests.
---
# Créer une carte `<carte>`

Emplacements : scène et script dans `Projet/world/<carte>/`, données dans `Projet/data/<carte>/`, budget dans `Projet/data/budgets/<carte>.json`, entrée dans le catalogue `Projet/data/config/boot.json`, tests dans `Projet/tests/unit/`. Modèle : `world/terrain_test/`. Ne jamais reprendre les chemins de l'ancien dossier `Game/`.

Nom en minuscules, chiffres et `_`. La carte doit posséder des données sources, un générateur déterministe, au moins trois points de vue, un budget et des tests.

## Règles
- Ressources partagées : un maillage par forme et taille, un matériau par apparence ; répétitions en `MultiMeshInstance3D`.
- Tous les nœuds reçoivent `owner = racine` avant l'empaquetage.
- Au moins 3 points de vue : vue générale, vue au sol, vue du pire cas (zone la plus dense).
- Budgets fixés **avant** de construire, avec l'agent `garant-performance`.
- Test de charge : construire la carte avec le volume maximal prévu et vérifier le partage des ressources et le temps de construction.
- Valider avec la skill `valider` et la commande unique du nouveau socle.
