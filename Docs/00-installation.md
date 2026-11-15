# 00 — Installation

> **Tu ne fais presque rien** : tu demandes à Claude Code de lancer le script d'installation, et tu acceptes une fenêtre d'autorisation Windows. Le script installe, vérifie et enregistre tout.

## Où mettre le projet

`C:\Projets\IbnKhaldoun` : un chemin court, **en dehors de OneDrive** (les dossiers synchronisés posent des problèmes avec Git et Godot).

```
C:\Projets\IbnKhaldoun\
├── CLAUDE.md
├── Docs\        ← ce dossier de conception
└── Tools\
    └── installer.ps1
```

## La commande

Ouvre Claude Code dans `C:\Projets\IbnKhaldoun` et écris :

> Lance `Tools/installer.ps1` et vérifie que tout est installé.

Ou, dans PowerShell :

```powershell
powershell -ExecutionPolicy Bypass -File C:\Projets\IbnKhaldoun\Tools\installer.ps1
```

Le script peut être relancé autant de fois que nécessaire : il n'installe que ce qui manque.

## Ce qui est installé

| Outil | Rôle | Où | Taille approx. |
|---|---|---|---|
| **Git + Git LFS** | Historique du projet, gros fichiers | Déjà présent / winget | — |
| **Godot 4** (portable) | Le moteur | `Tools\godot\` | ~ 100 Mo |
| **Modèles d'export Godot** | Créer la version jouable `.exe` | `%APPDATA%\Godot\export_templates\` | ~ 1 Go |
| **godot-cpp** | Bibliothèque pour le C++ (GDExtension), même version que Godot | `Extensions\godot-cpp\` | ~ 100 Mo |
| **Python + SCons** | Compilation de l'extension C++ | Python déjà présent ; SCons via pip | ~ 10 Mo |
| **Visual Studio Build Tools** | Compilateur C++ (MSVC), sans l'éditeur complet | winget | ~ 6 à 8 Go |
| **Blender** | Modèles 3D par script | winget | ~ 1 Go |
| **Terrain3D** | Grands terrains | `Game\addons\terrain_3d\` | ~ 50 Mo |
| **Dialogue Manager** | Dialogues | `Game\addons\dialogue_manager\` | < 10 Mo |
| **GUT** | Tests automatisés | `Game\addons\gut\` | < 10 Mo |

**Total : environ 10 Go.**

À la fin, le script écrit **`Tools\outils.json`** : chemins et versions de chaque outil. Claude Code s'en sert ensuite pour toutes ses commandes.

## Ta seule intervention

Pendant l'installation de **Visual Studio Build Tools** (et parfois de **Blender**), Windows affiche *« Voulez-vous autoriser cette application à apporter des modifications ? »* → **Oui**.

## Version de Godot figée

La première installation prend **la dernière version stable de Godot 4** et l'enregistre dans `outils.json`. Ensuite, **on ne change plus de version** sans décision explicite, pour éviter que le projet casse.

## Déjà en place sur la machine (vérifié le 15/11/2026)

- Git ✅
- Python ✅
- Claude Code ✅
- Epic Games Launcher : plus nécessaire depuis le passage à Godot (tu peux le désinstaller si tu veux).

## En cas de problème

Claude Code lit le message d'erreur, corrige et relance. Les cas prévus :
- **winget absent** : installer « App Installer » depuis le Microsoft Store.
- **Limite de requêtes GitHub** atteinte (rare) : attendre une heure, ou définir la variable `GITHUB_TOKEN`.
- **Plugin incompatible** avec la version de Godot : Claude Code installe la version du plugin qui correspond.
