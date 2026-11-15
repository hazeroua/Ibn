---
name: godot-gdscript
description: Conventions, commandes et pièges de Godot 4.7 et du GDScript typé dans ce projet (exécution sans fenêtre, constructeurs de scènes, autoloads, tests GUT, erreurs fréquentes). À utiliser avant d'écrire ou de modifier du GDScript, une scène ou un réglage du projet.
---
# Godot et GDScript dans ce projet

## Version et chemins
- Godot **figé** (`Tools/versions.json`, chemins dans `Tools/outils.json`). Ne jamais changer de version sans décision explicite.
- Projet Godot : `Game/`. Ne jamais lancer l'éditeur pour modifier quoi que ce soit : tout est texte ou construit par script.

## Commandes (toujours via les scripts de `Scripts/Pipeline/`)
| Besoin | Script |
|---|---|
| Importer | `importer.ps1` (`--headless --import`) |
| Construire une scène | `construire.ps1 -Constructeur <nom>` (`--headless --script res://tools/builders/build_<nom>.gd`) |
| Tests | `tester.ps1` (GUT : `-s res://addons/gut/gut_cmdln.gd`) |
| Lancer le jeu | `lancer.bat` (ou `-Scene res://…`) |

## Règles de code
- **Typage statique partout** (`untyped_declaration` est une erreur) : variables, paramètres, retours, variables de boucle (`for x: int in …`). `:=` est accepté.
- Données lues avec `JsonData` (erreurs signalées par `push_error`, qui fait échouer le pipeline).
- Pas de `_process` sans nécessité ; jamais d'allocation ni de recherche linéaire par image dans les systèmes nombreux (→ C++).
- Formatage : `python -m gdtoolkit.formatter --line-length 140` ; analyse : `python -m gdtoolkit.linter` (le Python des outils est dans `Tools/outils.json` → `scons.python`).
- Textes affichés au joueur en français et traduisibles ; noms de code en anglais.

## Pièges connus
- Un script lancé par `--script` doit étendre `SceneTree` et terminer par `quit(code)` ; les classes `class_name` ne sont connues qu'après un import (`importer.ps1`).
- `Node3D.global_transform` exige un nœud dans l'arbre : dans un constructeur, utiliser `transform`.
- Avant `PackedScene.pack(racine)`, chaque nœud doit avoir `owner = racine`, sinon il n'est pas enregistré.
- Une ligne `ERROR:` est un échec, même si Godot rend le code 0 : corriger la cause.
- Godot crée des fichiers `.uid` à côté des scripts : ils se versionnent avec le script.
