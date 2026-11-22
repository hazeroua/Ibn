---
name: ressource-libre
description: Ajoute une ressource libre (texture, modèle, son) au jeu : manifeste data/ressources.json, téléchargement vérifié par empreinte, transformation par un constructeur.
---
# Ajouter une ressource libre

## Ordre de préférence
1. **Téléchargement automatique** (aucune action du porteur du projet) : Poly Haven par son API (déjà en place), puis autres sources CC0 téléchargeables par script.
2. **Génération par script** : Blender en ligne de commande, dans `Projet/outils/`.
3. **Téléchargement manuel** (dernier recours, ressource derrière un compte) : l'ajouter à `Docs/ressources-a-telecharger.md` (nom, lien, licence, raison, dossier de destination) et attendre son dépôt dans `Import/`.

## Import dans Projet/

- Déclarer la ressource dans `Projet/data/ressources.json` (source, page, licence CC0, adresses https) : section `textures` pour un sol Terrain3D (albédo, normale, rugosité, hauteur), section `fichiers` pour un fichier isolé (particules, sons…), en épinglant une adresse immuable (commit Git, fichier versionné). `valider.bat` la télécharge dans `Projet/ressources/telechargees/<clé>/` et enregistre son empreinte SHA-256 dans `Projet/data/ressources.lock.json` au premier téléchargement : relire le fichier (Read pour une image) avant de committer le verrou.
- La transformer par un constructeur (`world/<scène>/*_builder.gd`) vers `Projet/generated/`, jamais à la main.
- Ne jamais ajouter une ressource du reboot au manifeste ou aux dossiers de l'ancien `Game/`.
- Les fichiers téléchargés peuvent rester non versionnés si le manifeste, la licence, la somme de contrôle et les réglages d'import permettent de les reproduire.

## Règles
- **Licence** : uniquement CC0 ou licence qui autorise un usage commercial ; la noter dans le manifeste.
- **Budget** : vérifier la mémoire vidéo dans le rapport actif après l'ajout ; une texture 2K coûte environ quatre fois une 1K.
- **Style** : faire valider l'apparence par l'agent `directeur-artistique` (capture à l'appui).
- Un module tiers (code, addon) n'est pas une ressource : il va dans `Tools/versions.json` avec version, adresse et empreinte SHA-256, après accord du porteur du projet.
- Toute ressource livrée avec le jeu est ajoutée à `Docs/credits.md`, avec l'attribution exigée par sa licence.
