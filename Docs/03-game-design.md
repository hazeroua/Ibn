# 03 — Game design

## Genre

Action-aventure **narrative** en **monde ouvert par régions**, à la troisième personne. On explore **à pied** des villes vivantes peuplées de PNJ avec lesquels on interagit, et **à cheval** les grands espaces entre elles. Le cœur du jeu : l'**exploration**, les **interactions**, la **diplomatie** et l'**enquête**. Le combat est présent mais secondaire.

## Boucle de jeu

```
Arriver dans une région → Explorer (à pied / à cheval) → Entrer en ville, parler aux PNJ
      ↑                                              ↓
Voyager vers la région suivante  ←  Missions (histoire + annexes)
                                                     ↓
                    Codex enrichi, alliances ('asabiyya) modifiées
```

- **Boucle courte (minutes) :** flâner, écouter, parler à un PNJ, découvrir un lieu, accomplir un objectif.
- **Boucle moyenne (heures) :** terminer les missions d'une ville, changer l'équilibre des alliances locales.
- **Boucle longue (partie entière) :** avancer dans la vie d'Ibn Khaldoun, compléter la *Muqaddima*.

## Structure du monde

On ne reproduit **pas** la carte réelle à l'échelle. Le monde est découpé en **régions ouvertes compactes**, chacune centrée sur une ou deux villes (comme les régions d'Assassin's Creed Origins).

| Région | Villes | Paysages |
|---|---|---|
| **Ifriqiya** | Tunis, Béjaïa | Côte, médina, oliveraies, collines |
| **Désert du Zab** | Biskra, Qal'at Ibn Salama | Oasis, palmeraies, steppe, hauts plateaux |
| **Maghreb al-Aqsa** | Fès, Tlemcen | Montagnes de l'Atlas, cédraies, vallées |
| **Al-Andalus** | Grenade, Séville | Sierra Nevada, Alhambra, plaine du Guadalquivir |
| **Égypte** | Le Caire, Alexandrie | Nil, désert, cité monumentale |
| **Hijaz** | La Mecque | Désert rocheux, route du pèlerinage |
| **Syrie** | Damas | Ghouta, remparts, camp de Tamerlan |

**Transitions entre régions :** voyages jouables condensés (traversée du désert en caravane, traversée maritime sous forme de séquence courte), qui servent aussi d'écrans de chargement intelligents.

**Les villes sont entièrement explorables à pied** : ruelles, souks, places, toits accessibles par endroits, et de nombreux **intérieurs** (mosquées, madrasas, maisons, boutiques, palais, hammams, caravansérails). Les campagnes comptent des villages, des fermes, des campements nomades, des ksour et des ruines.

## L'exploration à pied

C'est le mode principal en ville.

- **Marcher, courir, flâner** : une marche lente en ville (comme dans Red Dead Redemption 2), où l'on prend le temps de regarder.
- **Escalade légère** : murets, terrasses et toits à certains endroits, pour observer la ville ou prendre un raccourci, sans parkour à la Assassin's Creed.
- **Interactions avec le décor** : ouvrir les portes, s'asseoir, ramasser des objets, lire des documents et des inscriptions, boire à une fontaine, prier, s'abriter du soleil.
- **Mode observation** : s'arrêter, regarder, écouter. Les détails remarqués (une inscription, une conversation, un comportement) alimentent le Codex et la *Muqaddima*.
- **Comportement social** : courir dans une mosquée, bousculer les gens ou entrer armé au palais fait réagir les PNJ.

## Les PNJ et les interactions

Les villes doivent paraître **habitées**, pas décorées.

### Des PNJ vivants
- **Routines quotidiennes** : le marchand ouvre son échoppe le matin, le muezzin appelle à la prière, les étudiants vont à la madrasa, le souk se vide la nuit.
- **Métiers visibles** : potiers, tisserands, tanneurs, copistes, porteurs d'eau, forgerons, changeurs.
- **Réactions** : à l'heure, à la météo, aux événements (la peste vide les rues), à la réputation et à la fonction d'Ibn Khaldoun (on ne parle pas pareil à un étudiant et au chambellan).
- **Variété** : Arabes, Berbères, Andalous, marchands génois et vénitiens, juifs, chrétiens, esclaves, soldats, savants, nomades.

### Les interactions possibles
| Interaction | Exemple |
|---|---|
| **Parler** | Dialogues à choix avec les PNJ importants ; quelques répliques contextuelles avec tous les autres |
| **Écouter** | Surprendre des conversations, qui donnent des rumeurs et des pistes de missions |
| **Demander son chemin** | Les PNJ indiquent des lieux, à la place d'une mini-carte |
| **Commercer** | Acheter, vendre et marchander au souk |
| **Aider** | Petits services qui deviennent des missions annexes |
| **Questionner** | Recueillir des témoignages pour les enquêtes |
| **Persuader / convaincre** | Arguments débloqués par le savoir et les idées de la *Muqaddima* |
| **Saluer, respecter les usages** | Les bonnes manières améliorent la relation avec les groupes |

### Trois niveaux de PNJ
1. **Personnages principaux** : visages uniques (générés avec MakeHuman puis stylisés), dialogues complets, doublés.
2. **PNJ nommés** (marchands, imams, artisans) : routines, quelques dialogues, missions annexes.
3. **Foule** : ambiance, répliques courtes, réactions simples (simulation de foule en C++, affichage par MultiMesh au loin).

### Missions émergentes
Une partie des missions annexes naît **des rencontres** : une rumeur entendue au souk, un enfant qui demande de l'aide, une dispute à arbitrer. Le joueur n'a pas besoin de marqueurs partout sur la carte : il découvre les missions en vivant dans la ville.

## Le cheval

Le cheval sert aux **grandes distances** entre les villes et dans les campagnes, et c'est le **compagnon** du voyage.

- **Allures :** pas, trot, galop, sprint (endurance).
- **Endurance et soins :** eau et repos aux puits et aux oasis.
- **Appel du cheval :** sifflet.
- **Lien :** plus on monte le même cheval, plus il est réactif (comme dans Red Dead Redemption 2).
- **Suivi de route :** maintenir une touche pour suivre la piste jusqu'au prochain objectif, et profiter du paysage.
- **Caravanes :** rejoindre une caravane pour voyager en sécurité, avec des événements aléatoires (tempête, pillards, marchand, savant).
- Possibilité ultérieure : **chameau** pour les grandes traversées du désert.

## Les verbes du joueur

| Verbe | Description | Inspiration historique |
|---|---|---|
| **Marcher / explorer** | Flâner en ville, entrer dans les bâtiments, observer | Observateur de la vie urbaine |
| **Chevaucher** | Exploration, voyages, poursuites | Toute sa vie est faite de voyages |
| **Parler / négocier** | Dialogues à choix, arguments débloqués par le savoir | Diplomate, chambellan, négociateur |
| **Enquêter** | Collecter des témoignages, les recouper, démasquer les exagérations | « Le regard critique » de l'historien |
| **Écrire** | Le journal devient la *Muqaddima* ; chaque observation débloque des idées | Son œuvre |
| **Juger** | Rendre des verdicts au Caire, en résistant à la corruption | Grand juge malékite |
| **Se défendre** | Combat léger à l'épée et à cheval, toujours évitable si possible | Batailles, pillards, troubles |
| **Se faufiler** | Discrétion légère (évasion, rencontre secrète) | Prison de Fès, remparts de Damas |

## Systèmes de jeu

### 1. La 'asabiyya (système central)
- Chaque **groupe** (dynasties, tribus, corporations urbaines, savants) possède une valeur de **cohésion** et une valeur de **relation avec Ibn Khaldoun**.
- Les choix du joueur dans les missions **renforcent ou affaiblissent** les groupes.
- Effets : accès à des lieux, aide pendant les missions, prix, dialogues, et dans les chapitres « tribus » (Biskra), capacité à **rallier** des tribus pour un souverain.
- **Garde-fou historique :** les grands événements (chute d'un émir, victoire d'une dynastie) arrivent quoi qu'il se passe. Le joueur influence le *comment* et le *prix* payé, pas l'issue historique.

### 2. Le Codex « Kitab al-'Ibar »
- Encyclopédie dans le jeu, enrichie à chaque découverte : lieux, personnages, dynasties, concepts, objets du quotidien.
- Chaque entrée indique : **historique**, **plausible** ou **fiction**.
- **Mode Découverte** (plus tard) : visite libre sans combat, avec des visites guidées par région, sur le modèle du Discovery Tour d'Ubisoft.

### 3. Le Carnet de la Muqaddima (progression principale)
- **C'est le système central du jeu**, détaillé dans `07-philosophie.md`.
- Pas de niveaux classiques ni de points d'expérience. La progression se fait par les **idées** : observer → relier les observations → comprendre une idée → l'appliquer.
- Chaque idée donne un **livret** de résumé et, une fois maîtrisée, une **capacité** (un argument en négociation, la lecture des intentions d'une tribu, la détection des mensonges dans les témoignages, etc.).

### 4. Le regard critique (enquête)
- Le joueur rassemble des **témoignages** et des **documents**.
- Il doit repérer les **contradictions** et les **impossibilités** (« 300 000 cavaliers ? Impossible de nourrir une telle armée dans ce désert »).
- La vérité découverte change l'issue de la mission.

### 5. Réputation et charge
- Ibn Khaldoun change de **fonction** au fil de sa vie (étudiant, secrétaire, prisonnier, ambassadeur, chambellan, réfugié, juge). Chaque fonction modifie ses tenues, son accès et ses missions disponibles.

## Caméra, contrôles, interface

- Caméra à la troisième personne, rapprochée à pied et plus large à cheval.
- **Interface minimale** : pas de mini-carte encombrée. La navigation passe par l'environnement (étoiles la nuit, minarets, fumée des villes, vent), avec une boussole discrète en option.
- Carte stylisée comme une **carte médiévale** (inspirée de la cartographie d'al-Idrissi).
- Manette et clavier/souris.

## Direction artistique

- **Style stylisé peint**, inspiré des **miniatures persanes et ottomanes** et de l'**enluminure des manuscrits** : formes lisibles, couleurs franches, motifs géométriques (zellige, arabesques), avec une **lumière très travaillée** (heure dorée, poussière, ombres des souks). C'est une identité visuelle unique, belle et légère, qui tourne sur une puce graphique intégrée.
- **Références visuelles** : *The Legend of Zelda: Breath of the Wild*, *Tunic*, *Sable*, *Ghost of Tsushima* (pour la lumière et la couleur), miniatures d'Herat et de Tabriz, cartes d'al-Idrissi.
- **Matières** : textures peintes ou simplifiées à partir de Poly Haven, palettes limitées par région, shaders stylisés (contour léger, ombrage doux).
- **Palette par région** : ocre et blanc à Tunis, vert et cuivre à Fès, rouge de l'Alhambra à Grenade, or poussiéreux au Caire.
- **Architecture fidèle** : médinas, mosquées-universités, kasbahs, ksour, palais nasrides.
- **Son** : appels à la prière, marchés, vent du désert ; musique inspirée du **malouf** tunisien, de la musique **arabo-andalouse** et des **instruments traditionnels** (oud, ney, qanun, bendir).

## Ton et narration

- Récit **mature et humain** : la perte (peste, naufrage), l'ambition, la prison, l'exil, l'amitié (Ibn al-Khatib), la curiosité intellectuelle.
- **Narration encadrée** : à Damas en 1401, Ibn Khaldoun raconte sa vie à Tamerlan pour sauver la ville. Chaque acte est un souvenir joué ; entre les actes, on revient dans la tente du conquérant. Voir `08-synopsis.md`.
- **Fil rouge** : la relation avec Rachid, ami d'enfance devenu rival, dont le destin dépend des choix du joueur.
