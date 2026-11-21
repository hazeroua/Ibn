# Reprise du projet autour de Terrain3D

Décision du 21 novembre 2026 : le projet est reconstruit depuis zéro sur une base neuve, avec Terrain3D comme fondation du monde extérieur. L'ancien projet reste conservé uniquement comme archive et source éventuelle d'éléments sélectionnés après validation du nouveau socle. Aucun fichier existant n'est supprimé ou déplacé pendant cette phase.

## Objectif du premier jalon

Obtenir une tranche jouable courte mais soignée dans le Sahara : un personnage peut parcourir à pied un terrain crédible, rejoindre une petite oasis et revenir au point de départ, avec une image stable à 60 images par seconde en 1080p avec FSR 2 sur la puce Intel Arc intégrée de la machine de développement.

Le premier jalon ne comprend ni Tunis, ni foule, ni missions historiques complexes. Il valide d'abord le terrain, la direction artistique, la caméra et les performances.

## Règles du redémarrage

- Terrain3D est la source de vérité du relief, des textures de sol, des collisions et du placement de la végétation du désert.
- Le nouveau socle est construit à côté de l'ancien jusqu'à validation de Terrain3D sur Windows et dans l'export du jeu.
- Aucun ancien système n'est repris automatiquement. Chaque réutilisation doit être justifiée par une mesure ou un gain clair.
- La cible minimale reste Windows, 1080p, 60 images par seconde, sur Intel Arc intégrée.
- Chaque ticket produit une scène essayable, des tests et des mesures reproductibles.
- Les tickets sont réalisés dans l'ordre ci-dessous. Les tickets 3 et 4 peuvent avancer en parallèle après le ticket 2.

## Tickets du jalon « Reboot Terrain3D »

### 1. [Valider Terrain3D sur la machine cible](https://github.com/hazeroua/Ibn/issues/62)

Créer un projet Godot minimal séparé, installer Terrain3D 1.1.0, générer un terrain de 4 × 4 km, activer collisions et niveaux de détail, puis vérifier l'éditeur, le jeu, l'export Windows et une session de déplacement de 30 minutes.

Critères d'acceptation :

- aucun plantage, erreur Godot ou corruption du terrain ;
- terrain, collisions et textures visibles dans l'export Windows ;
- rapport comparant Vulkan et D3D12 sur Intel Arc ;
- mesure du temps CPU, du temps GPU, de la mémoire et des images par seconde ;
- décision écrite : continuer avec Terrain3D ou arrêter le reboot avant d'investir davantage.

### 2. [Créer le socle neuf du projet](https://github.com/hazeroua/Ibn/issues/63)

Créer le nouveau projet Godot autour de Terrain3D avec démarrage, configuration graphique, entrées, journalisation, tests, export Windows et pipeline de validation. Conserver l'ancien projet sans le modifier.

Critères d'acceptation :

- démarrage direct dans une scène de test Terrain3D ;
- configuration 1080p, FSR 2, Forward+ et Jolt documentée ;
- commande unique pour tester, mesurer et exporter ;
- versions de Godot et Terrain3D figées ;
- aucune dépendance au code de l'ancien jeu.

### 3. [Construire le terrain saharien](https://github.com/hazeroua/Ibn/issues/64)

Créer un terrain de 4 × 4 km composé de dunes, zones pierreuses, oueds secs et reliefs rocheux, avec des transitions naturelles et des repères visuels permettant de s'orienter.

Critères d'acceptation :

- heightmap déterministe générée par script ;
- matériaux sable, roche et terre sèche avec variation à grande échelle ;
- absence de répétition visuelle évidente depuis le sol ;
- collisions stables à pied et à vitesse élevée ;
- niveaux de détail sans trous ni sauts visibles gênants.

### 4. [Refaire le personnage et la caméra](https://github.com/hazeroua/Ibn/issues/65)

Créer un contrôleur troisième personne neuf pour la marche, la course, les pentes et les collisions, accompagné d'une caméra fluide adaptée aux dunes et aux zones rocheuses.

Critères d'acceptation :

- clavier, souris et manette ;
- déplacement stable sur les pentes et les changements de niveau de détail ;
- caméra sans traversée du terrain ni secousse ;
- animation et sons de pas liés au type de sol ;
- aucun code repris de l'ancien contrôleur sans validation explicite.

### 5. [Définir l'identité visuelle du Sahara](https://github.com/hazeroua/Ibn/issues/66)

Créer la lumière, le ciel, la brume sèche, le vent et la poussière dans un style stylisé haut de gamme, lisible sur la machine cible.

Critères d'acceptation :

- trois moments réglés : matin, midi et fin de journée ;
- palette et références visuelles documentées ;
- effet de chaleur et poussière sans dégrader la lisibilité ;
- budget GPU respecté dans le pire point de vue du terrain.

### 6. [Ajouter rochers, végétation et oasis](https://github.com/hazeroua/Ibn/issues/67)

Utiliser le système d'instanciation de Terrain3D pour répartir rochers, herbes sèches, arbustes et palmiers, puis construire une petite oasis servant de destination au joueur.

Critères d'acceptation :

- distribution cohérente selon pente, altitude et humidité ;
- niveaux de détail et imposteurs pour chaque famille d'objets ;
- eau, rive et palmeraie visuellement cohérentes ;
- densité maximale testée sans allocations par image ni chute sous le budget.

### 7. [Livrer la première boucle jouable](https://github.com/hazeroua/Ibn/issues/68)

Assembler le terrain, le personnage, l'ambiance et l'oasis dans un parcours de dix minutes : partir d'un camp, s'orienter grâce au paysage, atteindre l'oasis et revenir.

Critères d'acceptation :

- parcours compréhensible sans interface envahissante ;
- sauvegarde et reprise au camp ;
- sons d'ambiance et retour visuel cohérents ;
- session automatisée de 30 minutes sans fuite mémoire ;
- export Windows jouable et rapport final de performances.

## Dépendances

```text
1 Validation Terrain3D
└── 2 Socle neuf
    ├── 3 Terrain saharien ──┐
    └── 4 Joueur et caméra ──┼── 7 Première boucle jouable
        5 Identité visuelle ─┤
        6 Oasis et végétation┘
```

## Sort de l'ancien projet

L'ancien projet n'est ni supprimé ni fusionné dans le nouveau pendant ce jalon. Après la réussite du ticket 7, un ticket distinct décidera quels éléments conserver : scénario, données historiques, cheval, sons, modèles et outils de génération. Cette sélection se fera composant par composant.
