# Décision de licence — packs Quaternius

État observé le 21 novembre 2026 pour le ticket [#73](https://github.com/hazeroua/Ibn/issues/73). Cette analyse ne remplace pas un avis juridique et ne vaut pas acquisition : aucun pack ni fichier d'asset n'a été téléchargé.

## Constat contradictoire

Les sept fiches officielles étudiées affichent **CC0** et la FAQ affirme que tous les modèles sont sous CC0. À l'inverse, la page de licence globale, mise à jour le 28 août 2026, présente la **Quaternius Asset License (QAL) v1.0** comme licence applicable aux assets publiés sous cette licence.

La QAL autorise l'utilisation, la copie et la modification dans un produit personnel, éducatif ou commercial, sans attribution. Elle autorise aussi les collaborateurs et prestataires à travailler sur le produit. Elle interdit toutefois de redistribuer les assets, originaux ou modifiés, comme fichiers autonomes, pack, stock, modèle ou contenu comparable.

Ces pages ne permettent pas de démontrer avec certitude si chaque archive gratuite conserve CC0 ou bascule sous QAL. La date ancienne d'une fiche ne suffit pas à prouver la licence du fichier qui serait téléchargé aujourd'hui.

## Décision conservatrice

Pour chacun des sept packs, la décision est identique et explicite :

1. le pack reste un **candidat non acquis** ;
2. toute acquisition nouvelle est traitée comme **QAL v1.0** tant que l'archive obtenue ne contient pas une preuve CC0 explicite et rattachable à ses fichiers ;
3. sous QAL, les sources originales ou modifiées restent hors du dépôt public, y compris les GLB, FBX, OBJ, Blend, textures et animations dérivées ;
4. un jeu fini peut incorporer les assets et être distribué, mais le dépôt et le build ne doivent jamais les présenter comme un pack ou des fichiers autonomes réutilisables ;
5. les collaborateurs et prestataires peuvent recevoir les fichiers uniquement pour travailler sur ce produit et sous les mêmes restrictions ;
6. aucune attribution n'est exigée par QAL, mais la provenance reste obligatoire dans le manifeste interne du projet ;
7. l'acquisition ne sera autorisée qu'après enregistrement du nom exact de l'archive, de sa taille, de son SHA-256 et de la licence incluse.

Si une archive autorisée contient une licence CC0 explicite, la décision pourra être révisée pour **cette archive précise seulement**, après conservation de la preuve et de son empreinte. La FAQ ou la fiche web, seules, ne suffisent pas à appliquer CC0 à un téléchargement futur en présence de la contradiction actuelle.

## Relevé par pack

| Pack | Date affichée | Licence affichée sur la fiche | Formats affichés | Décision dépôt public |
|---|---|---|---|---|
| [Stylized Nature MegaKit](https://quaternius.com/packs/stylizednaturemegakit.html) | juillet 2024 | CC0 | FBX, OBJ, Blend, glTF | Sources hors Git ; QAL par défaut jusqu'à preuve CC0 de l'archive |
| [Ultimate Stylized Nature Pack](https://quaternius.com/packs/ultimatestylizednature.html) | mai 2022 | CC0 | FBX, OBJ, Blend, glTF | Sources hors Git ; QAL par défaut jusqu'à preuve CC0 de l'archive |
| [Fantasy Props MegaKit](https://quaternius.com/packs/fantasypropsmegakit.html) | juin 2025 | CC0 | FBX, OBJ, Blend, glTF | Sources hors Git ; QAL par défaut jusqu'à preuve CC0 de l'archive |
| [Medieval Village MegaKit](https://quaternius.com/packs/medievalvillagemegakit.html) | janvier 2025 | CC0 | FBX, OBJ, Blend, glTF | Sources hors Git ; QAL par défaut jusqu'à preuve CC0 de l'archive |
| [Universal Base Characters](https://quaternius.com/packs/universalbasecharacters.html) | août 2025 | CC0 | en-tête : FBX, OBJ, Blend, glTF ; fonctionnalités : FBX et glTF | Sources hors Git ; QAL par défaut jusqu'à preuve CC0 de l'archive |
| [Modular Character Outfits — Fantasy](https://quaternius.com/packs/modularcharacteroutfitsfantasy.html) | novembre 2025 | CC0 | en-tête : FBX, OBJ, Blend, glTF ; fonctionnalités : FBX et glTF | Sources hors Git ; QAL par défaut jusqu'à preuve CC0 de l'archive |
| [Universal Animation Library](https://quaternius.com/packs/universalanimationlibrary.html) | mars 2025 | CC0 | FBX, GLB, Blend | Sources hors Git ; QAL par défaut jusqu'à preuve CC0 de l'archive |

## Règles concrètes pour Git et les builds

- `Import/` reste ignoré par Git et reçoit uniquement les archives acquises avec autorisation.
- Les sources QAL et leurs conversions ne doivent pas être ajoutées à Git LFS : Git LFS reste une redistribution.
- Le dépôt peut contenir les URL, métadonnées, SHA-256, scripts de conversion écrits par le projet et réglages d'import sans recopier l'asset.
- Un workflow public ne doit pas télécharger automatiquement un asset QAL depuis une URL privée ou publier l'archive en cache ou artifact CI.
- La CI publique doit utiliser des substituts synthétiques tant que les conditions de distribution du produit fini ne sont pas vérifiées.
- Avant publication d'un build contenant un asset, vérifier que le build constitue bien un produit fini et ne distribue pas les sources comme fichiers autonomes.
- Ne jamais affirmer que le projet possède ou a créé les assets Quaternius.

## Preuves et empreintes

Le fichier [quaternius-licences.json](quaternius-licences.json) contient les neuf observations : page QAL, FAQ et sept fiches de pack. Chaque empreinte est le SHA-256 UTF-8, sans retour final, de :

```text
id|url|date_observation|constat_canonique
```

Le manifeste enregistre aussi le SHA-256 du contenu HTML reçu par HTTPS pour chaque page officielle. Ces empreintes protègent l'intégrité du relevé versionné et permettent de détecter une modification ultérieure ; elles ne remplacent pas la copie de la licence incluse dans une future archive. Lors de l'acquisition, le manifeste devra ajouter séparément le SHA-256 de l'archive et celui du fichier de licence reçu.

## Droits retenus sous QAL v1.0

| Usage | Décision |
|---|---|
| Projet personnel, éducatif ou commercial | Autorisé |
| Modification et incorporation au jeu | Autorisées |
| Distribution et vente du jeu fini | Autorisées |
| Attribution | Non requise |
| Travail par un collaborateur ou prestataire | Autorisé uniquement pour ce produit |
| Redistribution d'un asset original ou modifié comme fichier autonome | Interdite |
| Publication des sources dans ce dépôt public ou Git LFS | Interdite par politique conservatrice |
| Réutilisation dans un autre projet par un collaborateur | Non couverte par l'autorisation liée à ce produit |

## Réévaluation obligatoire

Rouvrir la décision avant import si la page de licence change, si le fournisseur répond par écrit, si l'archive contient CC0 ou une autre licence, ou si le mode de distribution rend les fichiers sources directement récupérables.
