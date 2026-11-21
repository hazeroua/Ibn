# 01 — Vision et attentes

## Mes attentes (exprimées par le porteur du projet)

- Un jeu sur l'**histoire maghrébine, arabe, musulmane, nord-africaine et du Moyen-Orient**.
- En **3D**, en **monde ouvert** complet : pas seulement un jeu de cheval.
- On **marche** librement dans les villes et les campagnes, on entre dans les bâtiments, on **interagit avec les PNJ** (parler, commercer, aider, observer), et le monde réagit.
- Un **cheval** pour les grandes distances : on fait la **traversée** soi-même.
- Un rendu **beau et soigné**, dans un **style stylisé haut de gamme** (lumière travaillée, couleurs fortes, matières peintes). *Le rendu photoréaliste « Assassin's Creed » visé au départ a été abandonné le 15/11/2026 : la machine de développement n'a pas de carte graphique dédiée, et le projet passe sous Godot 4.*
- Le jeu doit **tourner sur un PC sans carte graphique dédiée** (puce intégrée Intel Arc), ce qui le rend jouable par presque tout le monde.
- Suivre **toute la vie d'Ibn Khaldoun** : dans chaque ville, des **missions** inspirées de ce qu'il a réellement fait.
- Les missions doivent **expliquer l'histoire de la région** (dynasties, sociétés, idées).
- **C'est un jeu qui doit être joué avant de faire apprendre.** Une histoire attachante (personnages, suspense, trahisons, pertes) et **beaucoup de missions variées** qui donnent envie de rester. Pas une histoire factuelle (voir `08-synopsis.md`).
- **La philosophie d'Ibn Khaldoun est la ligne directrice de l'histoire.** À la fin du jeu, on a compris toute sa pensée.
- On apprend **par le jeu**, pas en lisant ses livres : un **système suit ce qu'on a appris**, et de **petits livrets** résument chaque idée (voir `07-philosophie.md`).
- Technologies **le plus open source possible**.
- Le jeu doit être **le plus optimisé possible**.
- **Aucun raccourci dans le code** : jamais de « on fera un meilleur système plus tard » ni de « ça suffit pour l'instant, on optimisera plus tard ». Tout est écrit avec la meilleure optimisation possible **pour tenir les pires cas**.
- Le développement est **entièrement vibe codé** : **tout se fait avec Claude Code**. Je ne manipule rien moi-même, sauf **télécharger les ressources graphiques** (personnages, tenues, textures, modèles) quand c'est nécessaire.
- Avancer par **jalons vérifiables** : d'abord le socle Terrain3D et une boucle Sahara, ensuite les systèmes de voyage, puis l'histoire.

## Ce que le joueur doit ressentir

- **L'émerveillement du voyage** : l'horizon du désert, l'arrivée sur une ville au coucher du soleil, le bruit des souks.
- **Des villes vivantes** : flâner à pied dans la médina, voir les artisans travailler, être interpellé par un marchand, écouter une conversation, suivre une rumeur qui mène à une mission.
- **L'intelligence plutôt que la violence** : Ibn Khaldoun est un lettré et un politique. On gagne surtout par la négociation, l'observation et le savoir. Le combat existe mais reste secondaire.
- **Comprendre** : en fin de partie, le joueur doit savoir qui étaient les Hafsides, les Mérinides, les Nasrides et les Mamelouks, et ce qu'est la *'asabiyya*.

## Références

| Jeu | Ce qu'on en retient |
|---|---|
| Assassin's Creed Origins / Mirage / Shadows | Villes vivantes, mode Découverte éducatif |
| The Legend of Zelda: Breath of the Wild / Tunic | Beauté d'un monde stylisé, envie d'explorer |
| Cassette Beasts | Monde ouvert 3D réalisé par une très petite équipe avec Godot |
| Red Dead Redemption 2 | Le cheval comme compagnon, le rythme du voyage |
| Ghost of Tsushima | Navigation sans HUD (le vent guide), poésie visuelle |
| Kingdom Come: Deliverance | Rigueur historique, monde médiéval crédible |
| Sable / Journey | Traversée du désert, contemplation |

## Ce que le jeu n'est pas

- Pas un jeu d'assassinat ou de massacre.
- Pas un « Assassin's Creed au Maghreb » qui recopie ses mécaniques : la parkour et l'infiltration ne sont pas au cœur du jeu.
- Pas un cours d'histoire déguisé : le jeu doit être fun avant d'être éducatif.
- Pas un monde ouvert géant et vide.

## Réalité du projet (à garder en tête)

Un grand jeu en monde ouvert mobilise habituellement des dizaines, voire des centaines de personnes. Le vibe coding résout la partie **code** ; le goulot d'étranglement sera **le contenu artistique** (modèles, textures, animations, voix, construction des villes). D'où la stratégie :

1. Un **style stylisé**, qui demande beaucoup moins de ressources que le photoréalisme.
2. S'appuyer massivement sur les **ressources libres** (Poly Haven, Quaternius, Kenney, MakeHuman) et la **génération procédurale** (villes, dunes, végétation construites par des règles).
3. Livrer d'abord une **boucle Sahara** très soignée pour valider le socle ; construire ensuite une tranche verticale narrative (prologue + Tunis) utilisable comme vitrine.

## Critères de réussite

- **Premier jalon :** parcourir le Sahara à pied entre un camp et une oasis est agréable et stable à 60 i/s.
- **Tranche verticale :** un joueur qui ne connaît pas Ibn Khaldoun termine Tunis 1348 en voulant la suite, et peut expliquer ce qu'est la peste noire au Maghreb et qui gouvernait Tunis.
- **Long terme :** le jeu complet couvre les 8 grandes étapes de la vie d'Ibn Khaldoun.
- **Fin du jeu :** le joueur sait expliquer avec ses mots les 20 idées principales d'Ibn Khaldoun et le grand cycle *désert → cohésion → pouvoir → ville → luxe → déclin*.

## Questions ouvertes

- [x] Moteur : **Godot 4**, piloté entièrement par Claude Code (décision du 15/11/2026, voir `05-technologies.md`).
- [x] Machine de développement : Intel Core Ultra 7, puce graphique intégrée = configuration minimale du jeu.
- [ ] Mémoire vive de la machine de développement : 16 Go minimum, 32 Go idéal (à vérifier).
- [ ] Plateformes cibles : PC Windows au départ ; Linux et Steam Deck faciles ensuite avec Godot ?
- [ ] Langues : français, arabe, anglais ? Doublage ou sous-titres ?
- [ ] Modèle économique : gratuit, payant, financement participatif ?
- [ ] Faire relire le scénario par un historien du Maghreb médiéval ?
