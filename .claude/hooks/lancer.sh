#!/usr/bin/env bash
# Lance un hook Python avec l'interpréteur disponible (python3, sinon python).
# Sous Windows, « python3 » peut être un raccourci du Microsoft Store qui ne fonctionne pas : on le teste.
set -u
hook="$(dirname "$0")/$1"
for candidat in python3 python; do
    if command -v "$candidat" >/dev/null 2>&1 && "$candidat" -c "" >/dev/null 2>&1; then
        exec "$candidat" "$hook"
    fi
done
echo "Hook $1 : Python introuvable, vérification impossible." >&2
exit 1
