---
name: godot-gdscript
description: Conventions Godot 4.7 et GDScript typé du reboot Terrain3D. Avant #63, ne travaille que dans le prototype de validation ; après #63, suit la structure documentée du nouveau socle.
---
# Godot et GDScript dans ce projet

## Version et chemins
- Godot **figé** (`Tools/versions.json`, chemins dans `Tools/outils.json`). Ne jamais changer de version sans décision explicite.
- Avant la fermeture de #63, le seul projet actif est `Reboot/Terrain3DValidation/`.
- `Game/` est l'ancien projet : ne pas y ajouter de code pour le reboot.
- Ne jamais lancer l'éditeur pour modifier manuellement une scène : tout doit rester reproductible par texte, données ou script.

## Commandes actives pour #62

Utiliser `run-validation.ps1` sous Vulkan et D3D12, conformément à la skill `valider`. Le ticket #63 devra documenter les commandes définitives d'import, de test, de construction et de lancement avant tout nouveau développement GDScript.

## Règles de code
- **Typage statique partout** (`untyped_declaration` est une erreur) : variables, paramètres, retours, variables de boucle (`for x: int in …`). `:=` est accepté.
- Les données et leur chargeur seront définis par #63 ; ne pas reprendre automatiquement le chargeur de l'ancien projet.
- Pas de `_process` sans nécessité ; jamais d'allocation ni de recherche linéaire par image dans les systèmes nombreux (→ C++).
- Formatage : `python -m gdtoolkit.formatter --line-length 140` ; analyse : `python -m gdtoolkit.linter` (le Python des outils est dans `Tools/outils.json` → `scons.python`).
- Textes affichés au joueur en français et traduisibles ; noms de code en anglais.

## Pièges connus
- Un script lancé par `--script` doit étendre `SceneTree` et terminer par `quit(code)` ; les classes `class_name` ne sont connues qu'après un import Godot.
- `Node3D.global_transform` exige un nœud dans l'arbre : dans un constructeur, utiliser `transform`.
- Avant `PackedScene.pack(racine)`, chaque nœud doit avoir `owner = racine`, sinon il n'est pas enregistré.
- Une ligne `ERROR:` est un échec, même si Godot rend le code 0 : corriger la cause.
- Godot crée des fichiers `.uid` à côté des scripts : ils se versionnent avec le script.
