---
name: godot-gdscript
description: Modifier Godot 4.7, le GDScript typé, les scènes générées ou les réglages du projet en respectant les conventions d'import, de construction et de test du dépôt.
---

# Godot et GDScript

- La version est figée dans `Tools/versions.json`; les chemins locaux viennent de `Tools/outils.json`.
- Le projet est dans `Game/`. Les scènes complexes sont construites par les scripts `Game/tools/builders/`, jamais éditées manuellement.
- Passer par `Scripts/Pipeline/*.ps1` pour importer, construire, tester et lancer. Sous macOS, utiliser `pwsh`; sous Windows, `powershell`.
- Taper statiquement variables, paramètres, retours et variables de boucle. Les textes joueur sont en français traduisible ; les noms de code sont en anglais.
- Éviter `_process` sans nécessité et toute allocation ou recherche linéaire par image dans les systèmes nombreux.
- Une classe `class_name` exige un import avant un constructeur. Un script `--script` étend `SceneTree` et appelle `quit(code)`.
- Avant `PackedScene.pack`, donner `owner = racine` à chaque nœud à enregistrer.
- Versionner les `.uid` créés à côté des scripts.
