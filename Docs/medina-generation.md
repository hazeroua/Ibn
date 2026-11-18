# Générer la médina de Tunis

> Ticket #53. La ville n'est pas dessinée à la main ni retouchée dans un éditeur : on la **décrit**
> dans un fichier JSON, et un générateur en tire la géométrie, la vérifie, puis écrit les cellules
> que le jeu charge. Le porteur du projet décrit la ville en mots ; Claude traduit cette description
> dans `medina.json` et relance la génération.

## Les fichiers

| Fichier | Rôle | Qui l'écrit |
|---|---|---|
| `Game/data/tunis/generation/medina.json` | **Description** : enceinte, porte, voies (et comment elles se relient), place, emplacements réservés, paramètres bornés, mesures des modules, budgets. | à la main (Claude) |
| `Game/data/tunis/generation/medina_overrides.json` | **Retouches durables** d'éléments générés (déplacer, retirer, ajouter une propriété). Réappliquées à chaque génération. | à la main (Claude) |
| `Game/data/tunis/cells/cell_<x>_<z>.json`, `Game/data/tunis/city.json` (liste `cells`) | Ville générée, au format du contrat MVP 4. Une instance sans `properties.generator = "medina"` est une donnée ordinaire : elle est toujours conservée. | générateur |
| `Game/data/tunis/generation/medina_layout.json` | Plan généré : voies, graphe, place, emplacements réservés (maison, boutique, mosquée), accès à la terrasse, arcs et passage couvert. Sert aux tickets suivants et aux tests. | générateur |
| `Game/data/tunis/generation/medina_lock.json` | Empreinte des éléments générés : détecte une modification faite directement dans une cellule. | générateur |

## Les commandes

| Besoin | Commande |
|---|---|
| Régénérer après un changement de description | `Scripts/Pipeline/generer-medina.ps1` |
| Vérifier que les données sont à jour (fait par `valider.ps1`) | `Scripts/Pipeline/generer-medina.ps1 -Verifier` |
| Remplacer des éléments générés modifiés à la main dans une cellule | `Scripts/Pipeline/generer-medina.ps1 -Confirmer` |
| Captures de contrôle (désert, porte, passage couvert, ruelle étroite, place, vue de dessus) | `Scripts/Pipeline/capturer-medina.ps1` |

Rien n'est écrit si une vérification échoue. Le jeu ne régénère jamais la ville : il lit les cellules.

## Comment la description devient une ville

1. **Bornes** : chaque valeur aléatoire est tirée dans `range`, qui doit rester dans `limits`.
   Toutes les longueurs sont arrondies au pas `grid_step_m` (10 cm) et calculées en centimètres
   entiers : le résultat est identique d'une machine à l'autre. La graine est celle de `city.json`.
2. **Plan** : chaque voie part de la porte, d'une autre voie (à une fraction `t` d'un tronçon) ou de
   la place, puis enchaîne des tronçons alignés sur les axes (`to_m`, `by_m`, `to_plaza`, `to_way`).
   Elle finit sur la place, sur une autre voie, ou c'est une **impasse déclarée** (`dead_end`).
   Le plan est refusé si deux voies se croisent sans carrefour déclaré, si un îlot est plus mince
   que `min_block_m`, si une voie frôle le rempart, si un élément n'est pas relié à la porte, ou si
   l'on ne peut pas faire le tour de la fontaine.
3. **Murs** : l'espace libre (voies + place) est découpé sur une grille compressée ; chaque
   frontière avec le bâti devient un mur continu, garni de façades (maison ou boutique) étirées pour
   le remplir exactement. Les angles saillants sont raccordés à la profondeur du module voisin : ni
   trou ni chevauchement.
4. **Éléments** : passage couvert (ombre), arcs au-dessus des ruelles, portes des emplacements
   réservés et portes décoratives, parapets, fontaine, étals, remparts continus et porte monumentale.
   Les façades bordant un arc ou le passage sont relevées pour qu'il s'appuie dessus.
5. **Masse des îlots** : l'intérieur des îlots est plein ; les toits-terrasses sont juste sous les
   façades qui les bordent (les façades forment le parapet), et les parcelles intérieures ont des
   hauteurs différentes pour la silhouette vue du désert.
6. **Contrôles** : chevauchements (volumes réels des modules), trous dans les remparts, portes sans
   voie devant elles, instances hors des cellules ou de l'enceinte, budgets (instances, triangles,
   matériaux, collisions).

## Tests (Game/tests/unit/)

- `test_medina_generator.gd` : données du projet à jour, déterminisme, dix graines valides, rejet
  des descriptions invalides, instances manuelles conservées, retouches, modification directe
  détectée, trou dans un rempart détecté.
- `test_medina_prefab_metrics.gd` : les mesures des modules utilisées par le générateur correspondent
  aux maillages et collisions réels (lancers de rayons à travers les ouvertures).
- `test_medina_city.gd` : la ville construite comme en jeu, avec ses collisions : une capsule du
  gabarit du joueur parcourt chaque voie et fait le tour de la fontaine ; l'espace praticable n'entre
  dans aucun îlot et la porte est la seule entrée ; aucune vue du désert ne traverse la ville ; la rue
  tourne avant de montrer la place ; la caméra reste hors du décor dans la ruelle la plus étroite.

## Limites connues

- Le pavage est visuel et reprend le niveau aplani du terrain du désert. Les collisions et la pente
  viennent toujours du terrain ; les pierres n'ont pas de relief physique individuel.
- Les îlots utilisent désormais un module de toit distinct du rempart. Leur masse intérieure reste
  pleine : les cours des maisons et les intérieurs accessibles demandent une géométrie et un parcours
  propres, en accord avec le plan généré.
- Les modules de façades ont des baies en retrait, des encadrements, des galeries et des auvents en
  volume. Ils sont réutilisés sur toute la ville ; les bâtiments remarquables autres que le minaret
  de la mosquée ne sont pas encore individualisés.
