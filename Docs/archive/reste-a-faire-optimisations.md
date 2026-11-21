# Reste à faire après la passe d'optimisation Intel Arc

État au 17 novembre 2026. La passe fonctionnelle est implémentée ; ce fichier distingue les validations terminées de la seule validation longue interrompue volontairement avant le push.

## Validé

- Parcours réel à pied dans la palmeraie : 545,6 m, 41 901 images, 99,4 i/s au 1 % le plus lent, GPU p99 8,30 ms, parcours terminé, budgets stricts respectés.
- Parcours réel de Barq avec cheminement A* : 4 847 m, 76 195 images, 109,0 i/s au 1 % le plus lent, GPU p99 6,78 ms, parcours terminé, budgets stricts respectés.
- Vue globale `desert_jeu` : 155,65 i/s de moyenne et 92,77 i/s au 1 % le plus lent sur la mesure de 30 s.
- Shader de terre de la palmeraie : 9 lectures de texture réduites à 3 ; cultures : 2 réduites à 1. Captures avant/après sans erreur magenta et sans régression visuelle notable.
- Streaming lourd Windows : 9/9 tests, p99 d'attache 2,20 ms, aucune cellule manquante.
- Barq avec 1 000 obstacles : p99 0,027 ms ; personnage avec 1 000 collisionneurs : p99 0,193 ms.
- Arrêt headless verbose sans fuite ObjectDB ; arrêt rendu court sans fuite après vidange de tous les lecteurs audio.
- Tests ciblés du vent, du terrain, du streaming, de Barq, du personnage, du pipeline et du provider de Tunis verts.

## À rejouer

1. Relancer `Scripts/Pipeline/tester.ps1` sans interruption. La première suite complète a exécuté 373 tests ; ses quatre échecs provenaient tous d'une dernière frame du vent pendant la destruction des scènes. Le garde de cycle de vie a ensuite été ajouté et les deux suites directement concernées (`test_wind_system.gd` et `test_tunis_cell_provider.gd`) passent. La seconde suite complète a été interrompue à la demande du porteur du projet pour pousser avant la limite de session.
2. Pour une preuve audio maximale, rejouer le parcours Barq complet après la vidange audio généralisée. Le parcours complet et ses budgets sont déjà verts ; seul son ancien code de sortie était non nul à cause des sons de sabots encore référencés. Un run rendu court valide la nouvelle sortie propre.
3. Si une mesure isolée du gain shader est souhaitée, profiler la même caméra fixe avant/après sur `vue_palmeraie_parcelles`. Le nombre de lectures est déjà réduit de plus de moitié et la validation visuelle est faite, mais aucun delta GPU isolé et parfaitement comparable n'a été archivé.

## Commandes

```powershell
Scripts/Pipeline/tester.ps1
Scripts/Pipeline/mesurer.ps1 -Carte desert_jeu -Parcours joueur -Prechauffage 2
Scripts/Pipeline/mesurer.ps1 -Carte desert_jeu -Parcours res://data/desert_jeu/route_barq.json -Prechauffage 2
Scripts/Pipeline/capturer.ps1 -Carte desert_jeu
```
