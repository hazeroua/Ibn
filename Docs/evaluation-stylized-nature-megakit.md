# Évaluation — Stylized Nature MegaKit Standard

État au 21 novembre 2026. Cette évaluation répond au ticket [#76](https://github.com/hazeroua/Ibn/issues/76). Elle porte sur l'archive Standard gratuite distribuée par la [boutique officielle Godot](https://store.godotengine.org/asset/quaternius/stylized-nature-megakit/) par Quaternius, après autorisation explicite de téléchargement.

## Verdict

Le pack améliore immédiatement les zones rocheuses et fournit des graminées de prototype, mais **ne peut pas constituer l'oasis à lui seul** : la version Standard ne contient aucun palmier-dattier. Deux graminées sèches sont retenues. Les trois gros rochers, cinq galets ronds, deux graminées irriguées et un buisson restent adaptables. Les arbres tempérés/fantasy, plantes tropicales ambiguës, fleurs, champignons et chemins de pierres sont refusés pour cette tranche.

Aucun fichier source du pack n'est versionné. Le laboratoire Godot charge les glTF depuis `Projet/assets_local/`, ignoré par Git, et reste hors du catalogue de démarrage du jeu. Le profil réutilisable [oasis_nature_profile.json](../Projet/data/assets/oasis_nature_profile.json) contient la sélection, les corrections de pivot et les budgets de densité/LOD.

## Provenance, licence et sécurité

| Champ | Valeur constatée |
|---|---|
| Archive | `Stylized_Nature_MegaKitStandard.zip` |
| Taille | 104 088 529 octets |
| SHA-256 | `298f6732b872e4cf7b30e6e7abf9641c7f6dc6b326df37ac089533ed7e3d58c9` |
| Source | Boutique Godot officielle, fiche publiée par Quaternius |
| Fiche | Standard gratuite, 104,09 Mo, CC0 affiché |
| Preuve interne | Aucun fichier de licence dans l'archive |
| Politique appliquée | QAL v1.0 conservatrice : sources et dérivés d'assets hors Git tant qu'une preuve CC0 propre à l'archive n'est pas conservée |

La quarantaine a inspecté 459 entrées, 122 116 746 octets décompressés déclarés, sans exécutable, script, lien ni chemin traversant. Le seul fichier inattendu, `glTF/desktop.ini`, est un petit dictionnaire `[LocalizedFileNames]` sans commande ni URL. L'inspecteur accepte désormais uniquement cette forme inerte et refuse toute autre configuration `desktop.ini`. Seuls les `.gltf`, `.bin` et images référencées ont été extraits. Aucun `.blend`, projet moteur ou script tiers n'a été ouvert ou exécuté.

## Mesures techniques

L'analyse statique reproductible de [stylized-nature-standard-analysis.json](references/stylized-nature-standard-analysis.json) couvre les 68 glTF : 216 582 sommets, 148 947 triangles, 88 primitives, aucune animation. Les URI externes et chemins traversants sont refusés par l'outil.

Les 15 textures PNG réellement référencées vont de 512² à 2048² et leurs dimensions/octets figurent dans le rapport. L'archive contient aussi `Rocks_Desert_Diffuse.png` (2048², 2 095 731 octets), non référencée par les glTF : le mode dense l'applique explicitement aux rochers à la place de la texture vert-gris, sans modifier les sources.

Un rendu isolé à 1 920 × 1 080 a chargé les 17 candidats dans Godot 4.7.2, Forward+, Metal, sur Apple M4 : 88 appels de rendu et 15 199 primitives au pic. Le mode dense MultiMesh charge réellement 1 250 instances (1 000 touffes, 200 galets, 50 rochers) en 39 appels de rendu et 9 463 primitives visibles au pic ; sur 330 images, moyenne 8,61 ms et p99 9,52 ms. Ces mesures valident le laboratoire, l'import et le regroupement GPU, **pas** la cible Intel Arc. La décision 60 FPS exige encore une comparaison Sahara seul / Sahara+nature sur la machine Intel Arc cible.

## Matrice conserver / adapter / refuser

Chaque modèle de l'archive apparaît dans une famille ci-dessous.

| Modèles | Qté | Décision | Motif / action |
|---|---:|---|---|
| `Rock_Medium_1..3` | 3 | Adapter | Silhouettes lisibles, 244–522 triangles ; utiliser la texture désert incluse mais non assignée, offsets sol et échelle 0,6–1,0 |
| `Pebble_Round_1..5` | 5 | Adapter | 114–136 triangles ; harmoniser avec Terrain3D, rotation/échelle/groupes irréguliers, aucune collision |
| `Grass_Wispy_Short/Tall` | 2 | Conserver | Meilleures silhouettes sèches ; légère désaturation beige/gris-vert, atlas et MultiMesh |
| `Grass_Common_Short/Tall` | 2 | Adapter | Désaturer, supprimer les accents rouges et réserver aux bandes irriguées |
| `Bush_Common` | 1 | Adapter | Silhouette utilisable, mais feuillage rouge refusé ; recoloration, offset sol 0,235 m et validation botanique |
| `Plant_1`, `Plant_1_Big` | 2 | Refuser | Feuilles larges et silhouette tropicale/agave ambiguë ; la grande variante rompt l'échelle |
| `Plant_7`, `Plant_7_Big` | 2 | Refuser | Fleurs violettes/fantasy et pivots flottants |
| `Bush_Common_Flowers` | 1 | Refuser | Fleurs décoratives et deux matériaux sans bénéfice pour le Zab |
| `Clover_1..2`, `Fern_1` | 3 | Refuser | Lecture humide/tempérée non justifiée pour ce peuplement |
| `Flower_3_Group/Single`, `Flower_4_Group/Single`, `Petal_1..5` | 9 | Refuser | Palette et forme décoratives génériques ; aucune validation botanique |
| `Mushroom_Common`, `Mushroom_Laetiporus` | 2 | Refuser | Hors besoin et écologiquement trompeurs dans la scène actuelle |
| `CommonTree_1..5`, `Pine_1..5`, `TwistedTree_1..5`, `DeadTree_1..5` | 20 | Refuser | Aucun dattier ; silhouettes tempérées, conifères, fantasy ou mortes, jusqu'à 10 104 triangles |
| `Pebble_Square_1..6` | 6 | Refuser | Silhouette artificiellement cubique ; doublon inutile face aux galets ronds |
| `RockPath_Round_*`, `RockPath_Square_*` | 10 | Refuser | Assemblages de chemin coûteux (559–3 500 triangles), trop aménagés et moins flexibles qu'une dispersion |

Total : 68 modèles — 2 conservés, 11 à adapter, 55 refusés.

## LOD et peuplement proposés

- Rochers : original jusqu'à 30 m, 180 triangles maximum jusqu'à 65 m, 64 jusqu'à 120 m, imposteur 2 triangles jusqu'à 220 m. Collisions convexes/boîtes uniquement près du joueur.
- Galets : original jusqu'à 12 m, 40 triangles jusqu'à 25 m, 12 jusqu'à 40 m, puis sol/imposteur et disparition à 55 m. Aucune collision.
- Graminées : géométrie originale jusqu'à 12 m, 96 triangles jusqu'à 25 m, cartes croisées de 12 triangles jusqu'à 45 m, imposteur jusqu'à 70 m. MultiMesh, atlas, alpha-scissor, ombres coupées après 12–15 m et aucun nœud par brin.
- Buissons : original jusqu'à 20 m, 300 triangles jusqu'à 45 m, 80 jusqu'à 85 m, imposteur jusqu'à 160 m. Aucune collision pour la variante basse.

Les plafonds initiaux du micro-biome sont 45 rochers, 240 galets, 1 800 touffes et 80 buissons. La couche nature vise au plus 60 appels de rendu et 250 000 triangles visibles. Le mode dense du laboratoire instancie 1 000 touffes, 200 galets et 50 rochers par MultiMesh. Ces nombres sont des budgets de test, pas une promesse de contenu ; ils devront être ajustés après comparaison Sahara seul / Sahara+nature sur Intel Arc (p99 ≤ 16,6 ms, VRAM totale ≤ 512 Mio).

## Lacunes et suite

Le dattier (`Phoenix dactylifera`) et la végétation de rive restent obligatoires selon le [guide de l'oasis du Zab](oasis-zab-guide-historique.md). L'[évaluation du pack Ultimate](evaluation-ultimate-stylized-nature.md) fournit désormais des proxies de dattier sans réintroduire les familles déjà refusées ; la végétation de rive reste manquante. Les personnages ne sont pas concernés par ces packs : leurs rigs, tenues et performances sont traités dans les tickets dédiés afin de ne pas mélanger licences, validation historique et squelettes.

## Reproduire sans publier les sources

1. Placer l'archive autorisée dans `Import/quarantaine/` et vérifier son SHA-256 exact.
2. Exécuter l'inspection de quarantaine ; ne jamais contourner un refus non expliqué.
3. Extraire uniquement `glTF/` dans `Projet/assets_local/quaternius-stylized-nature-standard/`, en excluant `desktop.ini`.
4. Lancer `Tools/analyser-pack-gltf.ps1`, puis l'import Godot.
5. Ouvrir explicitement `res://world/asset_lab/nature_asset_lab.tscn`. Cette scène n'est pas chargée par le jeu normal.

Le laboratoire échoue clairement si les sources locales manquent ; le projet principal, les tests et l'export restent indépendants du pack non redistribuable.
