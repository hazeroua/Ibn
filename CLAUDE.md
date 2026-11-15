# CLAUDE.md — Consignes pour l'agent IA

Ce projet est un jeu en monde ouvert sous **Godot 4** (GDScript typé + C++ via GDExtension) sur la vie d'Ibn Khaldoun (1332–1406). Il est entièrement développé par vibe coding : **tu fais tout**, le porteur du projet ne fait que télécharger certaines ressources graphiques et jouer.

**Machine de développement :** Windows, Intel Core Ultra 7, **puce graphique intégrée Intel Arc, pas de carte graphique dédiée**. C'est aussi la configuration minimale du jeu.

## À lire avant toute tâche
- `Docs/01-vision-et-attentes.md` : ce que veut le porteur du projet.
- `Docs/06-roadmap-mvp.md` : le MVP en cours. **Ne travaille que sur le MVP en cours.**
- `Docs/05-technologies.md` : stack, architecture, pipeline, budget de performance.
- `Tools/outils.json` : chemins de Godot, de Blender et des outils (créé par `Tools/installer.ps1`).
- Pour toute tâche de contenu (mission, dialogue, Codex) : `Docs/08-synopsis.md` (l'histoire), `Docs/04-missions.md`, `Docs/03-game-design.md`, et `Docs/02-histoire.md` pour les faits.
- **Toujours** pour le contenu narratif : `Docs/07-philosophie.md`. Chaque mission doit servir au moins une des 20 idées (observation ou application).
- **Jouer d'abord, apprendre ensuite** : une mission doit être amusante avant d'être instructive. Jamais de texte explicatif imposé au joueur.

## ⛔ RÈGLE ABSOLUE N° 1 : AUCUN RACCOURCI

Cette règle passe avant toutes les autres. Elle ne souffre aucune exception.

**Interdit :**
- Écrire une version « provisoire », « simple pour l'instant », « suffisante pour le moment » ou « à améliorer plus tard ».
- Repousser l'optimisation : *« on optimisera plus tard »*, *« ça suffit pour un prototype »*, *« ce sera remplacé par un meilleur système »*.
- Les `TODO`, `FIXME`, `HACK` ou commentaires du type *« temporaire »* dans le code rendu.
- Les implémentations factices (stubs, valeurs en dur, fonctions vides) présentées comme du travail terminé.
- Les solutions qui marchent dans le cas moyen mais s'effondrent dans le pire cas.

**Obligatoire :**
- Chaque système est écrit **directement dans sa version définitive**, avec **la meilleure optimisation possible**.
- Chaque système est conçu pour **tenir le pire cas**, pas le cas moyen. Avant de coder, identifier et écrire explicitement les pires cas, par exemple :
  - nombre maximal de PNJ, de cavaliers et d'objets visibles en même temps (souk bondé, armée de Damas, caravane du pèlerinage) ;
  - **la puce graphique intégrée de la machine de développement** ;
  - partie de 100 heures : taille de la sauvegarde, nombre de missions, d'observations et d'idées enregistrées ;
  - galop à vitesse maximale à travers une zone dense (streaming des cellules du monde) ;
  - tous les systèmes actifs en même temps (météo, foule, combat, dialogue, cycle jour/nuit).
- Choisir les structures de données et les algorithmes pour leur **complexité dans le pire cas** (pas d'O(n²) sur des listes de PNJ, pas de recherche linéaire répétée à chaque image, etc.).
- **Zéro allocation mémoire inutile** dans les chemins chauds (par image) : réserver, réutiliser, mettre en pool.
- Écrire un **test de charge** pour chaque système, qui reproduit son pire cas, et donner les mesures (temps par image, mémoire).
- Si une contrainte empêche de faire la meilleure solution (limite du moteur, ressource manquante), **le dire clairement et s'arrêter pour demander**, au lieu de livrer une solution au rabais.

**Le MVP limite le périmètre, jamais la qualité.** Un MVP contient moins de fonctionnalités, mais chaque fonctionnalité livrée est finale, optimisée et robuste au pire cas.

## ⛔ RÈGLE ABSOLUE N° 2 : LE PORTEUR DU PROJET NE MANIPULE RIEN

- **Tu fais tout** : installation des outils, code, scènes, matériaux, éclairage, imports, réglages, tests, mesures, export. Voir « Tout par Claude Code » dans `Docs/05-technologies.md`.
- **Télécharge toi-même** les ressources libres (Poly Haven, Quaternius, Kenney…) quand c'est possible. Si une ressource exige un compte ou un clic, ajoute-la à `Docs/ressources-a-telecharger.md` (nom, lien, licence, raison, dossier de destination), puis attends qu'elle soit déposée dans `Import/`.
- **Ne demande jamais** d'ouvrir l'éditeur Godot, de cliquer, de régler une valeur, de placer un objet ou de créer un fichier à la main.
- **Les scripts sont la source de vérité** : les scènes complexes sont construites par des scripts de `Scripts/Godot/` et doivent pouvoir être recréées en les relançant ; les modèles créés ou retouchés le sont par des scripts de `Scripts/Blender/`.
- **Vérifie ton travail toi-même** : captures d'écran automatiques pour le visuel, tests GUT pour la logique, scènes de mesure pour la performance.
- Si une opération te semble impossible par script, cherche d'abord une solution par le code. Si vraiment il n'y en a pas, **arrête-toi et explique pourquoi** avant de demander quoi que ce soit.

## Règles de code
- **GDScript typé statiquement partout** (variables, paramètres, retours). Pas de code non typé.
- **C++ (GDExtension) pour tout chemin chaud** : streaming du monde, foules, routines en masse, génération procédurale, locomotion du cheval, et tout ce qu'une mesure désigne comme trop coûteux en GDScript.
- **Tout est piloté par les données** : missions, dialogues, Codex, idées, livrets, groupes, PNJ nommés → fichiers JSON dans `Game/data/` ou dialogues de Dialogue Manager. Jamais de contenu codé en dur.
- Respecter l'arborescence de `Docs/05-technologies.md`.
- Pas de `_process` / `_physics_process` sans nécessité : préférer signaux, timers et mises à jour par paquets.
- Répétitions visuelles → **MultiMeshInstance3D**. Lointain → niveaux de détail et imposteurs. Médinas → occlusion culling.
- Noms de code en **anglais**, commentaires et textes du jeu en **français** (textes traduisibles via le système de traduction de Godot).
- Version de Godot **figée** : celle de `Tools/outils.json`. Ne change pas de version sans le demander.

## Performance (non négociable)
- Cible : **60 i/s en 1080p (FSR 2) sur la puce Intel Arc intégrée de la machine de développement, dans le pire cas.**
- Mesurer à chaque fonctionnalité, avec la scène de mesure correspondante.
- Signaler immédiatement tout dépassement de budget (appels de dessin, triangles, mémoire des textures, temps par image).

## Méthode de travail
1. Reformuler la tâche en une phrase et vérifier qu'elle appartient au MVP en cours.
2. Écrire les pires cas de la tâche.
3. Coder par petits incréments ; compiler le C++ (`scons`) et lancer les tests GUT ; corriger avant de rendre la main.
4. Lancer le **test de charge du pire cas** et rapporter les mesures.
5. Prendre des **captures d'écran** automatiques et les vérifier si la tâche touche au visuel.
6. Terminer par : les pires cas traités et leurs mesures, ce qui a changé, **la commande unique qui lance le jeu au bon endroit pour essayer**, et les éventuelles ressources à télécharger.
7. Une fonctionnalité = une branche Git = un commit clair.

## Histoire
- Ne jamais contredire un fait historique de `Docs/02-histoire.md`.
- Tout contenu inventé est marqué `"statut_historique": "F"` (fiction) ou `"P"` (plausible).
- Représenter les peuples, religions et cultures avec respect et nuance.
