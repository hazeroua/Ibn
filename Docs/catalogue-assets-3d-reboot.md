# Catalogue des assets 3D du reboot

État au 21 novembre 2026. Ce document recense les ressources candidates pour le reboot Terrain3D. Il ne vaut ni autorisation d'achat, ni autorisation de téléchargement, ni validation historique. Aucun des packs ci-dessous n'a été téléchargé ou exécuté dans le cadre de cette étude.

## Décision immédiate

La première tranche jouable utilise uniquement les familles nécessaires au camp saharien, aux rochers et à la petite oasis. Tunis, Fès et les personnages historiques sont documentés pour plus tard, mais ne doivent pas être intégrés au premier jalon.

Ordre d'évaluation proposé :

1. `Stylized Nature MegaKit` pour les rochers, palmiers, arbustes et plantes ;
2. `Ultimate Stylized Nature Pack` pour compléter les variantes manquantes ;
3. accessoires de camp sélectionnés dans `Fantasy Props MegaKit`, seulement après validation historique ;
4. architecture et personnages dans un jalon ultérieur.

## Suivi GitHub

- [#89 — Pilotage de l'admission des bibliothèques 3D](https://github.com/hazeroua/Ibn/issues/89) : ticket maître et ordre d'exécution ;
- [#67 — Rochers, végétation et oasis](https://github.com/hazeroua/Ibn/issues/67) : deux packs Nature, priorité du jalon Sahara ;
- [#68 — Première boucle jouable](https://github.com/hazeroua/Ibn/issues/68) : accessoires sobres du camp issus du Fantasy Props MegaKit ;
- [#65 — Personnage et caméra](https://github.com/hazeroua/Ibn/issues/65) : bases humanoïdes, vêtements modulaires et animations ;
- [#72 — Architecture de Tunis et Fès](https://github.com/hazeroua/Ibn/issues/72) : évaluation différée des kits 3D Tudor et Medieval Village.

Le backlog détaillé est découpé dans [#73 à #88](https://github.com/hazeroua/Ibn/issues?q=is%3Aissue%20state%3Aopen%20%22%5BASSETS%22) : licences, quarantaine, références historiques, un ticket par pack, conversion Blender, scènes Godot, performances et manifeste de provenance.

## Statut des licences

Les pages individuelles des sept packs Quaternius ci-dessous affichent actuellement **CC0** et autorisent les projets personnels, éducatifs et commerciaux sans attribution. Cependant, la page de licence globale de Quaternius affiche depuis le 28 août 2026 la **Quaternius Asset License (QAL) v1.0** : usage commercial et modification autorisés, sans attribution, mais redistribution des assets seuls interdite.

Cette incohérence doit être levée au moment de l'acquisition. Pour chaque archive, conserver la page du pack, la page de licence datée et le fichier de licence inclus. La licence retenue dans le manifeste sera celle explicitement attachée à la version effectivement obtenue. Tant que cette preuve n'est pas archivée, le statut est « candidat, licence à figer », et non « CC0 confirmé localement ».

Le pack 3D Tudor utilise une licence commerciale propriétaire décrite sur sa fiche : un créateur acheteur peut l'utiliser dans un nombre illimité de projets personnels ou commerciaux et dans des produits finis, mais ne peut pas redistribuer ou revendre les sources comme assets autonomes ou pack concurrent. La fiche ne clarifie pas suffisamment le partage des sources avec une équipe ou des prestataires : le nombre de sièges et les droits des collaborateurs devront être confirmés par écrit avant l'achat. Conserver la facture, la fiche datée et les conditions fournies avec l'achat.

## Catalogue

| Priorité | Ressource officielle | Contenu utile | Formats annoncés | Licence affichée | Décision pour le reboot |
|---|---|---|---|---|---|
| P0 | [Stylized Nature MegaKit](https://quaternius.com/packs/stylizednaturemegakit.html) | Rochers, arbres, plantes et fleurs ; candidat principal pour l'oasis et les zones rocheuses | FBX, OBJ, Blend, glTF | CC0 sur la fiche ; QAL globale à clarifier | Évaluer en premier, en glTF uniquement ; retenir seulement les espèces et silhouettes compatibles avec un Sahara stylisé |
| P0 | [Ultimate Stylized Nature Pack](https://quaternius.com/packs/ultimatestylizednature.html) | Rochers, arbres, plantes, textures et normales ; variantes de complément | FBX, OBJ, Blend, glTF | CC0 sur la fiche ; QAL globale à clarifier | Évaluer après le MegaKit ; éviter les doublons et mesurer le coût des matériaux |
| P1 | [Fantasy Props MegaKit](https://quaternius.com/packs/fantasypropsmegakit.html) | Mobilier, outils, contenants et accessoires pouvant fournir quelques objets de camp | FBX, OBJ, Blend, glTF | CC0 sur la fiche ; QAL globale à clarifier | N'importer que des objets quotidiens plausibles après validation historique ; écarter armes, objets magiques et ornements fantasy |
| P2 | [Arabic Desert City — 3D Tudor](https://3dtudor.itch.io/arabic-desert-city-modular-pack) | 143 objets annoncés : murs, portes, tours, arches, balcons, toits, marché et accessoires | GLB, FBX + textures, Blend, projet UE5 | Licence commerciale propriétaire de la fiche | Achat manuel requis ; différer après le jalon Sahara ; peut servir de kit de prototypage, jamais de preuve d'authenticité pour Tunis ou Fès |
| P2 | [Medieval Village MegaKit](https://quaternius.com/packs/medievalvillagemegakit.html) | Modules de murs, sols, escaliers, toits et accessoires | FBX, OBJ, Blend, glTF | CC0 sur la fiche ; QAL globale à clarifier | Réserve de formes neutres uniquement ; l'étiquette « médiéval » ne le rend pas maghrébin |
| P2 | [Universal Base Characters](https://quaternius.com/packs/universalbasecharacters.html) | Six bases, vingt coiffures, rig humanoïde, environ 13 000 triangles par personnage | FBX, glTF ; Blend et projets moteurs dans l'édition source | CC0 sur la fiche ; QAL globale à clarifier | Bonne base technique possible, mais aucun personnage historique prêt à l'emploi ; morphologie, visages, cheveux et vêtements à redessiner |
| P2 | [Modular Character Outfits — Fantasy](https://quaternius.com/packs/modularcharacteroutfitsfantasy.html) | Douze tenues, 62 pièces modulaires, rig humanoïde | FBX, glTF ; Blend et projets moteurs dans l'édition source | CC0 sur la fiche ; QAL globale à clarifier | Ne pas utiliser comme costume historique complet ; ne conserver éventuellement que des pièces neutres validées |
| P2 | [Universal Animation Library](https://quaternius.com/packs/universalanimationlibrary.html) | Plus de 120 animations humanoïdes : locomotion, actions et poses | FBX, GLB, Blend | CC0 sur la fiche ; QAL globale à clarifier | Déjà référencée par l'ancien projet ; vérifier la provenance et les empreintes existantes avant toute réutilisation dans le reboot |

## Besoins de la première tranche

### Camp saharien

- petites pierres et groupes de rochers servant de repères ;
- jarres, paniers, coffres simples, tapis sobres, sacs et outils non anachroniques ;
- foyer, bois, cordages et structures de tente à produire ou adapter si aucun candidat n'est historiquement satisfaisant ;
- collisions simples et pivots au sol, sans scripts embarqués.

### Petite oasis

- plusieurs silhouettes de palmiers et au moins trois niveaux de détail ;
- arbustes bas, touffes sèches et végétation de rive ;
- rochers de tailles différentes et variantes de teinte ;
- matériaux compatibles avec l'éclairage du projet, idéalement regroupés dans un atlas ;
- densité testée avec l'instanciation de Terrain3D sans modifier Terrain3D lui-même.

### Architecture ultérieure : Tunis et Fès

Les kits `Arabic Desert City` et `Medieval Village` ne sont que des bibliothèques de formes. Avant production, les modules devront être comparés à des références sourcées de Tunis et de Fès au XIVe siècle : morphologie des rues, murs, portes, patios, matériaux, couvertures, ouvertures, éléments religieux et décor. Tout élément seulement « arabe », « désertique », « médiéval » ou « fantasy » reste non validé.

### Personnages ultérieurs

Les personnages Quaternius peuvent servir de base de rig ou de test de performance, mais pas de représentation d'Ibn Khaldoun ni des populations du Maghreb médiéval. Les visages, proportions, coiffures, tenues, accessoires, couleurs et statuts sociaux nécessitent une direction artistique et une validation historique séparées.

## Sécurité : peut-on les utiliser localement ?

Un modèle 3D n'est pas à « exécuter ». Les fichiers de données issus d'une source officielle peuvent être **inspectés puis importés**, mais aucun pack ne doit être déclaré sûr sur la seule foi de sa page web.

Niveau de confiance proposé :

| Type de contenu | Risque relatif | Politique |
|---|---|---|
| GLB/glTF, FBX, OBJ et images provenant de la fiche officielle | Faible à modéré | Acceptable après contrôle de l'archive, empreinte SHA-256, antivirus et import dans une copie isolée du projet |
| Fichier `.blend` | Modéré | Ouvrir uniquement avec l'exécution automatique Python désactivée, par exemple Blender avec `--factory-startup --disable-autoexec`, sans accepter d'activer les scripts |
| Projet Godot, Unity ou Unreal, add-on, script, shader complexe ou générateur fourni | Élevé | Ne pas ouvrir ni exécuter dans l'environnement principal ; extraire uniquement les données nécessaires après revue manuelle |
| Archive 3D Tudor non encore acquise | Inconnu | Ne pas acheter ou télécharger sans autorisation ; privilégier les deux GLB ou `FBX & Textures`, éviter initialement le projet UE5 et les fichiers Blend |

Même les formats de données passent par des parseurs Blender ou Godot et ne sont donc jamais sans risque. La réputation du fournisseur et HTTPS réduisent le risque de chaîne d'approvisionnement, mais ne remplacent pas le contrôle local.

## Procédure d'admission d'une archive

1. Obtenir l'autorisation explicite avant téléchargement ou achat.
2. Télécharger uniquement depuis la fiche officielle ; ne pas utiliser de miroir inconnu.
3. Placer l'archive dans une zone de quarantaine hors du projet actif.
4. Enregistrer URL finale, date, taille, nom exact et SHA-256 avant extraction.
5. Lister l'archive sans l'ouvrir dans Blender ou Godot ; refuser exécutables, scripts inattendus, liens symboliques et chemins sortant du dossier d'extraction.
6. Scanner l'archive et son contenu avec les protections disponibles sur la machine.
7. Préférer GLB/glTF, puis FBX/OBJ et textures. Ne jamais lancer un exécutable ou script fourni par le vendeur.
8. Inspecter géométrie, matériaux, textures, unités, axes, pivots, squelette et animations dans une copie isolée avec réseau coupé et auto-exécution désactivée.
9. Convertir avec un script Blender écrit et relu dans ce dépôt ; ne pas exécuter de script tiers.
10. Importer seulement les fichiers retenus dans le nouveau projet, puis mesurer triangles, appels de rendu, mémoire, collisions, LOD et performances Intel Arc.

La validation technique n'autorise pas la publication des sources. Seuls les assets dont la licence permet explicitement la redistribution des fichiers sources peuvent être versionnés dans le dépôt GitHub public. Les sources QAL ou 3D Tudor restent hors Git, y compris hors de `Game/` et du futur projet ; avant toute distribution du jeu, vérifier aussi les conditions applicables aux fichiers dérivés et la possibilité d'extraire les assets du produit fini.

## Manifeste de provenance

Chaque ressource admise doit avoir une entrée contenant au minimum :

```yaml
id: identifiant-stable
nom: Nom du pack et de l'objet
fournisseur: Quaternius ou 3D Tudor
url_source: https://...
date_acquisition: YYYY-MM-DD
fichier_source: archive-ou-fichier.ext
sha256_source: ...
licence: nom et version exactement constatés
preuve_licence: chemin vers copie datée contenant URL et texte intégral de la fiche et du fichier de licence
autorisation: référence de l'accord d'achat ou de téléchargement
formats_recus: [glb]
fichiers_retenus: []
transformations: []
outil_conversion: Blender 5.x, script et commit
validation_historique: non_requise | en_attente | validee
validation_securite: en_attente | validee
validation_performance: en_attente | validee
```

## Sources de licence à archiver

- [Licence globale Quaternius — QAL v1.0](https://quaternius.com/license.html)
- [FAQ Quaternius — déclaration CC0](https://quaternius.com/faq.html)
- [Fiche et conditions commerciales 3D Tudor](https://3dtudor.itch.io/arabic-desert-city-modular-pack)
