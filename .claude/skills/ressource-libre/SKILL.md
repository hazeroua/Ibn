---
name: ressource-libre
description: Sélectionne une ressource libre pour le reboot. Le premier ticket qui importe une ressource dans `Projet/` crée son manifeste et son étape d'import dans `Projet/valider.bat`.
---
# Ajouter une ressource libre

## Ordre de préférence
1. **Téléchargement automatique** (aucune action du porteur du projet) : Poly Haven par son API (déjà en place), puis autres sources CC0 téléchargeables par script.
2. **Génération par script** : Blender en ligne de commande, dans `Projet/outils/`.
3. **Téléchargement manuel** (dernier recours, ressource derrière un compte) : l'ajouter à `Docs/ressources-a-telecharger.md` (nom, lien, licence, raison, dossier de destination) et attendre son dépôt dans `Import/`.

## Import après #63

- #63 n'importe aucune ressource externe. Le premier ticket qui en a besoin (textures de #64 ou #66) crée `Projet/data/ressources.json` (source, licence, empreinte SHA-256), le dossier `Projet/assets/` et l'étape de téléchargement vérifié dans `Projet/outils/valider.ps1`.
- Ne jamais ajouter une ressource du reboot au manifeste ou aux dossiers de l'ancien `Game/`.
- Les fichiers téléchargés peuvent rester non versionnés si le manifeste, la licence, la somme de contrôle et les réglages d'import permettent de les reproduire.

## Règles
- **Licence** : uniquement CC0 ou licence qui autorise un usage commercial ; la noter dans le manifeste.
- **Budget** : vérifier la mémoire vidéo dans le rapport actif après l'ajout ; une texture 2K coûte environ quatre fois une 1K.
- **Style** : faire valider l'apparence par l'agent `directeur-artistique` (capture à l'appui).
