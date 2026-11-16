# Remarques à garder de côté : fin du MVP 2 (série « Nature », tickets #17 à #23)

Ce document liste ce qui reste à reprendre, à vérifier ou à décider. Il est écrit en français simple.
Rien de la série « Nature » n'a été compilé, lancé ni testé : le code a été écrit et relu, mais jamais exécuté
(pas de Godot, de Blender ni de compilateur C++ dans l'environnement de travail).

## 1. À faire en premier : vérifier que ça démarre

1. `git pull --ff-only` puis `.\lancer.bat` (recompile le C++, régénère les modèles Blender).
2. Si ça plante : lire `Mesures\journaux\jeu.log`.
3. Zone la plus risquée : le C++ de la végétation (`Extensions/src/vegetation_scatter.cpp`) a été modifié par
   quatre tickets différents sans jamais être compilé. Avertissements = erreurs : il peut y avoir un ou deux
   petits défauts de compilation.
4. Ensuite seulement : `valider.ps1`, tests, mesures, captures (voir section 6).

## 2. Ce qui est « provisoire » dans les faits (écarts avec la règle « aucun raccourci »)

| Sujet | Écart | Ce qu'il faudrait |
|---|---|---|
| Sons de pas dans l'eau et sons de la faune | Synthétisés par le code (`SoundSynth`, `FaunaSynth`), pas des enregistrements libres | Télécharger de vrais sons CC0 (gravier, eau, chants d'aube, criquets, rapace) avec leur SHA-256 |
| Son de pas « galets » | Réutilise des sons de pierre et de terre | Un vrai son de gravier |
| Séguias de la palmeraie | De petites berges de 0,5 m avec un filet d'eau, **pas creusées** dans le terrain, sans collision | Les creuser dans la hauteur du terrain (`LandscapeFeatures`) |
| Vigne | Un motif de rangs au sol, pas de modèle 3D | Un vrai modèle de vigne |
| Niveau de détail des arbres | Choisi **par cellule de 250 m**, pas par arbre : toute la cellule passe au même niveau | Soit des sous-cellules, soit un choix par instance dans le C++ |
| Couches proche/lointaine du couvert du sol (alfa, drinn…) | Même limite : la distance s'applique à la cellule entière, le fondu peut « sauter » au ras du sol | Idem : sous-cellules ou C++ |
| Drinn sur les crêtes | Approché par `altitude_min` 38 et pente max 24° : le C++ n'a pas de pente minimale | Ajouter une pente minimale au C++ |
| Oued : fond du lit | Suit le minimum local du relief : peut être plus profond que `depth_m` par endroits | Décider si c'est voulu |
| Parcelles de la palmeraie | Peuvent atteindre 44 m (au lieu de 40) quand elles sont trop petites pour être coupées | Resserrer la règle |

## 3. Choses « codées en dur » ou à confirmer

- **Positions inventées** (toutes marquées `statut_historique` « P » ou « F » dans `desert.json`) : lac des roseaux
  (620, −300), guelta (−80, −330), chott (1050, −1000), deux oueds. Aucun n'a été relu par l'agent `historien`.
- **Courbes d'eau du tamaris et du laurier-rose** : calées sur l'oasis de 55 m de rayon (distance normalisée).
  Un plan d'eau plus grand ferait dépasser les 30 m voulus. Il faudrait exprimer ces courbes en mètres.
- **Grille de 125 m (32 × 32)** de `LandscapeFeatures` : les 32 cases par côté sont une constante du script
  (`GRID_SIDE`), pas une donnée. Même chose pour les maxima (32 plans d'eau, 16 oueds, 64 points).
- **Limite de 40 espèces** de végétation dans le C++ (24 utilisées). La mémoire réservée par espèce est
  calculée à partir de `max_instances` : à surveiller si on en ajoute beaucoup.
- **Compatibilité de noms** : `OasisWater` existe encore (utilisé par `test_props_water`) en plus de `WaterBody`.
  Deux chemins de code pour l'eau ; à unifier plus tard.
- **Hauteurs des points de vue** `vue_lac`, `vue_guelta`, `vue_chott`, `vue_faune` : estimées sans voir le
  relief, à ajuster d'après les premières captures.
- **Fichiers `.uid`** : ceux de plusieurs nouveaux scripts n'ont pas été créés ; quatre autres (palmeraie) l'ont été à la
  main avec des identifiants inventés. Godot les régénérera ; à versionner après le premier lancement.
- **Texture `river_small_rocks`** (Poly Haven) : identifiant jamais vérifié (pas d'accès réseau).
  À confirmer avec `importer-ressources.ps1`.
- **Alpha des couleurs de sommet** des modèles de faune (poids d'animation) : si l'import glTF de Godot perd
  l'alpha, il faudra changer de méthode.

## 4. Ce qui manque (fonctionnalités prévues par les tickets, non faites)

- **Flaques d'hiver** dans les oueds (ticket #20) : elles dépendaient de `season_wetness`, arrivé après.
- **Végétation dans le lit des oueds** : le C++ ne connaît pas la surface « galets » : rien n'y pousse.
- **Fennec** (cité dans le ticket faune) et **corbeau en vol libre** : non faits.
- **Éboulis** : placés le long de toutes les berges d'oued, pas seulement dans la gorge.
- **Avis de l'agent `historien`** sur toutes les espèces, tous les lieux et tous les animaux : à faire (les agents
  ont appliqué eux-mêmes la liste du ticket, ce qui n'est pas la même chose).
- **Captures** : aucune relue par `directeur-artistique` ; manquent aussi les vues à hauteur d'homme (allée de la
  palmeraie, printemps et été).
- **Mesures de vitesse** : le pire cas de `vue_crete` n'a jamais été mesuré avec les nouvelles espèces.

## 5. Risques de performance à mesurer (estimations seulement)

- Total estimé en vue de crête : 0,9 à 1,1 million de primitives (budget 1,5 million) ; palmeraie seule : environ
  230 000 triangles. **Ce sont des calculs à la main, pas des mesures.**
- Appels de dessin estimés à 200 ou moins (budget 300). Plus d'espèces et plus de niveaux de détail : à vérifier.
- Gazelles : environ 60 000 appels à `height_at` au chargement (dans un fil de travail).
- Palmeraie : temps de construction d'une cellule et du plan au chargement non mesurés.
- Un accrochage de 258 ms noté plus tôt (probablement compilation de shaders) : toujours à étudier sur secteur.
- Les nouveaux shaders (eau, chott avec mirage, palmeraie, faune) n'ont jamais tourné sur la puce Intel Arc.

## 6. Tests et validation en retard

- **Aucun test n'a été écrit** pour les tickets #17 à #23, à la demande du porteur du projet. À écrire plus tard :
  - `test_landscape_features` (relief de l'oasis inchangé, coût de `height_at`, distance aux oueds contre calcul brut) ;
  - budgets de triangles des nouveaux modèles (arbres, falaises, faune, roseaux, cultures) et couleurs de sommets ;
  - placement des tamaris et lauriers-roses près de l'eau ; zéro allocation du `scatter`.
- **Tests existants à revoir** : `test_seasons_system` ne liste pas les nouveaux uniformes (`season_bloom`,
  `season_flowering`, `season_wetness`, `season_fruit`, `season_crop_growth`, `season_crop_ripe`) ; `test_vegetation_scatter`
  supposait que la surface n'était pas évaluée quand toutes les surfaces sont permises (ce n'est plus vrai).
- **Budgets de temps** : toujours en mode « non bloquant » (`ibn/tests/budgets_de_temps_bloquants=false`) à
  réactiver sur secteur ou en CI.
- **Agents de contrôle** jamais appelés sur cette série : `verificateur`, `garant-performance`, `directeur-artistique`.
- `valider.ps1` complet (pas seulement `-Rapide`) jamais relancé depuis ces fusions.

## 7. Décisions à prendre

1. Les 7 tickets « Nature » sont rangés dans le MVP 2 : le MVP 2 n'est donc pas encore terminé. Les garder dedans,
   ou en faire une étape à part ?
2. Garder les sons synthétisés pour l'instant, ou exiger de vrais enregistrements avant de clore le MVP 2 ?
3. Creuser les séguias dans le terrain (modifie la hauteur, donc touche toute la chaîne du relief) ?
4. Passer le choix des niveaux de détail et des couches du sol « par instance » (plus propre, plus de C++) ?
5. Unifier `OasisWater` et `WaterBody` ?
6. Découper `generer_props_desert.py` : il a grossi très vite (arbres, couvert du sol, falaises, cultures) et a
   été fusionné à la main plusieurs fois.

## 8. Risques liés à la méthode

- Sept tickets ont été écrits en parallèle, puis fusionnés à la main : les conflits les plus délicats sont dans
  `seasons.gd`, `landscape_features.gd`, `desert_heightfield.gd`, `vegetation.json`, `foliage.json`,
  `generer_props_desert.py` et `desert_session.gd`. Une relecture complète de ces fichiers après le premier
  lancement est conseillée.
- Les JSON `vegetation.json` et `foliage.json` ont été réécrits avec une mise en forme différente (indentation
  standard) lors des fusions : le contenu est le même, mais le diff Git est bruyant.
- Deux agents ont ajouté le même mécanisme de floraison avec des sens différents ; séparé en deux variables.
  Un défaut de ce genre peut en cacher d'autres : lire les shaders (`desert_foliage.gdshader`) au premier plantage.

## 9. Après les premiers essais du porteur du projet (16 novembre)
Corrigé : eau invisible (faces à l'envers), oasis sans profondeur, palmeraie presque vide (relief trop bosselé ; terrasse de jardins ajoutée, 79 parcelles), murets et séguias gris et posés sur le sol, séguias traversables et ouvertes sur les côtés, pas désynchronisés (désormais calés sur les appuis lus dans l'animation, silencieux contre un mur), carrés de sable flottants, rive du chott en cercle parfait, zones carrées relevées au niveau des plans d'eau.

Reste à faire :
- **Végétation** trop « jouet » : ticket #24, en cours dans la branche `vegetation-texturee`.
- **Test de charge de la palmeraie** : le pire cas a doublé (au plus 30 parcelles, 152 murets, 289 formes de collision par cellule ; décor construit en 46 ms au pire sur un fil de travail, mesuré sous Linux). Le shader de terre fait 9 lectures de texture par pixel. À mesurer sur la puce Intel Arc.
- **Tests GUT** : aucun test ne couvre les pas calés sur l'animation (les tests tournent sans squelette), ni la géométrie des séguias. `test_desert_heightfield` est mis à jour (oasis creusée, terrasse).
- Les rides du lac restent un motif assez régulier ; l'anneau de terre nue entre l'oasis et les jardins est vide ; au-delà du monde chargé, l'horizon est une plaine unie.
- Deux pas de suite du même pied entre la marche et l'arrêt.
