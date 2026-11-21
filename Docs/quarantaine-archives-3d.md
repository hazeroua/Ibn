# Quarantaine des archives 3D

Outil du ticket [#74](https://github.com/hazeroua/Ibn/issues/74). Il inspecte uniquement les archives ZIP avant Blender ou Godot et n'exécute aucun contenu tiers.

## Commande

```powershell
pwsh -NoProfile -File Tools/inspecter-archive-3d.ps1 -Archive Import/pack.zip -Rapport Import/rapports/pack.json
```

Sous Windows PowerShell :

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File Tools/inspecter-archive-3d.ps1 -Archive Import/pack.zip -Rapport Import/rapports/pack.json
```

Codes de sortie :

- `0` : **accepté** — uniquement des formats de données autorisés ;
- `2` : **quarantaine** — structure sûre, mais format complexe à examiner séparément, par exemple Blend ou archive imbriquée ;
- `3` : **refusé** — chemin dangereux, lien, script, exécutable, projet moteur, extension inconnue ou limite dépassée.

Une décision « accepté » signifie seulement que les contrôles automatiques de structure ont réussi. Elle ne valide ni la licence, ni l'authenticité historique, ni la qualité technique de l'asset.

## Garanties

1. le SHA-256 et la taille de l'archive sont calculés avant ouverture ;
2. les membres sont listés avec `ZipArchive` sans Blender, Godot ou shell ;
3. chemins absolus, `../`, segments relatifs, caractères ambigus, noms Windows réservés, collisions de casse et doublons sont refusés ;
4. liens symboliques et points de réanalyse sont refusés ;
5. scripts, exécutables, bibliothèques et projets Godot, Unity ou Unreal sont refusés ;
6. nombre de membres, tailles décompressées et taux de compression sont bornés contre les bombes ZIP ;
7. aucune extraction n'a lieu si un seul membre est refusé ;
8. une archive structurellement sûre est extraite manuellement, membre par membre, dans un dossier temporaire aléatoire ;
9. chaque fichier extrait reçoit un SHA-256 et entre dans l'inventaire ;
10. le dossier temporaire est supprimé avant l'écriture du rapport final ;
11. le rapport ne contient aucun chemin absolu local.

## Formats

Acceptés automatiquement : GLB/glTF et BIN, FBX, OBJ/MTL, images usuelles, KTX/DDS, documents de licence et métadonnées texte/JSON/XML/YAML.

Placés en quarantaine : Blend, PDF, fichiers d'édition complexes (PSD, KRA, XCF) et archives imbriquées.

Refusés : scripts, exécutables, bibliothèques natives, raccourcis, installateurs, projets moteur et toute extension inconnue. Une archive autre que ZIP est refusée : ajouter un extracteur n'est autorisé qu'après une revue de sécurité séparée.

## Limites par défaut

- 8 Gio pour l'archive ZIP avant ouverture ;
- 100 000 membres ;
- 4 Gio par fichier ;
- 20 Gio décompressés au total ;
- taux de compression maximal de 200:1 au-delà de 1 Mio.

Ces limites sont des plafonds de sécurité, pas des budgets de performance ou d'import.

## Tests

```powershell
pwsh -NoProfile -File Tools/tests/test-asset-quarantine.ps1
```

Les archives sont créées synthétiquement dans le dossier temporaire du système puis supprimées. Les cas couvrent archive saine, limite de taille avant ouverture, traversée et chemin absolu, nom Windows réservé, lien symbolique, script inattendu, extension inconnue, PDF, fichier Blend et collision de casse. Deux tests supplémentaires exécutent la commande publique et vérifient ses codes de sortie.
