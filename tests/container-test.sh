#!/bin/sh
# Runs inside a fresh container. The repo is mounted read-only at /repo.
set -eu

cd /repo

echo "==> Installing in $(. /etc/os-release 2>/dev/null && echo "${PRETTY_NAME:-unknown}")"
./install.sh --no-font --theme catppuccin_mocha

echo "==> Checking the saved theme"
current=$(fish -i -c 'chooseOhMyPosh --current' 2>/dev/null | tail -n 1)
[ "$current" = "catppuccin_mocha.omp.json" ] || {
    echo "unexpected current theme: $current" >&2
    exit 1
}

echo "==> Checking the local theme list"
count=$(fish -i -c 'chooseOhMyPosh --list' 2>/dev/null | wc -l | tr -d ' ')
[ "$count" -eq 125 ] || {
    echo "expected 125 themes, got $count" >&2
    exit 1
}

echo "==> Checking that the startup snippet configured Oh My Posh"
fish -i -c 'test -n "$POSH_CONFIG"'
fish -i -c 'oh-my-posh print primary --config "$POSH_CONFIG" --shell fish >/dev/null'

echo "==> Switching themes and checking persistence"
fish -i -c 'chooseOhMyPosh --set agnoster' 2>/dev/null
current=$(fish -i -c 'chooseOhMyPosh --current' 2>/dev/null | tail -n 1)
[ "$current" = "agnoster.omp.json" ] || {
    echo "theme switch did not persist: $current" >&2
    exit 1
}

echo "==> Uninstalling managed files"
./install.sh --uninstall
[ ! -e "$HOME/.config/fish/conf.d/99-oh-my-posh.fish" ] || {
    echo "conf.d file was not removed" >&2
    exit 1
}
[ ! -e "$HOME/.config/fish/functions/chooseOhMyPosh.fish" ] || {
    echo "function file was not removed" >&2
    exit 1
}

echo "==> OK"
