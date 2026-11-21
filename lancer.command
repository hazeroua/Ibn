#!/bin/zsh
set -euo pipefail

racine="${0:A:h}"
pwsh_bin="$(command -v pwsh || true)"
if [[ -z "$pwsh_bin" && -x "$racine/Tools/pwsh/pwsh" ]]; then
    pwsh_bin="$racine/Tools/pwsh/pwsh"
fi
if [[ -z "$pwsh_bin" ]]; then
    print -u2 "PowerShell 7 est introuvable. Lancez d'abord Tools/installer-macos.command."
    exit 1
fi

exec "$pwsh_bin" -NoProfile -File "$racine/Scripts/Pipeline/lancer.ps1" "$@"
