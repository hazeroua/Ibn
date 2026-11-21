#!/bin/zsh
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
    print -u2 "Cet installateur est réservé à macOS."
    exit 1
fi

racine="${0:A:h:h}"
pwsh_bin="$(command -v pwsh || true)"
if [[ -z "$pwsh_bin" && -x "$racine/Tools/pwsh/pwsh" ]]; then
    pwsh_bin="$racine/Tools/pwsh/pwsh"
fi
if [[ -z "$pwsh_bin" ]]; then
    if ! command -v brew >/dev/null 2>&1; then
        print -u2 "Homebrew est requis pour installer PowerShell 7 automatiquement : https://brew.sh"
        exit 1
    fi
    brew install --cask powershell
    pwsh_bin="$(command -v pwsh || true)"
fi
if [[ -z "$pwsh_bin" ]]; then
    print -u2 "PowerShell 7 reste introuvable après l'installation."
    exit 1
fi

exec "$pwsh_bin" -NoProfile -File "$racine/Tools/installer-macos.ps1"
