# 00 — Installation

> **Tu ne fais presque rien** : tu récupères le projet, tu demandes à Claude Code de lancer le script d'installation, et tu acceptes une fenêtre d'autorisation Windows. Le script installe, vérifie et enregistre tout.

## 1. Récupérer le projet

Dans PowerShell :

```powershell
git clone https://github.com/hazeroua/Ibn.git C:\Projets\IbnKhaldoun
```

Un chemin court, **en dehors de OneDrive** (les dossiers synchronisés posent des problèmes avec Git et Godot).

## 2. Lancer l'installation

Ouvre Claude Code dans `C:\Projets\IbnKhaldoun` et écris :

> Lance `Tools/installer.ps1` et vérifie que tout est installé.

Ou directement :

```powershell
powershell -ExecutionPolicy Bypass -File C:\Projets\IbnKhaldoun\Tools\installer.ps1
```

Le script peut être relancé autant de fois que nécessaire : il n'installe que ce qui manque. Il est vérifié à chaque envoi par la CI (Windows PowerShell 5.1).

## Ce qui est installé

**Outils système (winget), s'ils manquent :**

| Outil | Rôle |
|---|---|
| Git + Git LFS | Historique du projet, gros fichiers |
| Python | Outils de compilation et d'analyse |
| Visual Studio Build Tools | Compilateur C++ (MSVC), sans l'éditeur complet (environ 6 à 8 Go) |
| Blender | Modèles 3D par script |

**Dépendances du projet, aux versions figées de `Tools/versions.json` (`Tools/dependances.ps1`) :**

| Dépendance | Version | Où |
|---|---|---|
| Godot (portable) | 4.7.2 | `Tools/godot/` |
| Modèles d'export Godot | 4.7.2 | `%APPDATA%\Godot\export_templates\` (environ 1 Go) |
| godot-cpp | branche 4.5 (compatible Godot 4.5 et suivants) | `Extensions/godot-cpp/` |
| SCons | 4.11.1 | environnement Python dédié `Tools/venv/` |
| gdtoolkit (gdlint, gdformat) | 4.5.0 | `Tools/venv/` |
| GUT (tests) | 9.7.1 | `Game/addons/gut/` |
| Dialogue Manager | 4.2.0 | `Game/addons/dialogue_manager/` |
| Terrain3D | 1.1.0 | `Game/addons/terrain_3d/` |

**Total : environ 10 Go.** À la fin, le script écrit **`Tools/outils.json`** (chemins et versions réellement installés), que tous les scripts du pipeline utilisent.

## Ta seule intervention

Pendant l'installation de **Visual Studio Build Tools** ou de **Blender**, Windows peut afficher *« Voulez-vous autoriser cette application à apporter des modifications ? »* → **Oui**.

## 3. Essayer

```powershell
C:\Projets\IbnKhaldoun\lancer.bat
```

La première fois, le lancement compile l'extension C++, télécharge la texture du sol, importe le projet et construit la scène, puis ouvre le bac à sable. Caméra libre : déplacement avec Z Q S D, E pour monter et A pour descendre, Maj pour accélérer, clic droit maintenu pour regarder, Échap pour quitter. La manette fonctionne aussi.

## Versions figées

Godot et les dépendances ne changent **jamais** sans décision explicite : `Tools/versions.json` fait foi, et la CI vérifie le projet avec exactement ces versions.

## En cas de problème

Claude Code lit le message d'erreur, corrige et relance. Cas prévus :
- **winget absent** : installer « App Installer » depuis le Microsoft Store.
- **Un téléchargement interrompu** : relancer le script, il reprend où il en était.
- **godot-cpp sur une mauvaise branche** : le script le détecte et indique de supprimer `Extensions/godot-cpp` avant de relancer.
