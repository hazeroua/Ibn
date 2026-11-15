---
name: nouvelle-carte
description: Crée une nouvelle carte (scène générée par script) selon les conventions du projet, avec ses données, son constructeur, ses points de vue, ses budgets et ses tests. À utiliser quand une tâche demande une nouvelle zone, ville, région ou scène de test.
---
# Créer une carte `<carte>`

Nom en minuscules, chiffres et `_` (ex. `tunis_medina`). Les scripts du pipeline trouvent tout par convention :

| Élément | Chemin |
|---|---|
| Données (source de vérité) | `Game/data/<carte>/<carte>.json` |
| Points de vue (captures, parcours de mesure et vidéo) | `Game/data/<carte>/viewpoints.json` |
| Logique de construction | `Game/world/<carte>/<carte>_builder.gd` (classe `…Builder`, méthode statique `build(data) -> Node3D`) |
| Script lancé par le pipeline | `Game/tools/builders/build_<carte>.gd` (`extends SceneTree`, enregistre la scène, `quit(code)`) |
| Scène produite (non versionnée, jamais éditée) | `Game/world/<carte>/<carte>.tscn` → ajouter au `.gitignore` |
| Budgets de performance | `Game/tests/perf/budgets/<carte>.json` |
| Tests | `Game/tests/unit/test_<carte>_builder.gd` |

Modèle à suivre : la carte `sandbox` (`SandboxBuilder`, `build_sandbox.gd`, `data/sandbox/`).

## Règles
- Ressources partagées : un maillage par forme et taille, un matériau par apparence ; répétitions en `MultiMeshInstance3D`.
- Tous les nœuds reçoivent `owner = racine` avant l'empaquetage.
- Au moins 3 points de vue : vue générale, vue au sol, vue du pire cas (zone la plus dense).
- Budgets fixés **avant** de construire, avec l'agent `garant-performance`.
- Test de charge : construire la carte avec le volume maximal prévu et vérifier le partage des ressources et le temps de construction.
- Valider avec la skill `valider -Cartes <carte>`.
