# Validation Terrain3D

Prototype isolé du ticket 1 du reboot. Il génère un terrain Terrain3D de 4 × 4 km, déplace une caméra à 70 m/s pendant 30 minutes, vérifie les collisions chaque seconde et écrit les mesures dans `reports/terrain3d-validation.json`.

La mesure est précédée de cinq secondes de préchauffage exclues des statistiques. Une capture PNG est écrite à côté de chaque rapport.

## Pire cas testé

- terrain actif de 4 096 × 4 096 mètres à deux mètres entre sommets ;
- seize régions physiques de 1 024 × 1 024 mètres ;
- déplacement continu à 70 m/s sur un cercle de 3,5 km de diamètre ;
- collision dynamique mise à jour autour de la caméra ;
- rendu 1 920 × 1 080 avec FSR 2 à 67 % ;
- session de 30 minutes sans rechargement de scène.

## Commandes

Depuis ce dossier :

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\run-validation.ps1 -Renderer vulkan -ToolchainRoot C:\Projets\IbnKhaldoun
powershell -NoProfile -ExecutionPolicy Bypass -File .\run-validation.ps1 -Renderer d3d12 -ToolchainRoot C:\Projets\IbnKhaldoun
```

Pour une vérification rapide d'intégration, ajouter `-DurationSeconds 30`.

## Budgets de décision

- p99 de l'image inférieur ou égal à 16,6 ms ;
- aucune image supérieure ou égale à 50 ms après préchauffage ;
- au plus 300 appels de dessin et 512 Mio de mémoire vidéo pour ce prototype ;
- aucune collision manquée, erreur, corruption ou fuite sur 30 minutes ;
- comparaison Vulkan et D3D12 sur le même export, le même parcours et la même graine.
