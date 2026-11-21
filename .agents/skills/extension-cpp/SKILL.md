---
name: extension-cpp
description: Écrire ou modifier la GDExtension C++ du jeu avec godot-cpp, avertissements stricts, mémoire bornée, compilation Windows et macOS et tests GUT. À utiliser pour les chemins critiques en performance.
---

# Extension C++

- Sources dans `Extensions/src/`; compilation par `Scripts/Pipeline/compiler.ps1`; bibliothèques déclarées dans `Game/bin/ibn.gdextension`.
- Compiler debug et release sur la plateforme touchée. Conserver les entrées Windows lors d'une adaptation macOS et réciproquement.
- Utiliser `IBN_GDCLASS`, lier les méthodes dans `_bind_methods()` et enregistrer la classe dans `register_types.cpp`.
- Traiter les avertissements comme des erreurs : `/W4 /WX` avec MSVC et `-Wall -Wextra -Wpedantic -Wshadow -Wconversion -Werror` avec Clang/GCC.
- Réserver les buffers à l'initialisation ; aucune allocation dans un chemin par image. Préférer les données contiguës et borner les capacités.
- Ajouter des tests GUT de présence, de calcul et de charge du pire cas.

Commandes : `powershell ... compiler.ps1` sous Windows, `pwsh -NoProfile -File Scripts/Pipeline/compiler.ps1` sous macOS.
