---
name: nouvelle-carte
description: Crée une nouvelle carte dans le socle Terrain3D après le ticket #63, avec données, génération, points de vue, budgets et tests.
---
# Créer une carte `<carte>`

Cette skill ne doit pas être utilisée avant la fermeture de #63. Les chemins définitifs du nouveau socle doivent alors être inscrits dans `Docs/05-technologies.md`; ne jamais reprendre ceux de l'ancien dossier `Game/` par défaut.

Nom en minuscules, chiffres et `_`. La carte doit posséder des données sources, un générateur déterministe, au moins trois points de vue, un budget et des tests dans les emplacements définis par #63.

## Règles
- Ressources partagées : un maillage par forme et taille, un matériau par apparence ; répétitions en `MultiMeshInstance3D`.
- Tous les nœuds reçoivent `owner = racine` avant l'empaquetage.
- Au moins 3 points de vue : vue générale, vue au sol, vue du pire cas (zone la plus dense).
- Budgets fixés **avant** de construire, avec l'agent `garant-performance`.
- Test de charge : construire la carte avec le volume maximal prévu et vérifier le partage des ressources et le temps de construction.
- Valider avec la skill `valider` et la commande unique du nouveau socle.
