---
name: nouvelle-carte
description: Créer une zone, ville, région ou scène de test selon les conventions de données, constructeur, points de vue, budgets et tests du projet.
---

# Créer une carte

Pour `<carte>` en minuscules, chiffres et `_` :

- source de vérité : `Game/data/<carte>/<carte>.json` ;
- vues : `Game/data/<carte>/viewpoints.json` ;
- logique : `Game/world/<carte>/<carte>_builder.gd` ;
- entrée pipeline : `Game/tools/builders/build_<carte>.gd` ;
- scène générée et ignorée par Git : `Game/world/<carte>/<carte>.tscn` ;
- budgets : `Game/tests/perf/budgets/<carte>.json` ;
- tests : `Game/tests/unit/test_<carte>_builder.gd`.

Suivre `sandbox`. Partager maillages et matériaux, utiliser MultiMesh pour les répétitions, définir les budgets avant la construction et fournir au moins une vue générale, une vue au sol et une vue du pire cas. Tester la construction au volume maximal et valider avec `Scripts/Pipeline/valider.ps1 -Cartes <carte>`.
