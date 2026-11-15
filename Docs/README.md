# Les Chemins d'Ibn Khaldoun — Dossier de conception

> Titre provisoire. Jeu d'action-aventure en monde ouvert, en 3D stylisée, sous Godot 4, qui suit la vie d'Ibn Khaldoun (1332–1406), de Tunis à Damas. On explore librement à pied et à cheval, on entre dans les villes, on parle et on interagit avec leurs habitants.

Ce dossier décrit le projet avant la première ligne de code. Il sert de référence au porteur du projet **et** à l'IA qui codera le jeu (vibe coding) : chaque fichier doit pouvoir être donné tel quel comme contexte à l'agent.

## Sommaire

| Fichier | Contenu |
|---|---|
| [00-installation.md](00-installation.md) | Les outils à installer, et comment Claude Code les installe |
| [01-vision-et-attentes.md](01-vision-et-attentes.md) | Ce que je veux, ce que je ne veux pas, critères de réussite |
| [02-histoire.md](02-histoire.md) | Base historique : les faits de sa vie et des régions traversées |
| [03-game-design.md](03-game-design.md) | Gameplay, monde ouvert, cheval, systèmes de jeu |
| [04-missions.md](04-missions.md) | Missions par ville et par époque |
| [05-technologies.md](05-technologies.md) | Moteur, outils, architecture, budget de performance |
| [06-roadmap-mvp.md](06-roadmap-mvp.md) | Les 17 MVP : un premier résultat vite, puis le jeu qui s'améliore à chaque étape |
| [08-synopsis.md](08-synopsis.md) | **L'histoire du jeu** : le pitch, les personnages, les actes |
| [07-philosophie.md](07-philosophie.md) | **Le fil conducteur** : la pensée d'Ibn Khaldoun, apprise en jouant (carnet, idées, livrets) |
| [CLAUDE.md](../CLAUDE.md) | Consignes pour l'agent IA qui code le projet |

## Le pitch

**Damas, 1401.** Encerclé par l'armée de Tamerlan, un vieil historien se fait descendre par une corde le long des remparts pour affronter le conquérant. Pour sauver la ville, il va lui raconter sa vie : la peste, la prison, les cours royales, les guerres du désert, l'amitié et la trahison de Rachid, son frère d'enfance. Le joueur vit chacun de ces souvenirs. (Voir `08-synopsis.md`.)

## Le jeu en une phrase

On incarne Abd al-Rahman Ibn Khaldoun, jeune lettré tunisois devenu diplomate, chambellan, prisonnier, négociateur auprès des tribus, juge au Caire et interlocuteur de Tamerlan ; on parcourt à pied et à cheval le Maghreb, al-Andalus, l'Égypte, le Hijaz et la Syrie du XIVᵉ siècle, et chaque mission fait comprendre l'histoire de la région.

**Le fil conducteur, c'est sa philosophie** : le joueur vit les situations qui ont fait naître ses idées, les comprend, puis les applique. À la fin, il a compris toute la pensée d'Ibn Khaldoun sans avoir lu ses livres.

## Principes directeurs

0. **Jouer d'abord, apprendre ensuite.** Le jeu doit être captivant même pour quelqu'un que l'histoire n'intéresse pas. L'apprentissage vient de ce qu'on vit, jamais d'un cours.
1. **Le moteur d'abord, l'histoire ensuite.** On ne raconte rien tant que marcher dans une médina, parler aux habitants et chevaucher dans le désert ne sont pas agréables.
2. **Petit mais beau.** Une tranche jouable très soignée vaut mieux qu'un monde ouvert vide.
3. **Tout en texte.** Code, missions, dialogues, données : tout ce qui peut être un fichier texte l'est, pour que l'IA puisse le lire et l'écrire.
4. **L'histoire est respectée.** On invente pour combler les vides, jamais pour contredire les faits connus, et le jeu distingue clairement les deux.
