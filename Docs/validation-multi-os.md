# Validation du jeu sous Windows, macOS et Linux (ticket #99)

Ce document explique **comment** la commande de validation du jeu (`Projet/outils/valider.ps1`) a été rendue identique sur les trois systèmes, **ce qui diffère** d'un système à l'autre, et **où chercher** en cas de panne. Il sert de carnet de bord : chaque choix y est justifié pour qu'un bug puisse être compris sans relire tout le script.

> Rappel : la machine cible du jeu et des budgets reste **Windows sur Intel Arc intégrée**. macOS et Linux servent à développer et à jouer ; leurs mesures sont enregistrées mais ne bloquent pas la validation (voir « Budgets »).

## État au 22 novembre 2026

| Système | Validation sans mesure | Mesure | Export | Comment c'est vérifié |
|---|---|---|---|---|
| Windows x64 | oui | oui | oui (`Windows Desktop`) | `valider.bat` sur la machine du porteur du projet (Windows PowerShell 5.1) |
| Linux x64 | oui | oui (projet lancé par Godot) | pas encore : préréglage `Linux` au ticket #101 | essayé dans un conteneur Ubuntu 24.04 avec PowerShell 7.5 (voir « Essais ») |
| macOS (Apple silicon, Intel) | écrit, **jamais essayé** | écrit, **jamais essayé** | pas encore : préréglage `macOS` au ticket #100 | aucun Mac disponible ; à confirmer au ticket #100 |

## Lancer la validation

| Système | Commande |
|---|---|
| Windows | double-clic sur `Projet/valider.bat` (inchangé) |
| macOS, Linux | `pwsh -NoProfile -File Projet/outils/valider.ps1` (les lanceurs à double-clic arrivent avec #100 et #101) |

Options ajoutées par ce ticket (les anciennes sont inchangées) :

| Option | Effet | Pour qui |
|---|---|---|
| `-Renderer <pilote>` | `vulkan`, `d3d12`, `metal` ou `opengl3`. **Vide par défaut** : le script choisit le pilote du système (tableau ci-dessous). | tous |
| `-SansExport` | n'exporte pas le jeu et ne mesure pas | machines sans modèles d'export (CI Windows) |
| `-BudgetsBloquants` | rend les budgets bloquants hors de Windows | quand des budgets macOS ou Linux auront été décidés |
| `-SansSon` | lance la mesure avec `--audio-driver Dummy` | machines sans carte son (CI Linux, conteneurs) |

## Ce qui change d'un système à l'autre

Toute la logique est commune. Les différences sont rassemblées **en un seul endroit**, la table `$PlatformSpecs` au début de `valider.ps1` :

| | Windows | Linux | macOS |
|---|---|---|---|
| Préréglage d'export | `Windows Desktop` | `Linux` (#101) | `macOS` (#100) |
| Fichier lancé pour la mesure | `build/IbnKhaldoun.exe` | `build/IbnKhaldoun.x86_64` | `build/IbnKhaldoun.app/Contents/MacOS/IbnKhaldoun` |
| Fichiers exigés à côté | `IbnKhaldoun.pck`, `libterrain.windows.release.x86_64.dll` | `IbnKhaldoun.pck`, `libterrain.linux.release.x86_64.so` | aucun (tout est dans le `.app`) |
| Pilotes de rendu acceptés (le premier par défaut) | vulkan, d3d12, opengl3 | vulkan, opengl3 | Apple silicon : metal, vulkan, opengl3 ; Intel : vulkan, opengl3 |
| gdlint et gdformat | `Tools/venv/Scripts/*.exe` | `Tools/venv/bin/*` | `Tools/venv/bin/*` |

### Détection du système

- `$OnWindows` : `[Environment]::OSVersion.Platform -eq Win32NT`. On n'utilise **pas** `$IsWindows`, qui n'existe pas dans Windows PowerShell 5.1 (celui de `valider.bat`).
- `$OnMacOS` : `RuntimeInformation.IsOSPlatform(OSX)`, évalué seulement hors de Windows.
- Architecture : `PROCESSOR_ARCHITECTURE` sous Windows (`x64` ou `arm64`), `RuntimeInformation.OSArchitecture` ailleurs.
- Metal n'existe dans Godot 4.7 que sur Apple silicon : sur un Mac Intel, la liste des pilotes devient `vulkan, opengl3` (Vulkan passe par MoltenVK, inclus dans Godot).

### Outils (Godot, gdtoolkit, Blender)

- **Godot** : chemin `godot.console` de `Tools/outils.json`, écrit par `Tools/dependances.ps1` pour chaque système (sous macOS, c'est le binaire dans `Godot.app/Contents/MacOS/`). Nouveau contrôle : si `outils.json` a été écrit sous un autre système (champ `plateforme`), la validation s'arrête et demande de relancer l'installateur, au lieu d'échouer plus loin sur un chemin introuvable.
- **gdtoolkit** : dans `Tools/venv`, sous `Scripts/` (Windows) ou `bin/` (macOS, Linux) ; sa présence est vérifiée avant l'analyse.
- **Blender** (préparation du personnage, #65), cherché dans cet ordre :
  1. `blender.chemin` de `Tools/outils.json` (écrit par `Tools/installer.ps1` sous Windows, `Tools/installer-macos.ps1` sous macOS, et par la CI) ;
  2. macOS : `Tools/blender/Blender.app/…` puis `/Applications/Blender.app/Contents/MacOS/Blender` ; Linux : `Tools/blender/blender` ;
  3. la commande `blender` du PATH.

### Lancement du jeu pour la mesure

Avant : `Start-Process` avec des guillemets ajoutés à la main autour des chemins. Sous macOS et Linux, ces guillemets risquaient d'arriver tels quels au jeu. Maintenant, la fonction `Start-Game` crée le processus directement (`System.Diagnostics.Process`, sans passer par un interpréteur) :

- PowerShell 7 (macOS, Linux, CI) : chaque argument est transmis séparément (`ArgumentList`), aucun problème d'espaces ou de guillemets ;
- Windows PowerShell 5.1 (`valider.bat`) : `ArgumentList` n'existe pas ; les arguments sont joints, et ceux qui contiennent un espace sont mis entre guillemets.

Différence visible : sous macOS et Linux, la sortie de Godot apparaît dans le terminal de la validation (le journal complet reste dans `jeu.log`).

### Export absent : la mesure lance le projet

Tant que le préréglage du système n'existe pas dans `Projet/export_presets.cfg` (cas de macOS et Linux jusqu'aux tickets #100 et #101), l'étape 7 l'annonce et la mesure lance **le projet avec Godot** (`godot --path Projet …`) : mêmes scènes, même sonde, mêmes rapports et captures. Dès que le préréglage sera ajouté, l'export et la mesure de la version exportée se feront sans autre changement du script.

## Budgets

- **Windows** : bloquants, comme avant.
- **macOS, Linux** : les dépassements sont affichés en rouge (`DÉPASSEMENT : …`), suivis d'une ligne jaune « Budgets non bloquants sous … », et la validation continue. `-BudgetsBloquants` les rend bloquants.
- Chaque `rapport.json` indique désormais :
  - `os_name`, `os_version`, `cpu_architecture`, `processor_name` (écrits par le jeu, `core/perf/performance_probe.gd`) ;
  - `validation_platform` (ex. `linux-x64`) et `budgets_blocking` (écrits par `valider.ps1`).

## Erreurs dans les journaux

La règle ne change pas : toute ligne `ERROR:`, `SCRIPT ERROR:` ou `CRASH` d'un journal Godot fait échouer la validation, sur les trois systèmes. Seul cas rencontré hors Windows : sans carte son, Godot écrit `ERROR: … ERR_CANT_OPEN … audio_driver_alsa.cpp`. On ne filtre pas ce message : l'option `-SansSon` démarre le jeu avec le pilote son « Dummy », qui ne cherche aucun périphérique.

## CI GitHub (`.github/workflows/ci.yml`)

Réécrite pour valider `Projet/` (l'ancien pipeline `Scripts/Pipeline/` n'y est plus) :

| Tâche | Ce qu'elle fait |
|---|---|
| `windows` | `Tools/dependances.ps1 -SansModelesExport`, Blender portable, puis `valider.ps1 -SansExport` avec **Windows PowerShell 5.1**, comme `valider.bat`. Pas d'export ni de mesure : les machines GitHub n'ont pas de carte graphique. |
| `linux` | Mesa (rendu logiciel), Xvfb, `dependances.ps1`, Blender portable, puis validation complète avec `-Renderer opengl3 -SansSon -DurationSeconds 10 -WarmupSeconds 1`. Les captures et rapports sont joints au résultat. |

- Blender de la CI : version fixée dans le fichier (`BLENDER_VERSION`, 5.0.1), archive officielle de download.blender.org ; son chemin est ajouté à `Tools/outils.json`.
- **Attention : la CI est désactivée dans les réglages du dépôt** (« disabled manually »). Le fichier est prêt, mais il ne tournera qu'une fois réactivé (onglet Actions de GitHub). Il n'a donc jamais tourné sur GitHub.
- L'ancienne tâche macOS de la CI (compilation C++ de l'ancien projet) est retirée ; la CI macOS du nouveau jeu fait partie du ticket #100.

## Essais réalisés

Dans un conteneur Ubuntu 24.04 (x86_64, sans carte graphique ni carte son), PowerShell 7.5.4, Godot 4.7.2 Linux :

1. `valider.ps1 -SansMesure` : dépendances, 22 fichiers de ressources vérifiés, personnage préparé par Blender 5.0.1, gdlint et gdformat, import, construction, **164 tests GUT réussis**, étape 7 « préréglage Linux absent ». Validation réussie (362 s).
2. `xvfb-run valider.ps1 -Scene terrain_test -Renderer opengl3 -DurationSeconds 10 -WarmupSeconds 1` : échec sur `ERROR: … audio_driver_alsa.cpp` (pas de carte son), d'où l'option `-SansSon`.
3. La même commande avec `-SansSon` : mesure réussie (rendu logiciel, 7 i/s), système affiché « Linux 24.04 (x86_64) », dépassements affichés sans bloquer, validation réussie.

Limites de ces essais : Blender y était le module `bpy` 5.0.1 appelé par un petit script se faisant passer pour `blender` (le conteneur ne peut pas télécharger Blender) ; GUT a été copié à la main, car le conteneur ne peut pas joindre l'adresse de téléchargement de GUT. Rien n'a été essayé sous macOS.

## En cas de bug : où regarder

| Symptôme | Cause probable | Où |
|---|---|---|
| « Tools/outils.json a été écrit sous windows, pas sous linux » | `outils.json` copié d'une autre machine | relancer l'installateur du système |
| « gdtoolkit absent : …/Tools/venv/bin/gdlint » | `Tools/venv` absent ou créé sous un autre système | `Tools/dependances.ps1` |
| « Pilote de rendu « metal » indisponible » | Mac Intel, ou `-Renderer` erroné | table `$PlatformSpecs`, ajustement Mac Intel juste après |
| « Blender introuvable » | Blender ni dans `outils.json`, ni aux emplacements habituels, ni dans le PATH | `Resolve-Blender` |
| Le jeu reçoit des chemins tronqués ou entre guillemets | passage des arguments | `Start-Game` (deux branches : PowerShell 7 / 5.1) |
| « Export incomplet : … absent » sous macOS ou Linux | préréglage ajouté mais noms de fichiers différents | `Executable` et `Required` dans `$PlatformSpecs` |
| `ERROR: … audio_driver_alsa.cpp` (ou CoreAudio) | machine sans sortie son | option `-SansSon` |
| Mesure très lente sous Linux | rendu logiciel (llvmpipe) | normal sans carte graphique ; budgets non bloquants |

## Fichiers modifiés

- `Projet/outils/valider.ps1` : détection du système, `$PlatformSpecs`, `Resolve-Blender`, `Start-Game`, `Test-ExportPreset`, options `-Renderer` (vide par défaut), `-SansExport`, `-BudgetsBloquants`, `-SansSon`, budgets non bloquants hors Windows, champs ajoutés aux rapports.
- `Projet/core/perf/performance_probe.gd` : `os_name`, `os_version`, `cpu_architecture`, `processor_name` dans le rapport.
- `.github/workflows/ci.yml` : validation de `Projet/` sous Windows et Linux.
- `.gitignore` : `Tools/blender/` (Blender portable de la CI ou des postes).
- Documentation : ce fichier, `Docs/README.md`, `Docs/05-technologies.md`, `Projet/README.md`.
