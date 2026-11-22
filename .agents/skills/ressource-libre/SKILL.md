---
name: ressource-libre
description: Ajouter une texture, un modèle, une animation ou un son utilisable commercialement avec provenance, licence, téléchargement contrôlé, réglages d'import et budget mémoire.
---

# Ajouter une ressource libre

Ordre de préférence : téléchargement automatisé depuis la source officielle, génération par un script du dépôt, puis téléchargement manuel documenté dans `Docs/ressources-a-telecharger.md`.

- Accepter uniquement CC0 ou une licence commerciale compatible et enregistrer la preuve exacte de licence.
- Ne pas exécuter de script, add-on ou projet moteur fourni par un tiers. Inspecter les archives et préférer les formats de données GLB/glTF, FBX, OBJ et images.
- Conserver URL, date, nom, taille et SHA-256. Ne pas versionner une source dont la licence interdit la redistribution.
- Déclarer la ressource dans `Projet/data/ressources.json` : section `textures` pour un sol Terrain3D (quatre cartes), section `fichiers` pour un fichier isolé, avec une adresse immuable. `Projet/valider.bat` télécharge dans `Projet/ressources/telechargees/` (hors Git) et fige les SHA-256 dans `Projet/data/ressources.lock.json`.
- Un module tiers (code, addon) va dans `Tools/versions.json` avec version, adresse et SHA-256, après accord du porteur du projet.
- Ajouter toute ressource livrée avec le jeu à `Docs/credits.md`, avec l'attribution exigée par sa licence.
- Mesurer la mémoire vidéo et le rendu après import. Une texture 2K exige une justification visuelle.
- Faire relire l'apparence et l'adéquation historique lorsque la ressource représente un lieu, une personne ou un objet d'époque.
