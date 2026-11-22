# Direction artistique du Sahara (ticket #66)

Ce document fixe l'identité visuelle du premier jalon : lumière, ciel, brume sèche, vent, poussière et chaleur. Il complète la section « Direction artistique » de `03-game-design.md`. Les valeurs exactes sont dans `Projet/data/sahara/atmosphere.json` ; ce document en donne l'intention.

## Intention

Un désert **stylisé et peint**, pas photographique. La lumière y fait le travail : l'heure dorée, la poussière qui accroche le soleil, l'horizon qui tremble à midi. Les formes doivent rester lisibles à tout moment. Aucun effet ne doit cacher un repère, un relief ou un chemin.

## Références visuelles

| Référence | Ce qu'on en retient |
|---|---|
| Miniatures persanes d'Herat et de Tabriz | Couleurs franches, ciel clair et plat, horizon net, ocres et turquoises |
| *Journey* | Sable qui brille, poussière dans la lumière, sentiment d'étendue |
| *Sable* | Lisibilité des silhouettes, aplats de couleur, ombres franches |
| *The Legend of Zelda: Breath of the Wild* | Perspective aérienne : les lointains bleuissent et se décolorent |
| *Ghost of Tsushima* | Le vent comme guide, poussière et particules qui donnent la direction |

Aucune image de ces œuvres n'est copiée dans le projet. Elles servent seulement de repères d'intention.

## Palette

| Rôle | Couleur (moyenne de texture × teinte de la carte) | Utilisation |
|---|---|---|
| Sable des dunes | `#9A7352` (moyenne de la texture) × teinte `#FFEAD2` | Erg, dune étoilée |
| Reg | `#A5956F` × teinte `#FFE9D2` | Plaines tassées |
| Terre des oueds | `#8F7761` × `#E9DFD2` | Lits craquelés |
| Roche | `#653E2E` × `#EAD9C8` | Gara, crête, pitons |
| Ciel de jour | `#BCD6EC` à `#D2E4F2` | Teinte atmosphérique |
| Horizon chaud | `#FFA775` à `#FFCFAA` | Matin et fin de journée |
| Poussière | `#F6E6D0` à `#FFCF9E` | Selon l'heure |

Règle : les couleurs saturées sont réservées à la lumière (soleil bas, horizon, poussière éclairée). Les sols restent dans une gamme d'ocres resserrée, pour que les repères rocheux rouges ressortent.

## Les trois moments

| Moment | Heure | Soleil | Ambiance | Poussière | Chaleur |
|---|---:|---|---|---|---|
| Matin | 7 h 45 | Bas à l'est (environ 20°), lumière dorée douce | Ciel pâle, horizon pêche, cirrus | Faible (30 %) | Aucune |
| Midi | 13 h | Haut (environ 66°), lumière blanche et dure | Ciel le plus bleu, contraste fort, couleurs légèrement désaturées | Moyenne (55 %) | Forte au lointain, près de l'horizon |
| Fin de journée | 17 h 45 | Bas à l'ouest (environ 8°), lumière orangée | Horizon orange, ombres longues, saturation renforcée | Forte (100 %), poussière orangée | Légère |

Le moment par défaut est la fin de journée, qui montre le mieux l'identité visuelle. En jeu, la touche **T** (bouton Y de la manette) passe d'un moment à l'autre.

Lieu et date du calcul solaire : 33° N, 8° E (sud de l'actuelle Tunisie), 15 avril 1352, fuseau UTC+1.

## Effets et lisibilité

- **Ciel et soleil** : Sky3D (Tokisan Games), à heure fixe. Nuages cumulus et cirrus légers, poussés par le même vent que les dunes (nord-est, 6 m/s).
- **Brume sèche** : brouillard de profondeur de Godot avec perspective aérienne, teinté par moment (beige clair le matin et à midi, orangé en fin de journée). Elle commence à 220–300 m, ne dépasse jamais 45 % d'opacité et ne masque donc jamais le premier plan. Les massifs restent identifiables à 3 km.
- **Poussière** : trois couches de particules qui suivent la caméra et sont portées par le vent. Elles disparaissent en fondu près de la caméra (aucun voile collé à l'écran) et au loin.
  - voiles : grands nuages légers, 96 au plus, opacité 14 % ;
  - grains : grains soulevés au ras du sol, 220 au plus ;
  - poussière fine : poussière fine en suspension dans la lumière, 400 au plus.
- **Chaleur** : l'image tremble seulement au-delà de 180 m et dans une bande autour de l'horizon. Elle est désactivée le matin, ce qui supprime aussi son coût.
- **Étalonnage** : saturation et contraste par moment, appliqués à toute l'image.

## Captures comparables

La mesure automatique (`Projet/valider.bat`) photographie chaque moment depuis les cinq mêmes points de vue : vue générale, erg au sol, oued, gara, reg vers les pitons. Elle compose aussi une planche comparative `planche_moments.png`, avec une ligne par moment et une colonne par point de vue. Le temps d'image de chaque prise est chronométré, et la plus coûteuse est comparée au budget (`worst_viewpoint_frame_ms`).

## Ressources utilisées

Voir `Docs/credits.md`.
