"""Hook PostToolUse (Write, Edit, MultiEdit) : analyse et vérifie le format de chaque fichier GDScript modifié.

Utilise gdtoolkit installé dans l'environnement Python des outils (Tools/venv, voir Tools/dependances.ps1).
Code de sortie 2 = problème renvoyé à Claude pour correction immédiate.
"""
import json
import os
import subprocess
import sys


def python_outils(racine: str) -> str:
    for relatif in ("Tools/venv/Scripts/python.exe", "Tools/venv/bin/python"):
        chemin = os.path.join(racine, relatif)
        if os.path.exists(chemin):
            return chemin
    return ""


def main() -> int:
    donnees = json.load(sys.stdin)
    chemin = str(donnees.get("tool_input", {}).get("file_path", ""))
    if not chemin.endswith(".gd") or "/addons/" in chemin.replace("\\", "/"):
        return 0
    racine = os.environ.get("CLAUDE_PROJECT_DIR", os.getcwd())
    python = python_outils(racine)
    if not python:
        print("Analyse GDScript impossible : Tools/venv absent, lancer Tools/installer.ps1.", file=sys.stderr)
        return 0
    jeu = os.path.join(racine, "Game")
    problemes = []
    for commande in (
        [python, "-m", "gdtoolkit.linter", chemin],
        [python, "-m", "gdtoolkit.formatter", "--check", "--line-length", "140", chemin],
    ):
        resultat = subprocess.run(commande, cwd=jeu, capture_output=True, text=True, check=False)
        if resultat.returncode != 0:
            problemes.append((resultat.stdout + resultat.stderr).strip())
    if problemes:
        print(
            "GDScript non conforme (corriger maintenant ; formatage automatique : "
            f"{python} -m gdtoolkit.formatter --line-length 140 {chemin}) :\n" + "\n".join(problemes),
            file=sys.stderr,
        )
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
