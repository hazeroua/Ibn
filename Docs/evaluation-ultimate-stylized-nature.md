# Évaluation — Ultimate Stylized Nature Pack

État au 21 novembre 2026. Cette évaluation répond au ticket [#77](https://github.com/hazeroua/Ibn/issues/77) et complète le MegaKit sans réintroduire ses doublons. La référence de game design est la traversée semi-aride décrite dans [direction-artistique-sahara-game-design.md](direction-artistique-sahara-game-design.md).

## Verdict

Le pack est **admis comme complément local** pour deux besoins précis : quatre silhouettes de palmiers adultes, une variante juvénile et un rocher sombre vertical. La composition normale utilise seulement `PalmTree_1`, `PalmTree_3` et un `Rock_4` agrandi ; les variantes penchées `PalmTree_2/4` restent disponibles pour le stress test, et `PalmTree_5` ne doit jamais servir de repère principal. Les arbres tempérés, fleurs, buissons et graminées du pack sont refusés ou redondants.

Les palmiers sont des **proxies génériques de dattier**, pas une preuve d'authenticité historique. Leur couronne lisible et leur verticalité répondent au rôle de navigation de l'oasis. La végétation de rive reste à produire ou à trouver.

## Provenance, licence et sécurité

| Champ | FBX | glTF/textures |
|---|---:|---:|
| Archive locale | `Ultimate_Stylized_Nature_FBX.zip` | `Ultimate_Stylized_Nature_glTF.zip` |
| Taille | 5 150 307 octets | 102 404 179 octets |
| SHA-256 | `3f696cc76f2e70277761e98abeb5552aa39c10a97d015fd65628fc8ab51d32e0` | `56315d74ae732ffdb988604c4464946db76da014912439a1e60eaa9a8e89033e` |
| Inventaire | 63 FBX | 93 entrées, dont 36 modèles glTF |
| Quarantaine | acceptée | acceptée |

Les fichiers proviennent du dossier Google Drive relié par la [fiche officielle Quaternius](https://quaternius.com/packs/ultimatestylizednature.html). La fiche affiche CC0 et la racine officielle contient `License.txt` (374 octets), mais les deux ZIP de formats ne l'embarquent pas. La politique conservatrice QAL reste donc appliquée : archives, FBX, textures, imports et dérivés restent sous `Import/` ou `Projet/assets_local/`, tous deux ignorés par Git.

Les contrôles ont déclaré 63 fichiers et 6 012 804 octets décompressés pour le FBX, sans script, exécutable, lien ni chemin traversant. Seuls dix FBX et quatre images ont été extraits. Godot 4.7.2 les a importés comme données ; aucun `.blend`, script du fournisseur ou programme tiers n'a été ouvert ou exécuté.

L'inspection géométrique est reproductible avec `res://outils/inspecter_assets_3d_locaux.gd`. Cet outil écrit par le projet charge uniquement les scènes déjà importées et relève surfaces, sommets, triangles, matériaux, animations et dimensions ; il n'évalue aucun code contenu dans les assets.

## Analyse des candidats

| Modèle | Triangles | Hauteur | Décision | Usage |
|---|---:|---:|---|---|
| `PalmTree_1` | 472 | 5,10 m | Adapter | palmier adulte principal, silhouette droite |
| `PalmTree_2` | 368 | 5,28 m | Adapter | variante adulte penchée, secondaire/stress |
| `PalmTree_3` | 344 | 4,67 m | Adapter | palmier adulte principal, couronne compacte |
| `PalmTree_4` | 472 | 3,65 m | Adapter | variante adulte penchée, secondaire/stress |
| `PalmTree_5` | 264 | 1,80 m | Adapter | jeune palmier uniquement |
| `Rock_4` | 456 | 2,15 m | Adapter | repère sombre lointain, agrandi 2,8–3,15× |
| `Rock_1/2` | 228 / 202 | env. 1,1 m | Refuser | doublons des rochers moyens déjà admis |
| `Rock_3/5` | 712 / 632 | 1,31 / 1,69 m | Refuser | coût supérieur sans gain de silhouette |

Chaque palmier possède deux surfaces, tronc et feuilles, sans animation. Le laboratoire remplace les matériaux par les textures officielles, active la normale du tronc, utilise l'alpha-scissor double face pour les feuilles et désature le vert. Les pivots sont compensés à la pose. Les palmiers sont regroupés par variante dans des MultiMesh ; le rocher lointain ne projette pas d'ombre et n'a pas de collision.

## Adaptation au game design et performances

La composition ajoute un bosquet de cinq palmiers à gauche de la route et un repère rocheux sombre à droite, tout en conservant un corridor central de 10 m. Elle combine 800 instances : 650 touffes, 120 galets, 24 rochers existants, cinq palmiers et un repère sombre. Le stress test utilise 1 262 instances et quatre variantes adultes.

À 1 920 × 1 080, Forward+, Metal, sur Apple M4, la composition finale atteint 60 appels de rendu, 10 214 primitives au pic, 8,72 ms en moyenne et 12,5 ms au p99 sur 330 images. Le stress test atteint 50 appels, 6 863 primitives, 8,33 ms en moyenne et 8,35 ms au p99. Ces mesures valident l'import, le regroupement et la marge sur cette machine ; elles **ne remplacent pas** la validation Intel Arc à 60 FPS.

Le profil reproductible est [ultimate_nature_profile.json](../Projet/data/assets/ultimate_nature_profile.json). Le laboratoire s'ouvre explicitement avec `--ultimate`; il ne modifie ni Terrain3D ni la scène de démarrage.

Le preset d'export exclut explicitement `assets_local/*`, le laboratoire et l'inspecteur. Un test automatisé protège cette règle afin que les sources de travail ne puissent pas glisser dans un build public.

## Suite

- produire ou sélectionner une végétation de rive historiquement plausible ;
- créer de vrais LOD/imposteurs avant peuplement d'une grande carte ;
- utiliser une capsule simple seulement pour les troncs proches du joueur ;
- comparer Sahara seul et Sahara + nature sur l'Intel Arc cible ;
- conserver tous les fichiers sources hors Git tant que la preuve de licence propre aux archives n'est pas archivée.
