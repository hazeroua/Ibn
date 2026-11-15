"""Hook PreToolUse (Write, Edit, MultiEdit) : applique la règle absolue n° 1 de CLAUDE.md.

Refuse l'écriture de code contenant des marqueurs de raccourci (TODO, FIXME, HACK, « provisoire »,
« pour l'instant », « plus tard », stub…). Seul le texte écrit est examiné, pas le texte remplacé :
supprimer un TODO reste possible. Code de sortie 2 = écriture refusée, message renvoyé à Claude.
"""
import json
import re
import sys

EXTENSIONS_CODE = (".gd", ".cpp", ".h", ".hpp", ".ps1", ".py", ".gdshader", ".cfg", ".tscn", ".tres")
NOMS_CODE = ("SConstruct",)
MOTIFS = re.compile(
    r"\b(TODO|FIXME|HACK|XXX)\b"
    r"|provisoire|temporaire|pour l['’]instant|plus tard|à améliorer|a ameliorer"
    r"|\bstub\b|placeholder|for now|good enough|optimi[sz]e later",
    re.IGNORECASE,
)


def main() -> int:
    donnees = json.load(sys.stdin)
    entree = donnees.get("tool_input", {})
    chemin = str(entree.get("file_path", ""))
    chemin_normalise = chemin.replace("\\", "/")
    if "/.claude/hooks/" in chemin_normalise or chemin_normalise.startswith(".claude/hooks/"):
        return 0
    nom = chemin_normalise.rsplit("/", 1)[-1]
    if not (nom.endswith(EXTENSIONS_CODE) or nom in NOMS_CODE):
        return 0
    textes = [entree.get("content", ""), entree.get("new_string", "")]
    textes += [modif.get("new_string", "") for modif in entree.get("edits", []) or []]
    for texte in textes:
        trouve = MOTIFS.search(str(texte or ""))
        if trouve:
            print(
                f"Refusé par la règle absolue n° 1 de CLAUDE.md : « {trouve.group(0)} » dans {nom}. "
                "Écris directement la version définitive et optimisée pour le pire cas, sans marqueur de raccourci.",
                file=sys.stderr,
            )
            return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
