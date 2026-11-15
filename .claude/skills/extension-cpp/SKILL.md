---
name: extension-cpp
description: Écrire ou modifier l'extension C++ du jeu (GDExtension, godot-cpp) - enregistrement des classes, liaisons, avertissements stricts, mémoire sans allocation par image, tests GUT. À utiliser pour tout système critique en performance (foules, streaming du monde, génération procédurale, locomotion du cheval).
---
# Extension C++ (GDExtension)

## Structure
- Sources : `Extensions/src/` ; compilation : `Scripts/Pipeline/compiler.ps1` (SCons, debug et release) ; bibliothèques produites dans `Game/bin/` (déclarées dans `Game/bin/ibn.gdextension`).
- godot-cpp figé (branche de `Tools/versions.json`), compatibilité minimale 4.5, chargé par Godot 4.7.
- Modèle : `PerfRecorder` (`perf_recorder.h/.cpp`).

## Ajouter une classe
1. `class MaClasse : public godot::RefCounted` (ou `Node`…) avec `IBN_GDCLASS(MaClasse, godot::RefCounted)` (de `gdclass.h` : `GDCLASS` sans l'avertissement MSVC C4189 de la macro) et `static void _bind_methods();`.
2. Lier chaque méthode : `ClassDB::bind_method(D_METHOD("nom", "param"), &MaClasse::nom);`.
3. L'enregistrer dans `register_types.cpp` : `GDREGISTER_CLASS(MaClasse);`.
4. Tests GUT dans `Game/tests/unit/` : présence de la classe, calculs, **test de charge du pire cas** avec mesure du temps.

## Règles
- Avertissements au maximum et traités comme des erreurs (`/W4 /WX`, `-Wall -Wextra -Wpedantic -Wshadow -Wconversion -Werror`) : conversions explicites (`static_cast`), paramètres inutilisés marqués `(void)`.
- **Aucune allocation dans un chemin par image** : réserver à l'initialisation (`reserve`), réutiliser des tampons, refuser proprement quand la capacité est atteinte.
- Données contiguës (`std::vector`, structures de tableaux), algorithmes choisis pour leur complexité dans le pire cas.
- Valeurs d'entrée validées (`ERR_FAIL_COND_V_MSG` pour les erreurs de programmation, retour `false` pour les refus attendus).
- Commentaires en français, noms en anglais.
