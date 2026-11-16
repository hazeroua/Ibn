# Reste à faire après les corrections du 16 novembre (MVP 2, désert)

Fusionné dans `main` à la demande du porteur du projet, **sans les vérifications finales** (plus de jetons disponibles). Ce document liste tout ce qui reste à faire. Voir aussi `Docs/remarques-mvp-2.md` (section 9).

## 1. Vérifications sautées (à faire en premier)
Les quatre contrôles du projet n'ont pas tourné sur la végétation texturée (ticket #24, commit `9dbabcc`) :
- **directeur-artistique** : juger les captures avant/après de la végétation ;
- **garant-performance** : coût de la découpe alpha (pré-passe de profondeur, ombres), surdraw des cartes de feuillage, distances des niveaux de détail ;
- **historien** : espèces d'oasis du Maghreb au XIVe siècle et leur aspect (palmes du dattier, olivier argenté, fleurs du laurier-rose) ;
- **verificateur** : lint, raccourcis interdits, contrat conservé (saisons, vent, fleurs et fruits), tests GUT.

Les corrections de l'eau, de la palmeraie et des pas (commits `883b8f1`, `249095a`) ont été vérifiées une fois. Les points « à corriger » de cette vérification sont traités, sauf ceux de la section 3.

## 2. À mesurer sur la puce Intel Arc (rien n'a été mesuré dessus)
- **Palmeraie** : pire cas doublé (au plus 30 parcelles, 152 murets, 289 formes de collision par cellule ; décor construit en 46 ms au pire sur un fil de travail, mesuré sous Linux). Le shader de terre fait 9 lectures de texture par pixel.
- **Végétation texturée** (mesures en rendu logiciel seulement) :
  - appels de rendu inchangés ;
  - primitives de 133 000 à 198 000 sur `vue_oasis_sol` (la simplification automatique de Godot est coupée sur la végétation) ;
  - mémoire vidéo de 246 à 280 Mo pour une limite de 384 Mo, dont environ 29 Mo d'écart inexpliqué ;
  - temps par image + 3 à 6 %.
- **Scintillement des bords de feuilles** avec FSR 2.
- Palmeraie dense vue de la crête, et galop en zone dense.

## 3. Défauts connus
- Les **rides du lac** forment un motif un peu régulier.
- **Anneau de terre nue** vide entre l'oasis et les jardins.
- **Horizon** : au-delà du monde chargé, c'est une plaine unie.
- **Imposteurs lointains des palmiers** (au-delà de 320 m) : silhouette un peu « champignon ».
- **Roseaux et joncs** entre 30 et 60 m : ils se lisent comme des masses verticales.
- ~~**Pas** : le même pied sonne deux fois de suite entre la marche et l'arrêt.~~ Corrigé (same_foot_min_gap_s).
- ~~`Wind._probe_ground` crée un dictionnaire 10 fois par seconde.~~ Corrigé : nœud RayCast3D, aucune allocation.
- Le générateur de modèles écrit maintenant lui-même les réglages d'import ; `lancer.bat` régénère les modèles et l'atlas au premier lancement.

## 4. Tests à écrire ou à réparer
- **Test de charge de la palmeraie** (décor, collisions, shader de terre).
- **Pas calés sur l'animation** : test avec un squelette (appuis, silence contre un mur, arrêts).
- **Géométrie des séguias** : crête au-dessus du sol, bouts fermés, collision du lit et des berges.
- ~~**Échecs GUT déjà présents sur `main`**~~ : corrigés, toute la suite GUT passe (352 tests, commit `816e56b`).

## 5. Ce qui a été fait (rappel)
- **Eau** visible (oasis, lac, guelta) ; oasis creusée de 2,2 m.
- **Relief** : terrasse de jardins autour de l'oasis ; plus de zones carrées relevées au niveau des plans d'eau.
- **Palmeraie** : 79 parcelles, des palmiers dans toutes. Murets, séguias et bassins ont la texture de la terre du terrain, leur pied est enfoui dans le sol, et ils ont tous une collision.
- **Séguias** : on marche sur les berges et dans le lit, les bouts sont fermés.
- **Pas** : déclenchés à l'appui du pied dans l'animation, silencieux contre un mur.
- **Sable du vent** : grains ronds au ras du sol.
- **Chott** : rive irrégulière.
- **Captures** : le monde se charge autour du point de vue ; nouveaux points de vue au sol (oasis, palmeraie, lac).
- **Végétation texturée et peinte** (#24) : une seule texture partagée, des cartes de feuillage, des écorces.
