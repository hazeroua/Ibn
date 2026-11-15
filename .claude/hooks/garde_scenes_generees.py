"""Hook PreToolUse (Write, Edit, MultiEdit) : les scènes générées ne se modifient jamais à la main.

Une scène Game/world/<carte>/<carte>.tscn est produite par Game/tools/builders/build_<carte>.gd à partir
de Game/data/<carte>/. Le dossier Game/.godot/ est géré par Godot. Code de sortie 2 = écriture refusée.
"""
import json
import re
import sys


def main() -> int:
    donnees = json.load(sys.stdin)
    chemin = str(donnees.get("tool_input", {}).get("file_path", "")).replace("\\", "/")
    if "/Game/.godot/" in chemin or chemin.startswith("Game/.godot/"):
        print("Refusé : Game/.godot/ est géré par Godot (relancer Scripts/Pipeline/importer.ps1).", file=sys.stderr)
        return 2
    scene = re.search(r"(?:^|/)Game/world/([a-z0-9_]+)/\1\.tscn$", chemin)
    if scene:
        carte = scene.group(1)
        print(
            f"Refusé : {carte}.tscn est une scène générée. Modifier Game/data/{carte}/ ou "
            f"Game/world/{carte}/ (constructeur), puis lancer Scripts/Pipeline/construire.ps1 -Constructeur {carte}.",
            file=sys.stderr,
        )
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
