---
name: extension-cpp
description: Prépare une GDExtension C++ seulement après que #63 a défini le nouveau socle et qu'un profilage a prouvé le besoin. Ne réutilise jamais automatiquement l'ancienne extension.
---
# Extension C++ (GDExtension)

## Porte d'entrée

- Avant #63 : ne créer ni modifier aucune extension pour le reboot.
- Après #63 : utiliser uniquement les chemins, commandes de compilation et tests inscrits dans `Docs/05-technologies.md`.
- L'ancienne extension est consultable, mais aucune classe ni macro ne doit être copiée sans revue et mesure explicites.
- La version de godot-cpp reste figée dans `Tools/versions.json` jusqu'à une décision contraire.

## Ajouter une classe après #63

1. Démontrer par profilage que GDScript ne respecte pas le budget.
2. Définir l'API, les capacités maximales et les pires cas avant le code.
3. Lier et enregistrer la classe avec les mécanismes standards de godot-cpp retenus par le nouveau socle.
4. Ajouter tests fonctionnels et test de charge dans la structure du nouveau projet.

## Règles
- Avertissements au maximum et traités comme des erreurs (`/W4 /WX`, `-Wall -Wextra -Wpedantic -Wshadow -Wconversion -Werror`) : conversions explicites (`static_cast`), paramètres inutilisés marqués `(void)`.
- **Aucune allocation dans un chemin par image** : réserver à l'initialisation (`reserve`), réutiliser des tampons, refuser proprement quand la capacité est atteinte.
- Données contiguës (`std::vector`, structures de tableaux), algorithmes choisis pour leur complexité dans le pire cas.
- Valeurs d'entrée validées (`ERR_FAIL_COND_V_MSG` pour les erreurs de programmation, retour `false` pour les refus attendus).
- Commentaires en français, noms en anglais.
