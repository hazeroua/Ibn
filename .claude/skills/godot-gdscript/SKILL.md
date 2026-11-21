---
name: godot-gdscript
description: Conventions Godot 4.7 et GDScript typé du reboot Terrain3D. Le projet actif est `Projet/`.
---
# Godot et GDScript dans ce projet

## Version et chemins
- Godot **figé** (`Tools/versions.json`, chemins dans `Tools/outils.json`). Ne jamais changer de version sans décision explicite.
- Le projet actif est `Projet/` (structure dans `Projet/README.md`).
- `Game/` est l'ancien projet : ne pas y ajouter de code pour le reboot.
- Ne jamais lancer l'éditeur pour modifier manuellement une scène : tout doit rester reproductible par texte, données ou script.

## Commandes

Tout passe par `Projet/valider.bat` (skill `valider`). Le jeu démarre sur `core/boot/boot.tscn`, qui lit `data/config/` puis ouvre la scène du catalogue `data/config/boot.json` (`-- --scene=<id>`).

## Règles de code
- **Typage statique partout** (`untyped_declaration` est une erreur) : variables, paramètres, retours, variables de boucle (`for x: int in …`). `:=` est accepté.
- Données : JSON dans `Projet/data/`, lues avec `JsonData` (`core/data/json_data.gd`) et validées à la lecture (erreurs explicites, jamais de valeur par défaut silencieuse).
- Journal : `GameLog.info/warning/error(catégorie, message)` ; `GameLog.error` fait échouer la validation.
- Pas de `_process` sans nécessité ; jamais d'allocation ni de recherche linéaire par image dans les systèmes nombreux (→ C++).
- Formatage : `python -m gdtoolkit.formatter --line-length 140` ; analyse : `python -m gdtoolkit.linter` (le Python des outils est dans `Tools/outils.json` → `scons.python`).
- Textes affichés au joueur en français et traduisibles ; noms de code en anglais.

## Pièges connus
- Un script lancé par `--script` doit étendre `SceneTree` et terminer par `quit(code)` ; les classes `class_name` ne sont connues qu'après un import Godot.
- `Node3D.global_transform` exige un nœud dans l'arbre : dans un constructeur, utiliser `transform`.
- Avant `PackedScene.pack(racine)`, chaque nœud doit avoir `owner = racine`, sinon il n'est pas enregistré.
- Une ligne `ERROR:` est un échec, même si Godot rend le code 0 : corriger la cause.
- Godot crée des fichiers `.uid` à côté des scripts : ils se versionnent avec le script.
