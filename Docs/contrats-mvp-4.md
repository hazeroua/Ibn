# Contrats du MVP 4 — La porte de Tunis

> Ce contrat permet de traiter les tickets du MVP 4 dans des worktrees séparés, sans que deux
> agents modifient les mêmes sources. Les données JSON sont la source de vérité ; toute scène
> Godot de Tunis est construite par script et ne se modifie jamais à la main.

## Résultat attendu

Le joueur arrive du désert, laisse Barq à la porte, entre à pied dans une première rue de médina,
visite une maison, une boutique et une petite mosquée, interagit avec le décor, atteint une terrasse
et revient à son cheval. La ville tient 60 i/s à 1080p sur Intel Arc dans les pires cas définis dans
[`06-roadmap-mvp.md`](06-roadmap-mvp.md).

## Données communes

Tous les fichiers vivent sous `Game/data/tunis/` :

| Fichier | Source de vérité |
|---|---|
| `city.json` | Version de schéma, graine, origine, taille et limites des cellules, liste des fichiers de cellules. |
| `catalog.json` | Prefabs autorisés, chemins d'assets, empreinte, points d'accrochage, collision, LOD et catégories. |
| `cells/cell_<x>_<z>.json` | Instances placées dans une cellule. |
| `interiors/<id>.json` | Données propres à une maison, boutique ou petite mosquée. |
| `interactions.json` | Actions, textes et paramètres des objets interactifs. |
| `audio.json` | Zones et sources sonores. |
| `viewpoints.json` / `route_joueur.json` | Captures, vidéo et parcours automatiques reproductibles. |

Le schéma courant est `1`. Les coordonnées sont en mètres Godot : Y vertical, X/Z horizontaux,
origine dans `city.json`. Une cellule est calculée avec `floor((x - origin.x) / cell_size_m)` et
`floor((z - origin.z) / cell_size_m)`, y compris pour les coordonnées négatives. Les cellules font
la même taille sur X et Z. Toute donnée d'une version inconnue est refusée ; aucune migration ne
réécrit silencieusement les fichiers source.

Une instance possède obligatoirement `id`, `prefab_id`, `cell`, `position`, `rotation_y`, `scale`,
`layer` et `properties`. Son identifiant est unique dans toute la ville, stable, en `snake_case` et
ne dépend ni d'un ordre de tableau ni d'un `NodePath`. `prefab_id` référence le catalogue ;
`interaction_id` et `audio_id`, lorsqu'ils sont présents dans `properties`, référencent les fichiers
homonymes.

La sauvegarde canonique trie les clés des objets et les instances par `id`. À données égales, deux
sauvegardes ont exactement le même contenu UTF-8 ; un builder ne modifie pas les données source.

## Pires cas communs

- Entrée au galop dans la porte, puis descente sûre de Barq.
- Caméra dans la ruelle la plus étroite.
- Trois intérieurs chargés, portes ouvertes, fontaine, éclairage et audio actifs simultanément.

## Propriété des fichiers

| Ticket | Possède |
|---|---|
| #48 Contrat | `Docs/contrats-mvp-4.md`, `Game/world/tunis/data/`, fixtures et tests de validation, structure JSON initiale. |
| #49 Assets | `Scripts/Blender/generer_architecture_tunis.py`, `Game/assets/tunis/`, entrées de prefabs de `catalog.json`. |
| #50 Runtime | `Game/world/tunis/` hors `data/`, `Game/tools/builders/build_tunis.gd`, raccord pipeline. |
| #51 Admin | `Game/tools/tunis_editor/`, commande de lancement de l'éditeur. |
| #52 Sauvegarde | Persistance et historique de l'éditeur, sans modifier le validateur de #48. |
| #53 Médina | Données de génération et cellules de rue/place/remparts. |
| #54 Porte | Données de transition et intégration avec Barq. |
| #55 Intérieurs | `Game/data/tunis/interiors/` et contenu de leurs cellules. |
| #56 Interactions | Système d'interaction et entrées associées. |
| #57 Escalade | Données de prises, contrôleur et réglages caméra concernés. |
| #58 Ambiance | Données audio/visuelles et systèmes associés. |
| #59 Intégration | Scène assemblée, budgets, parcours, captures, vidéo et journal de fin. |

Un ticket ne modifie aucun fichier possédé par un autre. Une évolution de ce contrat passe par un
ticket dédié et une mise à jour explicite des tickets dépendants.
