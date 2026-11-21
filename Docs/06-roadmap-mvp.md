# 06 — Feuille de route active : reboot Terrain3D

Cette feuille de route remplace les anciens MVP. Le projet repart de zéro et avance par sept tickets ordonnés. La cible du premier jalon est une boucle jouable courte dans le Sahara, stable à 60 images par seconde en 1080p avec FSR 2 sur Intel Arc intégrée.

## Règles

- Terrain3D est la fondation du monde extérieur.
- Le nouveau socle ne dépend pas du code de l'ancien jeu.
- L'ancien dossier `Game/` est une archive ; le jeu se trouve dans `Projet/`.
- Chaque ticket produit une scène essayable, des tests, des mesures et une commande reproductible.
- Un ticket n'est fermé que lorsque tous ses critères d'acceptation sont vérifiés.
- Les tickets 3 et 4 peuvent avancer en parallèle après le ticket 2. Tous les autres suivent leurs dépendances.

## Ordre de réalisation

| Ordre | Ticket | État au 21 novembre 2026 | Résultat attendu |
|---:|---|---|---|
| 1 | [#62 — Valider Terrain3D](https://github.com/hazeroua/Ibn/issues/62) | Terminé (Vulkan retenu) | Décision mesurée Vulkan/D3D12 sur la machine cible |
| 2 | [#63 — Créer le socle neuf](https://github.com/hazeroua/Ibn/issues/63) | Terminé : socle `Projet/` | Nouveau projet Godot indépendant de l'ancien code |
| 3 | [#64 — Construire le terrain saharien](https://github.com/hazeroua/Ibn/issues/64) | Terminé : scène `sahara` | Dunes, zones rocheuses et oueds sur 4 × 4 km |
| 4 | [#65 — Refaire le personnage et la caméra](https://github.com/hazeroua/Ibn/issues/65) | Bloqué par #63 | Déplacement troisième personne neuf et stable |
| 5 | [#66 — Définir l'identité visuelle](https://github.com/hazeroua/Ibn/issues/66) | Bloqué par #63 et #64 | Lumière, ciel, brume, vent et poussière |
| 6 | [#67 — Ajouter rochers, végétation et oasis](https://github.com/hazeroua/Ibn/issues/67) | Bloqué par #63 et #64 | Oasis et instanciation du décor |
| 7 | [#68 — Livrer la première boucle jouable](https://github.com/hazeroua/Ibn/issues/68) | Bloqué par #64 à #67 | Parcours camp–oasis–camp exporté sous Windows |

```text
#62 Validation Terrain3D
└── #63 Socle neuf
    ├── #64 Terrain saharien ──┬── #66 Identité visuelle ─┐
    │                          └── #67 Oasis et décor ────┤
    └── #65 Joueur et caméra ─────────────────────────────┴── #68 Boucle jouable
```

## Porte de décision du ticket 1

Le prototype se trouve dans `Reboot/Terrain3DValidation/`. Les tests de 30 secondes Vulkan et D3D12 sont réussis (p99 8,3 ms, 0 image au-delà de 16,7 ms, 0 collision manquée, 0 erreur). Le porteur du projet a décidé le 21/11/2026 de fermer #62 sur la base des tests de 30 secondes, sans sessions de 30 minutes.

Décision : **Vulkan** est le moteur de rendu du nouveau socle (pire image 10,6 ms contre 12,9 ms, mémoire vidéo 276 Mio contre 292 Mio). La porte est franchie ; le ticket suivant est #63.

## Hors périmètre du premier jalon

- Tunis et la médina ;
- Barq et le gameplay monté ;
- foules, routines et missions historiques ;
- reprise automatique d'un système de l'ancien projet.

Après la réussite du ticket 7, un nouveau jalon décidera explicitement quels éléments historiques, narratifs, sonores ou artistiques peuvent être réutilisés.
