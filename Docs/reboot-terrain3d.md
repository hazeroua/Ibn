# Décision — Reconstruire le projet autour de Terrain3D

- **Date :** 21 novembre 2026
- **État :** adoptée, sous réserve de la porte technique #62
- **Feuille de route :** [06-roadmap-mvp.md](06-roadmap-mvp.md)

## Décision

Le projet est reconstruit depuis zéro. Terrain3D 1.1.0 est évalué comme fondation du monde extérieur sous Godot 4.7.2. Le premier jalon livre une boucle Sahara camp–oasis–camp avant toute reprise de Tunis, de Barq, des foules ou des missions historiques.

## Pourquoi repartir de zéro

L'ancien projet mêle plusieurs générations de terrain, streaming, gameplay, ville et optimisations. Continuer à empiler des systèmes rendrait les résultats difficiles à mesurer et transporterait des contraintes qui ne sont plus justifiées.

Le reboot doit fournir :

- une architecture minimale et lisible ;
- un terrain unique piloté par Terrain3D ;
- des performances vérifiées sur la machine cible dès le départ ;
- des tests, captures et exports reproductibles ;
- une sélection explicite, tardive et mesurée de tout élément ancien éventuellement récupéré.

## Ce qui est conservé

- la vision du jeu et son ambition historique ;
- les recherches historiques, le synopsis, les missions envisagées et la philosophie ;
- les outils et versions utiles au protocole de validation ;
- l'ancien code dans Git, uniquement comme archive consultable.

## Ce qui n'est pas repris automatiquement

- terrain par tuiles et ancien streaming ;
- contrôleurs du joueur et de Barq ;
- génération de Tunis et outils d'administration ;
- shaders, végétation, audio et budgets de l'ancien désert ;
- pipeline historique de validation.

Une éventuelle reprise après #68 doit démontrer un gain clair, ne pas créer de dépendance cachée et passer les tests du nouveau socle.

## Porte technique

Le ticket [#62](https://github.com/hazeroua/Ibn/issues/62) a comparé Vulkan et D3D12 sur Intel Arc intégrée. Le porteur du projet a décidé le 21/11/2026 de fermer #62 sur la base des tests de 30 secondes, sans sessions de 30 minutes. Vulkan est retenu.

Le reboot continue seulement si au moins un moteur de rendu respecte tous les budgets, sans crash, erreur, corruption, collision manquée ni croissance mémoire anormale.

## Conséquence documentaire

La feuille de route de sept tickets est la seule roadmap active. Les anciens contrats MVP, la médina, les passes de performance et les listes de travaux restantes sont déplacés dans `Docs/archive/` et ne doivent plus guider l'implémentation.
