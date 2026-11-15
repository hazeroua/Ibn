---
name: valider
description: Lance la chaîne complète de vérification du projet (qualité du GDScript, ressources, compilation C++, import, construction des scènes, tests GUT, mesures, captures) et corrige jusqu'au vert. À utiliser avant de rendre la main, après toute modification.
---
# Valider le projet

## Commande
```
powershell -NoProfile -ExecutionPolicy Bypass -File Scripts/Pipeline/valider.ps1
```
Options : `-SansRendu` (machine sans affichage), `-SansBudgets` (hors machine de développement uniquement), `-Cartes sandbox,…`.

## Étapes et causes d'échec fréquentes
| Étape | Script | Échec typique | Correction |
|---|---|---|---|
| Qualité GDScript | gdlint / gdformat | ligne trop longue, ordre des déclarations | `python -m gdtoolkit.formatter --line-length 140 <fichier>` puis corriger le reste |
| Ressources | `importer-ressources.ps1` | MD5 incorrect, identifiant Poly Haven inconnu | vérifier `Game/data/assets/polyhaven.json` |
| C++ | `compiler.ps1` | avertissement traité comme erreur | corriger le code, jamais baisser le niveau d'avertissement |
| Import | `importer.ps1` | `ERROR:` dans la sortie | lire `Mesures/journaux/import.log` |
| Construction | `construire.ps1` | donnée manquante (`JsonData : clé … manquante`) | corriger le JSON de la carte |
| Tests | `tester.ps1` | test en échec | lire `Mesures/tests/tests.log` et `junit.xml` |
| Mesures | `mesurer.ps1` | `Budget dépassé : …` | consulter l'agent `garant-performance` |
| Captures | `capturer.ps1` | image noire ou rose | texture manquante ou lumière absente |

## Règles
- Toute ligne `ERROR:` ou `SCRIPT ERROR:` de Godot fait échouer le pipeline : on corrige la cause, on ne filtre pas le message.
- Après une correction, relancer **toute** la validation, pas seulement l'étape fautive.
- Les budgets ne se vérifient que sur la machine de développement ; ne jamais assouplir un budget pour faire passer une mesure sans l'accord explicite du porteur du projet.
- Terminer en ouvrant les captures produites avec Read pour vérifier l'image soi-même.
