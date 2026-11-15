---
name: ressource-libre
description: Ajoute une ressource graphique ou sonore libre (Poly Haven, Quaternius, Kenney, Freesound CC0) au projet, avec licence, téléchargement automatique, réglages d'import et budget mémoire. À utiliser dès qu'une tâche a besoin d'une texture, d'un modèle, d'une animation ou d'un son.
---
# Ajouter une ressource libre

## Ordre de préférence
1. **Téléchargement automatique** (aucune action du porteur du projet) : Poly Haven par son API (déjà en place), puis autres sources CC0 téléchargeables par script.
2. **Génération par script** : Blender en ligne de commande (`Scripts/Blender/`), dans le style du jeu.
3. **Téléchargement manuel** (dernier recours, ressource derrière un compte) : l'ajouter à `Docs/ressources-a-telecharger.md` (nom, lien, licence, raison, dossier de destination) et attendre son dépôt dans `Import/`.

## Poly Haven
- Ajouter une entrée à `Game/data/assets/polyhaven.json` : `id`, `resolution` (1k par défaut ; 2k seulement si une capture le justifie), `maps` (`diff`, `nor_gl`, `rough`…), `usage`.
- Lancer `Scripts/Pipeline/importer-ressources.ps1` puis `importer.ps1` : les fichiers arrivent dans `Game/assets/textures/polyhaven/<id>/<id>_<carte>.jpg`, vérifiés par MD5, avec des réglages d'import explicites (compression VRAM, mipmaps, cartes de normales).
- Les fichiers téléchargés ne sont pas versionnés : le manifeste est la source de vérité.

## Règles
- **Licence** : uniquement CC0 ou licence qui autorise un usage commercial ; la noter dans le manifeste.
- **Budget** : vérifier la mémoire vidéo dans `resume.json` après l'ajout ; une texture 2K coûte environ 4 fois une 1K.
- **Style** : faire valider l'apparence par l'agent `directeur-artistique` (capture à l'appui).
