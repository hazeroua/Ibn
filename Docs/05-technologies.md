# 05 — Technologies et architecture du reboot

## État actuel

Le seul socle actif du reboot est le prototype `Reboot/Terrain3DValidation/`. Le projet historique dans `Game/`, ses extensions C++ et ses scènes restent présents pour consultation, mais ne sont pas des dépendances autorisées du nouveau projet.

Le ticket #63 déterminera l'emplacement définitif du nouveau projet Godot après validation complète de Terrain3D.

## Versions figées

| Élément | Version ou choix |
|---|---|
| Godot | 4.7.2 stable |
| Terrain3D | 1.1.0 |
| Rendu | Forward+ ; Vulkan et D3D12 évalués |
| Physique cible | Jolt |
| Mise à l'échelle | FSR 2, rendu interne à 67 % |
| Résolution cible | 1 920 × 1 080 |
| Plateforme minimale | Windows, Intel Arc intégrée |
| Langage principal | GDScript typé statiquement |
| Chemins chauds futurs | C++ via GDExtension uniquement si une mesure le justifie |

Les versions sont définies dans `Tools/versions.json`. Elles ne changent pas sans décision explicite.

## Architecture du premier jalon

```text
Reboot/
└── Terrain3DValidation/       Prototype isolé du ticket #62
    ├── project.godot
    ├── main.gd               Génération, parcours, collisions et mesures
    ├── main.tscn
    ├── run-validation.ps1    Import, export et test d'un moteur de rendu
    └── README.md             Protocole et budgets

Docs/                         Sources de vérité et conception durable
Game/                         Ancien projet, non réutilisé automatiquement
Extensions/                   Anciennes extensions, non réutilisées automatiquement
Scripts/                      Ancien pipeline, consultable mais non contractuel pour le reboot
Tools/                        Outils et versions figées partagés
```

## Responsabilités de Terrain3D

Terrain3D doit gérer :

- le relief de 4 × 4 km ;
- les niveaux de détail ;
- les textures de sol ;
- les collisions autour du joueur ;
- l'instanciation future de la végétation et des rochers.

Le relief est déterministe : une même graine et une même version doivent produire le même terrain. Aucun travail lourd ni allocation évitable ne doit être effectué à chaque image.

## Pipeline du prototype

Depuis `Reboot/Terrain3DValidation/` :

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\run-validation.ps1 -Renderer vulkan -ToolchainRoot C:\Projets\IbnKhaldoun
powershell -NoProfile -ExecutionPolicy Bypass -File .\run-validation.ps1 -Renderer d3d12 -ToolchainRoot C:\Projets\IbnKhaldoun
```

Chaque exécution copie localement Terrain3D, importe le projet, produit un export Windows, lance le parcours automatique et écrit dans `reports/` :

- un rapport JSON ;
- le journal Godot ;
- une capture 1 920 × 1 080.

Les artefacts générés ne sont pas versionnés.

## Budgets du ticket #62

| Mesure | Limite |
|---|---:|
| Temps d'image p99 | 16,6 ms maximum |
| Image isolée après préchauffage | moins de 50 ms |
| Appels de rendu | 300 maximum |
| Mémoire vidéo du prototype | 512 Mio maximum |
| Collisions manquées | 0 |
| Erreurs Godot, crashs ou corruption | 0 |
| Durée de validation | 30 secondes par moteur de rendu après 5 s de préchauffage (décision du porteur du projet, 21/11/2026) |

Le rapport doit aussi conserver les temps CPU disponibles, la RAM résidente, les primitives et l'identité du GPU. Godot 4.7 n'expose pas le temps GPU par image : décision documentée pour #62, le temps d'image total (moyenne, p99, pire image) sert de mesure de référence.

## Règles pour le socle neuf

- Aucune dépendance implicite au dossier `Game/` historique.
- Toute réutilisation est examinée composant par composant après #68.
- Les scènes complexes sont générées par script à partir de données versionnées.
- GDScript reste typé et formaté ; le C++ est réservé aux chemins chauds démontrés par profilage.
- Les tests, budgets, captures et exports doivent être exécutables par une commande unique.
- La cible 60 images par seconde dans le pire cas n'est jamais assouplie pour faire passer un test.

## Décisions remplacées

L'ancienne décision d'abandonner Terrain3D reposait sur un crash du rendu logiciel Linux de l'ancien pipeline. Elle ne gouverne plus le projet : le reboot évalue Terrain3D nativement sous Windows sur la machine cible. Les documents et mesures de cette période sont conservés dans `Docs/archive/` uniquement pour l'historique.
