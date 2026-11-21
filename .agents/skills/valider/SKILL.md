---
name: valider
description: "Exécuter et diagnostiquer la validation complète du projet : qualité GDScript, ressources, C++, import, scènes, tests, mesures et captures. À utiliser après toute modification avant de rendre la main."
---

# Valider le projet

Utiliser le pipeline partagé :

- Windows : `powershell -NoProfile -ExecutionPolicy Bypass -File Scripts/Pipeline/valider.ps1`
- macOS : `pwsh -NoProfile -File Scripts/Pipeline/valider.ps1`

Options : `-SansRendu`, `-SansBudgets` uniquement hors machine cible, et `-Cartes sandbox,…`.

Corriger toute erreur puis relancer la chaîne complète. Une ligne Godot `ERROR:`, `SCRIPT ERROR:`, `USER ERROR:` ou `Parse Error:` est un échec même avec un code de sortie nul. Ne jamais masquer le message ni détendre un budget sans accord explicite.

Lire `Mesures/tests/tests.log`, `junit.xml` et les journaux concernés pour diagnostiquer. Lorsque des captures sont produites, les ouvrir et vérifier qu'elles ne sont ni noires, ni uniformes, ni magenta et que le résultat correspond à la demande.
