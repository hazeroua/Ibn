# 06 — Feuille de route : les MVP

> **Objectif :** avoir un premier résultat jouable **le plus vite possible**, puis voir le jeu **s'améliorer à chaque étape**.

## Les règles du découpage

1. **Petits MVP.** Chaque MVP ajoute **une seule couche** visible : on le termine vite et on le voit tout de suite à l'écran.
2. **Toujours jouable.** À la fin de chaque MVP, une **commande unique** lance le jeu, et on peut y jouer. Rien de ce qui marchait avant ne doit casser.
3. **Le périmètre est petit, la qualité est finale.** Chaque fonctionnalité livrée est définitive, optimisée au maximum et testée dans son pire cas (règle absolue de `CLAUDE.md`). On ne refait jamais un MVP « en mieux » plus tard : on **ajoute** par-dessus.
4. **D'abord la construction du jeu, ensuite l'histoire.** Les MVP 1 à 7 construisent le jeu, et l'histoire arrive à partir du MVP 8.
5. **Chaque MVP laisse une trace** : captures d'écran depuis les **mêmes points de vue**, une courte vidéo et une entrée dans le journal (en bas de ce fichier). On voit le jeu grandir.

## Ce que contient chaque fin de MVP

| Élément | Qui |
|---|---|
| Version jouable + commande de lancement | Claude Code |
| Tests automatiques et tests de charge du pire cas qui passent | Claude Code |
| Mesures de performance sur la machine de développement (puce intégrée = configuration minimale) | Claude Code |
| Captures d'écran comparatives + courte vidéo | Claude Code |
| Entrée dans le journal | Claude Code |
| **Jouer et donner son avis** | Toi |

---

## Vue d'ensemble

```
CONSTRUIRE LE JEU                                       RACONTER L'HISTOIRE
─────────────────────────────────────────────────────   ──────────────────────────────
 0 Le bac à sable   →  1 Premiers pas  →  2 Le désert    8  Le prologue de Damas
 3 Barq             →  4 La porte de Tunis               9  Tunis, l'orphelin (acte I)
 5 Les habitants    →  6 La première mission            10  La démo publique
 7 Le carnet                                            11+ Les actes II à VII
```

| MVP | Nom | Ce que tu vois à la fin | Taille |
|---|---|---|---|
| 0 | **Le bac à sable** | Un sol, un ciel, un cube. Le pipeline Claude Code fonctionne. | S |
| 1 | **Premiers pas** | Ton personnage marche et court sur un terrain, caméra fluide. | S |
| 2 | **Le désert** | Des dunes à perte de vue, un coucher de soleil, la nuit étoilée. | M |
| 3 | **Barq** | Tu montes à cheval et tu galopes dans le désert. | M |
| 4 | **La porte de Tunis** | Tu entres dans une rue de médina, tu ouvres des portes, tu t'assois. | M |
| 5 | **Les habitants** | La rue est vivante : marchands, passants, tu peux leur parler. | L |
| 6 | **La première mission** | Une vraie mission jouable du début à la fin, avec un dialogue à choix. | L |
| 7 | **Le carnet** | Tu observes, tu relies, une idée naît et tu lis ton premier livret. | M |
| 8 | **Le prologue de Damas** | Les 20 premières minutes du jeu final. | L |
| 9 | **Tunis, l'orphelin** | L'acte I complet : 4 à 6 heures de jeu. | XL |
| 10 | **La démo publique** | Prologue + acte I, polis et prêts à être montrés. | L |
| 11+ | **Les actes II à VII** | Un acte par MVP. | XL chacun |

*Taille : S = petit, M = moyen, L = grand, XL = très grand.*

---

## MVP 0 — Le bac à sable

**But :** prouver que Claude Code peut tout faire sans que tu ouvres l'éditeur.

**Tu fais (une seule fois) :** demander à Claude Code de lancer `Tools/installer.ps1`, et accepter la fenêtre Windows d'autorisation. Claude Code installe tout le reste (voir `00-installation.md`).

**Livrables**
- [ ] Outils installés et vérifiés par `Tools/installer.ps1` ; `Tools/outils.json` rempli.
- [ ] Projet Godot 4 (`Game/`) et extension C++ (`Extensions/`) créés et organisés par script (voir `05-technologies.md`) ; l'extension C++ compile et se charge dans le jeu.
- [ ] Dépôt Git + Git LFS.
- [ ] Pipeline en ligne de commande (`Scripts/Pipeline/`) : importer, construire une scène par script, compiler le C++, tester (GUT), mesurer, capturer, enregistrer une vidéo, exporter.
- [ ] Script d'import automatique depuis `Import/` et fichier `Docs/ressources-a-telecharger.md`.
- [ ] La carte « bac à sable » : sol, ciel, éclairage, un cube. Elle est entièrement recréée par son script.
- [ ] `lancer.bat` (ou équivalent) : une commande qui lance le jeu.

**Terminé quand :** tu demandes « mets un deuxième cube rouge », et Claude Code le fait, le teste, prend une capture et te dit « c'est prêt », sans que tu touches à rien.

---

## MVP 1 — Premiers pas

**But :** marcher dans le monde. Le premier vrai moment de jeu.

**Ressources :** un personnage généré avec MakeHuman (MPFB) dans Blender, des animations de déplacement libres (Quaternius, ou Mixamo en téléchargement manuel).

**Livrables**
- [ ] Personnage à la troisième personne : marche lente, marche, course, arrêt, virages naturels.
- [ ] Caméra fluide, avec gestion des collisions contre les murs.
- [ ] Contrôles manette et clavier/souris (actions d'entrée de Godot, reconfigurables).
- [ ] Un terrain vallonné de test de 1 km².
- [ ] Sons de pas selon le sol (sable, pierre).

**Pires cas testés :** 1 000 objets avec collision autour du joueur, caméra coincée dans un recoin, changement de manette en jeu.

**Terminé quand :** marcher pendant 5 minutes est agréable, à 60 i/s.

---

## MVP 2 — Le désert

**But :** la première image « waouh ». C'est la carte postale du jeu.

**Ressources :** textures de sable et de roche (Poly Haven), rochers et palmiers libres ou générés dans Blender par script.

**Livrables**
- [ ] Désert de 4 × 4 km avec Terrain3D : dunes générées par script, rochers avec niveaux de détail, une oasis avec de l'eau.
- [ ] Végétation placée par génération procédurale (C++) et affichée en MultiMesh.
- [ ] **Cycle jour/nuit** complet : aube, heure dorée, nuit étoilée (ciel procédural, lumière du ciel, brouillard).
- [ ] Vent : sable qui vole, palmiers qui bougent, son du vent.
- [ ] Brouillard de chaleur et poussière à l'horizon.
- [ ] **Streaming du monde par cellules** en C++ (chargement asynchrone).

**Pires cas testés :** course à travers les zones les plus denses en végétation, toutes les heures de la journée, vent de sable maximal, sur la puce graphique intégrée.

**Terminé quand :** une capture du coucher de soleil sur les dunes donne envie d'y être, à 60 i/s.

---

## MVP 3 — Barq

**But :** le cheval, deuxième personnage du jeu.

**Ressources :** un cheval animé libre (Quaternius ou équivalent), retouché par script dans Blender (selle, harnais, proportions).

**Livrables**
- [ ] Monter et descendre du cheval, avec des animations fluides.
- [ ] Allures : pas, trot, galop, sprint avec endurance.
- [ ] Le cheval suit le relief, évite les obstacles et refuse les chutes dangereuses.
- [ ] Sifflet d'appel : Barq arrive en trottant depuis où il est.
- [ ] Caméra de monte, plus large et plus dynamique au galop.
- [ ] Sons des sabots selon le sol, souffle du cheval.
- [ ] Traces de sabots dans le sable.

**Pires cas testés :** galop au sprint maximal pendant 10 minutes à travers toute la carte (streaming), appel du cheval à l'autre bout de la carte, terrain très accidenté.

**Terminé quand :** galoper au coucher du soleil donne des frissons.

---

## MVP 4 — La porte de Tunis

**But :** la première ville, ou plutôt sa première rue.

**Ressources :** éléments d'architecture (murs, portes, arcs, tuiles, zellige) **générés dans Blender par script** dans le style du jeu, et accessoires (jarres, tapis, étals) libres ou générés.

**Livrables**
- [ ] Une **porte de ville** dans les remparts, avec la transition entre le désert et la ville.
- [ ] **Une rue de médina** construite par génération procédurale : ruelles, passages couverts, une petite place avec une fontaine.
- [ ] **3 intérieurs** : une maison, une boutique, une petite mosquée.
- [ ] Système d'**interaction** : ouvrir une porte, s'asseoir, ramasser un objet, lire une inscription, boire à la fontaine.
- [ ] Escalade légère vers une terrasse.
- [ ] Ambiance sonore de la ville.
- [ ] Le cheval reste à la porte ; on entre à pied.

**Pires cas testés :** entrée au galop dans la ville, ruelles les plus étroites (caméra), tous les intérieurs chargés en même temps.

**Terminé quand :** entrer dans la médina au coucher du soleil, passer de la lumière à l'ombre des ruelles, donne l'impression d'y être.

---

## MVP 5 — Les habitants

**But :** une rue vivante. On passe d'un décor à un monde.

**Ressources :** personnages variés générés avec MakeHuman (MPFB), vêtements d'époque, animations (marcher, vendre, discuter, prier, porter).

**Livrables**
- [ ] **PNJ nommés** (10) avec des **routines** selon l'heure : le marchand ouvre son échoppe, le porteur d'eau fait sa tournée, tout le monde rentre la nuit.
- [ ] **Foule** simulée en C++ dans la rue et sur la place, avec trois niveaux de détail.
- [ ] **Parler à n'importe qui** : répliques contextuelles selon l'heure, le lieu et la météo.
- [ ] **Écouter** : surprendre des conversations.
- [ ] **Réactions** : courir ou bousculer les gens les fait réagir.
- [ ] **Commerce** simple : acheter des figues.

**Pires cas testés :** foule maximale sur la place, 50 PNJ qui réagissent en même temps, journée complète en accéléré pour vérifier les routines.

**Terminé quand :** flâner 15 minutes dans la rue en écoutant les gens est intéressant.

---

## MVP 6 — La première mission

**But :** les systèmes qui portent tout le jeu, démontrés par **une vraie mission** de l'histoire.

**Livrables**
- [ ] Système de **missions** générique, piloté par des fichiers JSON (tous les types d'objectifs).
- [ ] Système de **dialogues** à choix, piloté par des données.
- [ ] Système d'**alliances** (*'asabiyya*) : groupes et relations.
- [ ] **Sauvegarde et chargement**.
- [ ] Interface : journal des missions, boussole discrète, carte stylisée.
- [ ] **La mission « Les toits de Tunis »** (acte I) entièrement jouable : poursuite sur les toits avec Rachid, dialogue, fin.

**Pires cas testés :** 1 000 missions chargées, sauvegarde après une partie simulée de 100 heures, chargement en pleine mission, au galop ou en dialogue.

**Terminé quand :** la mission est amusante, **et** Claude Code peut écrire une deuxième mission **uniquement en JSON**, sans toucher au C++.

---

## MVP 7 — Le carnet

**But :** le système qui fait apprendre en jouant (voir `07-philosophie.md`).

**Livrables**
- [ ] **Observations** : mode observation, collecte dans le monde et auprès des PNJ.
- [ ] **Tableau des idées** : relier les observations, animation quand une idée naît.
- [ ] **Livrets** : écran de lecture, avec la partie « Ce que tu as vu » générée à partir des observations du joueur.
- [ ] **Les quatre niveaux de maîtrise**, et les capacités débloquées.
- [ ] **Codex**.
- [ ] Démonstration : l'**idée 1** (« L'homme ne peut pas vivre seul ») débloquée en jouant dans la rue, avec son livret.

**Pires cas testés :** 20 idées, 2 000 observations, tableau plein, livrets générés pour toutes les combinaisons.

**Terminé quand :** tu comprends une idée sans avoir eu l'impression qu'on te l'explique.

---

## MVP 8 — Le prologue de Damas

**But :** l'accroche du jeu final. Le premier contenu définitif.

**Ressources :** remparts et ville syrienne, camp militaire (tentes, feux, étendards), personnages : Ibn Khaldoun âgé, Tamerlan, Rachid âgé, soldats (générés ou libres).

**Livrables**
- [ ] Les remparts de Damas de nuit.
- [ ] **« Les remparts »** : la descente à la corde.
- [ ] **« Le camp des mille feux »** : traverser le camp en discrétion (système de discrétion).
- [ ] **« La tente »** : premier dialogue avec Tamerlan, apparition de Rachid.
- [ ] Mise en scène : cinématiques en jeu, musique.

**Terminé quand :** quelqu'un qui joue les 20 premières minutes veut absolument savoir la suite.

---

## MVP 9 — Tunis, l'orphelin

**But :** l'acte I complet.

**Livrables**
- [ ] La ville de Tunis complète : médina, toits, Zitouna, kasbah, port, remparts, oliveraies, ruines de Carthage. La rue du MVP 4 est étendue, pas refaite.
- [ ] Personnages : Ibn Khaldoun et Rachid jeunes, al-Abili, Amina, les parents.
- [ ] Les **9 missions principales**, les **3 chaînes de quêtes**, **10 annexes** (voir `04-missions.md`).
- [ ] Activités : **échecs** (shatranj) et **courses de chevaux**.
- [ ] La peste : la ville change d'état (rues vides, fumées).
- [ ] Les **idées 1 à 3** avec leurs livrets et leurs applications.
- [ ] Retours dans la tente de Tamerlan entre les séquences.

**Terminé quand :** un joueur extérieur joue 4 à 6 heures sans décrocher.

---

## MVP 10 — La démo publique

**But :** une version à montrer au monde (vitrine, communauté, financement).

**Livrables**
- [ ] Prologue + acte I polis.
- [ ] Menus, options graphiques, réglages d'accessibilité, sous-titres.
- [ ] Langues : français, arabe, anglais.
- [ ] Bande-annonce enregistrée en jeu.
- [ ] Version empaquetée prête à distribuer.

**Terminé quand :** la démo tourne à 60 i/s sur un PC sans carte graphique dédiée et fait envie à des inconnus.

---

## MVP 11 et suivants — Les actes

Un acte par MVP, dans l'ordre de `08-synopsis.md` :

| MVP | Acte |
|---|---|
| 11 | II — Le courtisan (Fès) |
| 12 | III — L'ambassadeur (Grenade, Séville) |
| 13 | IV — Le faiseur de rois (Béjaïa, désert) |
| 14 | V — L'ermite (Qal'at Ibn Salama) |
| 15 | VI — Le juge (Tunis, Le Caire, La Mecque) |
| 16 | VII — Face à Tamerlan (Damas) + épilogue |
| 17 | Mode Découverte et sortie |

---

## Journal

Claude Code complète ce tableau à chaque fin de MVP.

| MVP | Date | Perf. pire cas (i/s, ms par image) | Mémoire | Ce qui a été plus dur que prévu | Décisions prises |
|---|---|---|---|---|---|
| 0 | | | | | |
