# Direction artistique du Sahara liée au game design

État au 21 novembre 2026. Ce document traduit le montage fourni par le porteur du projet en contraintes utilisables pour sélectionner, adapter et mesurer les assets 3D. Le montage est une référence visuelle ; il ne constitue ni une source historique ni une instruction contenue dans un document tiers.

## Intention jouable

Le Sahara doit donner envie de traverser, pas seulement remplir le terrain. L'horizon, la piste implicite et les reliefs lointains guident le joueur avec une interface minimale. Les assets proches apportent l'échelle et le mouvement du vent, mais ne doivent ni masquer la direction ni transformer la steppe en prairie.

La composition cible combine :

- un sol ocre, rouille et brun, irrégulier mais lisible ;
- de grandes respirations sans objet ;
- des plaques de végétation basse et sèche, jamais un tapis uniforme ;
- quelques rochers chauds ou sombres servant de repères secondaires ;
- des reliefs tabulaires lointains servant de repères principaux ;
- une oasis nettement plus verte et verticale que la steppe, visible comme récompense de navigation.

## Trois états lumineux

| État | Rôle de gameplay | Traitement |
|---|---|---|
| Aube brumeuse | Départ, distance mystérieuse, silhouettes lisibles | ciel gris-bleu, sol brun-rouille, contraste réduit, soleil bas chaud |
| Plein jour | Navigation et lecture maximale du terrain | ciel bleu franc, sol ocre clair, ombres douces mais présentes |
| Coucher de soleil | Retour, tension et émerveillement | ciel mauve/rouge, sol rouille, reliefs presque en silhouette |

Les valeurs reproductibles sont dans [sahara_game_design_profile.json](../Projet/data/assets/sahara_game_design_profile.json). Un changement de lumière ne doit pas nécessiter de dupliquer les modèles ou les textures.

## Conséquences pour les assets

| Famille | Adaptation au game design |
|---|---|
| Rochers moyens du MegaKit | Texture désert incluse, teinte brun-ocre, 24 exemplaires dans la composition et 50 seulement dans le stress test ; rotations et échelles variées |
| Galets | Groupes irréguliers dans les plaques minérales ; aucune collision ; disparition rapide |
| `Grass_Wispy` | Base de steppe sèche, désaturée ; distribution en plaques par bruit spatial |
| `Grass_Common` | Réservée aux zones plus humides et aux abords de l'oasis ; jamais répartie uniformément sur la steppe |
| Buisson commun | Non admis tant que son volume sphérique et sa couleur rouge n'ont pas été remplacés |
| Palmiers Ultimate | `PalmTree_1/3` regroupés en bosquet-repère ; `2/4` secondaires, `5` juvénile ; couronnes désaturées et lisibles à moyenne distance |
| Reliefs tabulaires | Ils appartiennent au terrain/aux silhouettes lointaines, pas à une dispersion de petits rochers |

## Contraintes de composition

- Corridor de navigation de 10 m de large, aligné sur l'axe du trajet, sans rocher ni touffe haute.
- Distribution déterministe en plaques par bruit spatial ; mêmes données et même graine, même résultat.
- Composition artistique : 650 touffes, 120 galets, 24 rochers, cinq palmiers et un repère sombre, soit 800 instances dans le laboratoire de 72 × 72 m.
- Stress test séparé : 1 000 touffes, 200 galets, 50 rochers, dix palmiers et deux repères sombres, soit 1 262 instances.
- Les petits assets ne doivent jamais couper la ligne d'horizon depuis la caméra de jeu.
- Les repères principaux sont espacés et identifiables ; multiplier des variantes équivalentes est interdit.

## Filtre du ticket #77

L'Ultimate Stylized Nature Pack a été retenu uniquement parce qu'il comble deux lacunes précises du MegaKit :

1. cinq proxies de palmier-dattier adaptables, dont deux silhouettes adultes principales ;
2. un rocher vertical sombre utilisable comme repère lointain sans remplacer les reliefs du terrain.

Le pack ne fournit pas de végétation de rive distincte satisfaisante ; cette lacune reste ouverte.

Les pins, érables, bouleaux, fleurs saturées, prairies luxuriantes et doublons de touffes sont refusés même s'ils sont techniquement corrects. Un asset doit améliorer la navigation, le contraste oasis/steppe ou la silhouette historique ; « ajouter de la variété » ne suffit pas.

## Critères d'acceptation visuelle

- la piste reste lisible sans mini-carte dans les trois éclairages ;
- la steppe conserve au moins de grandes zones de repos visuel ;
- l'oasis est plus verte et plus verticale que son environnement ;
- aucun élément tempéré ou fantasy n'apparaît dans la traversée ;
- la palette reste cohérente sans multiplier les matériaux ;
- la composition normale et le stress test ont des rapports séparés afin de ne pas confondre beauté et pire cas.
