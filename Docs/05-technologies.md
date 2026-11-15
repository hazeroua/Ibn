# 05 — Technologies

## Contraintes

1. **Tout se fait avec Claude Code** : le porteur du projet ne manipule rien, sauf télécharger certaines ressources graphiques.
2. **Le plus open source possible.**
3. **Le plus optimisé possible**, dans le pire cas (règle absolue de `CLAUDE.md`).
4. **La machine de développement n'a pas de carte graphique dédiée** : Intel Core Ultra 7 avec puce graphique intégrée Intel Arc.

## Décision : Godot 4 (15/11/2026)

Unreal Engine 5 a été écarté : sans carte graphique dédiée, ses atouts (Nanite, Lumen) sont inutilisables, son éditeur est très lourd, et ses fichiers binaires empêchent Claude Code de tout faire.

| Critère | Godot 4 |
|---|---|
| Licence | **MIT : 100 % open source**, sans redevance |
| Tourne sur une puce intégrée | **Oui**, éditeur comme jeu |
| Pour Claude Code | **Excellent** : scènes (`.tscn`), ressources (`.tres`), shaders et réglages sont des **fichiers texte** ; tout se pilote en ligne de commande |
| Performance maximale | Code critique en **C++ via GDExtension** |
| Limite connue | Le streaming de grands mondes et les foules ne sont pas intégrés : **on les code nous-mêmes en C++** |

**Conséquence importante :** la machine de développement **est** la configuration minimale. Si le jeu tourne bien dessus, il tournera bien chez presque tout le monde.

## Direction visuelle qui découle de ce choix

On ne vise pas le photoréalisme d'Assassin's Creed. On vise un **style stylisé haut de gamme** : lumière très travaillée, couleurs fortes, matières peintes. C'est beau, ça vieillit bien, et ça reste léger (voir `03-game-design.md`, Direction artistique).

## La stack

| Besoin | Outil | Licence |
|---|---|---|
| Moteur | **Godot 4** (dernière version stable, version figée pour le projet) | MIT |
| Gameplay | **GDScript typé statiquement** (types obligatoires partout) | — |
| Code critique (foules, streaming, génération, simulation) | **C++ via GDExtension** (`godot-cpp`) | MIT |
| Compilation C++ | **Visual Studio Build Tools** (compilateur MSVC seul) + **SCons** (Python) | Gratuit / MIT |
| Physique | **Jolt** (intégré à Godot) | MIT |
| Terrains | **Terrain3D** (plugin) : grands terrains, niveaux de détail, végétation instanciée | MIT |
| Dialogues | **Dialogue Manager** (plugin) : dialogues en fichiers texte | MIT |
| Tests automatisés | **GUT** (plugin), en ligne de commande | MIT |
| Modèles 3D | **Blender** en ligne de commande (scripts Python) | GPL |
| Personnages humains | **MPFB** (MakeHuman pour Blender) : génération de personnages par script | Sorties CC0 |
| Textures, ciels | **Poly Haven** | CC0 |
| Modèles, animaux, animations | **Quaternius**, **Kenney** ; éventuellement **Mixamo** (téléchargement manuel) | CC0 / gratuit |
| Sons | **Freesound** (filtre CC0) | CC0 |
| Versionnage | **Git + Git LFS** | Open source |
| Agent | **Claude Code** | — |

L'installation est décrite dans `00-installation.md` et automatisée par `Tools/installer.ps1`.

## Rendu et optimisation pour une puce intégrée

| Sujet | Choix |
|---|---|
| Moteur de rendu | **Forward+** (Vulkan ou Direct3D 12) |
| Résolution | Rendu interne mis à l'échelle avec **FSR 2** |
| Lumière globale | Éclairage du ciel + **SSAO/SSIL** réglables ; **VoxelGI** pour les intérieurs importants ; pas de SDFGI par défaut (trop coûteux) |
| Ombres | Une lumière directionnelle (soleil/lune) avec cascades réglées au plus juste ; lumières locales sans ombre sauf exception |
| Brouillard et poussière | Brouillard volumétrique de faible résolution, ou brouillard de profondeur selon la qualité choisie |
| Géométrie | **Niveaux de détail automatiques** + **imposteurs** pour le lointain ; **MultiMeshInstance3D** pour tout ce qui se répète (végétation, pierres, tuiles, foule lointaine) |
| Occlusion | **Occlusion culling** dans les médinas (les murs cachent énormément) |
| Personnages | Trois niveaux : proches (squelette complet), moyens (squelette simplifié, animation à fréquence réduite), lointains (**textures d'animation de sommets** en MultiMesh) |
| Matériaux | Peu de matériaux, partagés ; **atlas de textures** ; shaders stylisés simples |

## Ce qu'on code nous-mêmes en C++ (GDExtension)

| Système | Pourquoi |
|---|---|
| **Streaming du monde par cellules** | Charger et décharger les morceaux de région en tâche de fond (chargement asynchrone), selon la position et la vitesse du joueur (galop) |
| **Simulation des foules** | Des centaines de PNJ en données compactes (orientées données), mis à jour par paquets, sur plusieurs cœurs |
| **Routines des PNJ** | Emplois du temps évalués en masse, pas un script par PNJ et par image |
| **Génération procédurale** | Médinas, dunes, végétation, construites par des règles, rapides et reproductibles (même graine = même résultat) |
| **Locomotion du cheval** | Suivi du relief, allures et anticipation des obstacles |

Le reste (missions, dialogues, interface, logique de jeu) est en GDScript typé, sauf si une mesure montre qu'il doit passer en C++.

## Architecture du projet

```
IbnKhaldoun/
├── CLAUDE.md                 # Consignes pour Claude Code
├── Docs/                     # Ce dossier de conception
├── Game/                     # Le projet Godot
│   ├── project.godot
│   ├── addons/               # Terrain3D, Dialogue Manager, GUT (installés aux versions figées, non versionnés)
│   ├── bin/                  # Extension C++ compilée + ibn.gdextension
│   ├── core/                 # Démarrage, sauvegarde, chargement des données
│   ├── player/               # Personnage, caméra, contrôles
│   ├── horse/                # Monture
│   ├── missions/             # Système de quêtes générique
│   ├── dialogue/             # Dialogues
│   ├── asabiyya/             # Groupes et relations
│   ├── carnet/               # Observations, idées, livrets, Codex
│   ├── world/                # Régions, cycle jour/nuit, météo, voyages
│   ├── npc/                  # PNJ, routines, foules (interface vers le C++)
│   ├── ui/                   # Interface
│   ├── data/                 # JSON : cartes, entrées, missions, dialogues, idées, livrets, groupes, manifestes de ressources
│   ├── assets/               # Ressources importées
│   ├── tests/                # Tests GUT (unit/), budgets de performance (perf/budgets/)
│   └── tools/builders/       # Constructeurs de scènes (build_<carte>.gd), lancés par le pipeline
├── Extensions/               # C++ (GDExtension)
│   ├── godot-cpp/
│   └── src/                  # streaming, foules, génération, cheval
├── Scripts/
│   ├── Pipeline/             # Compiler, tester, mesurer, capturer, exporter (PowerShell)
│   └── Blender/              # Génération et retouche des modèles
├── Tools/                    # installer.ps1, dependances.ps1, versions.json (figées) ; Godot, venv et outils.json (locaux)
├── .claude/                  # Agents, skills, hooks et réglages de Claude Code
└── Import/                   # Ressources téléchargées à la main, en attente d'import
```

### Principe clé : tout est piloté par les données
Les missions, les dialogues, le Codex, les idées, les livrets et les groupes ne sont **jamais codés en dur**. Ils sont décrits dans des fichiers texte, chargés par des systèmes génériques. Claude Code peut donc écrire une mission complète sans toucher au code.

Exemple de mission (format à finaliser au MVP 6) :

```json
{
  "id": "tunis_01_les_toits",
  "acte": 1,
  "annee": 1347,
  "type": "principale",
  "statut_historique": "F",
  "objectifs": [
    { "type": "poursuivre", "cible": "pnj_rachid_jeune", "zone": "tunis_toits_souk" },
    { "type": "dialogue", "cible": "dlg_rachid_figues" }
  ],
  "consequences": { "relation": { "pnj_rachid_jeune": 5 } },
  "debloque": { "observations": ["obs_tunis_souk_matin"] }
}
```

## Tout par Claude Code : le pipeline

**Principe :** le porteur du projet ne manipule rien dans l'éditeur. Claude Code fait tout par du code et des scripts. **Seule exception autorisée : certains téléchargements de ressources graphiques.**

### Les scripts sont la source de vérité
- Les scènes et ressources Godot sont du **texte** : Claude Code peut les lire et les écrire directement.
- Les scènes complexes (villes, terrains, placement de végétation) sont **construites par des scripts** dans `Game/tools/builders/` (à partir des données de `Game/data/<carte>/`), et doivent pouvoir être **entièrement recréées** en relançant leur script.
- Les modèles 3D créés ou retouchés le sont par des **scripts Blender** dans `Scripts/Blender/`.

### Comment Claude Code pilote Godot
| Besoin | Méthode |
|---|---|
| Importer les ressources | `godot --headless --import` |
| Construire une scène par script | `godot --headless --script res://tools/builders/build_<carte>.gd` (assemble la scène depuis ses données et l'enregistre) |
| Compiler le C++ | `scons` dans `Extensions/` |
| Tester | GUT en ligne de commande (`godot --headless -s addons/gut/gut_cmdln.gd`) |
| Mesurer les performances | Scène de mesure qui joue un parcours scripté et écrit un rapport CSV (images par seconde, temps par image, mémoire, appels de dessin) |
| Vérifier l'image | Captures d'écran automatiques depuis des points de vue fixes ; Claude Code les regarde et corrige |
| Enregistrer une vidéo | Mode Movie Maker de Godot (`--write-movie`) sur un parcours scripté |
| Créer la version jouable | `godot --headless --export-release "Windows Desktop"` (les plugins ne sont inclus dans l'export qu'à partir du MVP qui les utilise : `exclude_filter` de `Game/export_presets.cfg`) |

Toutes ces commandes sont regroupées dans des scripts PowerShell de `Scripts/Pipeline/`, et les chemins des outils sont lus dans `Tools/outils.json`.

### Parcours du joueur (`route_joueur.json`)
Les mesures et les vidéos peuvent suivre deux sortes de parcours (paramètre `-Parcours` de `mesurer.ps1` et `video.ps1`) :
- `points_de_vue` (par défaut) : la caméra glisse d'un point de vue à l'autre (`Game/data/<carte>/viewpoints.json`) ;
- `joueur` : **le joueur marche vraiment**, piloté par les actions d'entrée (`move_forward`, `move_back`, `move_left`, `move_right` avec une intensité, comme un stick analogique, calculée par rapport à la caméra active ; `walk_slow` ou `sprint` maintenus selon l'allure), le long de `Game/data/<carte>/route_joueur.json`. Les mesures (`resume.json`, `images.csv`, budgets) sont les mêmes ; le résumé indique le mode (`walk`), le parcours, son état, les points atteints, la distance marchée et la durée. La mesure dure exactement le parcours ; la vidéo aussi, sauf si `-Duree` l'écourte.

Le joueur est le **seul** nœud du groupe `player` (seul un `Node3D` est supposé). Échecs explicites, avec la position du joueur : joueur absent ou en double, aucune caméra active, action d'entrée manquante, **joueur bloqué** (la distance au prochain point ne diminue plus), joueur sorti de la scène, durée maximale dépassée. Toutes les actions pressées sont relâchées à la fin.

```json
{
  "description": "Tour de la colline par le sentier, puis descente en courant.",
  "start_position": [0.0, 12.5, 0.0],
  "arrival_radius_m": 0.6,
  "stall_time_s": 2.0,
  "stall_min_progress_m": 0.25,
  "max_duration_s": 300.0,
  "waypoints": [
    { "id": "sentier", "position": [40.0, -12.0], "gait": "walk" },
    { "id": "sommet", "position": [65.0, 20.0], "gait": "walk_slow" },
    { "id": "descente", "position": [10.0, 60.0], "gait": "run" }
  ]
}
```

| Clé | Rôle |
|---|---|
| `description` | Texte libre (obligatoire). |
| `start_position` | Facultatif : `[x, y, z]` où le joueur est placé avant le préchauffage ; sinon il part d'où la scène l'a mis. |
| `arrival_radius_m` | Distance horizontale à laquelle un point de passage est atteint (0,05 à 20 m). |
| `stall_time_s`, `stall_min_progress_m` | Blocage : la distance au prochain point doit diminuer d'au moins `stall_min_progress_m` toutes les `stall_time_s` secondes (0,1 à 60 s ; 0,01 à 20 m). |
| `max_duration_s` | Durée maximale du parcours (au plus 900 s) ; elle dimensionne la mémoire des mesures, réservée avant de commencer. |
| `waypoints` | 1 à 10 000 points : `id` unique (utilisable comme nom de fichier), `position` horizontale `[x, z]` (la hauteur est celle du sol), `gait` = allure du segment qui **mène** à ce point : `walk_slow`, `walk` ou `run`. |

### Les seules manipulations manuelles
| Manipulation | Quand |
|---|---|
| Accepter la fenêtre Windows « Autoriser cette application à apporter des modifications » pendant l'installation | Une seule fois |
| Télécharger une ressource qui demande un compte (par exemple Mixamo) | Rarement, quand Claude Code le demande |
| Jouer et donner son avis sur le ressenti | À chaque MVP |

Les ressources libres (Poly Haven, Quaternius, Kenney…) sont **téléchargées par Claude Code lui-même** quand c'est possible. Sinon :
1. Claude Code tient à jour `Docs/ressources-a-telecharger.md` (nom, lien, licence, raison, dossier de destination).
2. Le porteur du projet télécharge et dépose les fichiers dans `Import/`.
3. Claude Code les importe, les range, les configure (niveaux de détail, collisions, compression) et vérifie par capture d'écran.

## Budget de performance

| Cible | Résolution | Fréquence |
|---|---|---|
| **Machine de développement = configuration minimale** (Intel Core Ultra 7, puce Intel Arc intégrée) | 1080p (rendu interne mis à l'échelle par FSR 2) | **60 i/s dans le pire cas** |
| PC avec carte graphique dédiée | 1440p à 4K, qualité maximale | 60 i/s et plus |

**Ces objectifs sont tenus dans le pire cas, pas en moyenne.**

Règles :
- **Aucun raccourci, aucune optimisation repoussée à plus tard** (voir la règle absolue de `CLAUDE.md`).
- Chaque système a son **test de charge** qui reproduit son pire cas (foule maximale, galop en zone dense, tous les systèmes actifs, sauvegarde après 100 heures de jeu).
- Les performances sont mesurées **à chaque fonctionnalité**, sur la machine de développement.
- Budgets par image définis et vérifiés : appels de dessin, triangles, mémoire des textures, temps de script et temps du C++.

## Limites à connaître

- La qualité visuelle dépend des **ressources libres disponibles** et de la **qualité des règles de génération** : Claude Code les choisit, les génère et les assemble, mais n'égale pas une équipe d'artistes.
- Le **streaming de monde** et les **foules** sont des systèmes à construire nous-mêmes : ce sont les deux plus gros chantiers techniques.
- Le **ressenti de jeu** ne peut être jugé que par un humain qui joue.
- Si une opération semble impossible par script, Claude Code doit **le dire et proposer une solution par le code**, et ne jamais la confier au porteur du projet sans le signaler.
