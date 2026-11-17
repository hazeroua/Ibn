# Profil de rendu Intel Arc 140V

Référence mesurée le 17 novembre 2026 sur Intel Core Ultra 7 258V, Intel Arc 140V intégrée et affichage 1920 × 1080.

## Profil normal retenu

- Moteur Forward+ et FSR 2 à 67 %.
- Ombre directionnelle à deux cascades, portée maximale de 150 m.
- Ombres des petites plantes désactivées ; ombres des arbres limitées aux variantes simplifiées.
- Variantes de matériaux opaques sans `discard` hors transition de LOD.
- Palmeraie : trois lectures de texture par fragment pour la terre (contre neuf auparavant) et une pour les cultures (contre deux).
- Streaming : construction asynchrone, anticipation par la vitesse du porteur et intégration étalée sous 2 ms.

Mesure `desert_jeu`, 30 s, 4 669 images : 155,65 i/s de moyenne, 92,77 i/s au 1 % le plus lent, image p99 9,76 ms, GPU p99 8,66 ms, 138 appels de rendu au maximum, 1 101 642 primitives au maximum et 271,14 Mio de mémoire vidéo au maximum. Tous les budgets stricts de `desert_jeu.json` sont respectés.

## Profil minimal documenté

À utiliser seulement si une machine plus faible ne tient pas le budget strict : conserver Forward+ et FSR 2, réduire la portée des ombres à 100 m, garder deux cascades, désactiver les ombres des arbustes et limiter les reflets de l'eau. Ne pas diminuer la densité historique ni supprimer des objets de jeu : les LOD et les distances de visibilité restent le levier principal.

## Reproduction

```powershell
Scripts/Pipeline/mesurer.ps1 -Carte desert_jeu
Scripts/Pipeline/mesurer.ps1 -Carte desert_jeu -Parcours joueur
Scripts/Pipeline/mesurer.ps1 -Carte desert_jeu -Parcours res://data/desert_jeu/route_barq.json
```

Les captures avant/après du shader de palmeraie sont produites par `Scripts/Pipeline/capturer.ps1 -Carte desert_jeu`. La luminance moyenne de `vue_palmeraie_parcelles` reste à 0,4456 avant et après ; aucune erreur magenta n'est présente.
