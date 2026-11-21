---
name: ressource-libre
description: Sélectionne une ressource libre pour le reboot. L'import dans le nouveau projet est suspendu jusqu'à ce que #63 définisse manifeste, dossiers et pipeline.
---
# Ajouter une ressource libre

## Ordre de préférence
1. **Téléchargement automatique** (aucune action du porteur du projet) : Poly Haven par son API (déjà en place), puis autres sources CC0 téléchargeables par script.
2. **Génération par script** : Blender en ligne de commande, dans un emplacement défini par le nouveau socle après #63.
3. **Téléchargement manuel** (dernier recours, ressource derrière un compte) : l'ajouter à `Docs/ressources-a-telecharger.md` (nom, lien, licence, raison, dossier de destination) et attendre son dépôt dans `Import/`.

## Import après #63

- #63 doit définir le manifeste, les dossiers d'assets, le téléchargement vérifié et la commande d'import du nouveau projet.
- Ne jamais ajouter une ressource du reboot au manifeste ou aux dossiers de l'ancien `Game/`.
- Les fichiers téléchargés peuvent rester non versionnés si le manifeste, la licence, la somme de contrôle et les réglages d'import permettent de les reproduire.

## Règles
- **Licence** : uniquement CC0 ou licence qui autorise un usage commercial ; la noter dans le manifeste.
- **Budget** : vérifier la mémoire vidéo dans le rapport actif après l'ajout ; une texture 2K coûte environ quatre fois une 1K.
- **Style** : faire valider l'apparence par l'agent `directeur-artistique` (capture à l'appui).
