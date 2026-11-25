#!/usr/bin/env bash
# Fast check in a throwaway HOME. Your real fish config is never touched.
#
# Requires fish and an existing oh-my-posh on PATH. The test does not download
# anything. For the full distro matrix, run tests/run.sh instead.
set -euo pipefail

REPO_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
TMP_ROOT=${TMPDIR:-/tmp}
TEST_HOME=$(mktemp -d "$TMP_ROOT/fish-offline-posh-test.XXXXXX")
trap 'rm -rf "$TEST_HOME"' EXIT

export HOME=$TEST_HOME
export XDG_CONFIG_HOME=$TEST_HOME/.config
export XDG_DATA_HOME=$TEST_HOME/.local/share

FISH_CONFIG=$XDG_CONFIG_HOME/fish
FISH_FUNC=$FISH_CONFIG/functions/chooseOhMyPosh.fish
FISH_CONF_D=$FISH_CONFIG/conf.d/99-oh-my-posh.fish
THEME_FILE=$XDG_CONFIG_HOME/oh-my-posh/theme

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

pass() {
    printf 'ok   %s\n' "$*"
}

# Run chooseOhMyPosh without loading the host's fish config.
fish_cmd() {
    fish --no-config -c 'source $argv[1]; chooseOhMyPosh $argv[2..-1]' "$FISH_FUNC" "$@"
}

command -v fish >/dev/null 2>&1 || fail "fish is required"
command -v oh-my-posh >/dev/null 2>&1 \
    || fail "oh-my-posh must already be on PATH (this test never downloads it)"

mkdir -p "$FISH_CONFIG"
printf 'set -g fish_greeting\noh-my-posh init fish | source\n' > "$FISH_CONFIG/config.fish"

cd "$REPO_DIR"
echo "==> Installing into $TEST_HOME"
if ! ./install.sh --no-deps --no-font > "$TEST_HOME/install.log" 2>&1; then
    cat "$TEST_HOME/install.log" >&2
    fail "install.sh exited non-zero"
fi
pass "install.sh finished"

expected=0
for theme in "$REPO_DIR"/themes/*.omp.*; do
    [ -e "$theme" ] || continue
    expected=$((expected + 1))
done
[ "$expected" -gt 0 ] || fail "no bundled themes in $REPO_DIR/themes"

count=$(fish_cmd --list | wc -l | tr -d ' ')
[ "$count" -eq "$expected" ] || fail "expected $expected themes, got $count"
pass "$count local themes listed"

current=$(fish_cmd --current)
[ -n "$current" ] && [ -f "$XDG_DATA_HOME/fish-offline-posh/themes/$current" ] \
    || fail "default theme is missing or does not exist: $current"
pass "default theme is $current"

[ -f "$FISH_CONF_D" ] && [ -f "$FISH_FUNC" ] || fail "managed fish files are missing"
grep -q '^oh-my-posh init fish | source$' "$FISH_CONFIG/config.fish" \
    && fail "the existing oh-my-posh init line was not disabled"
pass "existing init line disabled and managed files installed"

fish_cmd --set agnoster >/dev/null
[ "$(fish_cmd --current)" = "agnoster.omp.json" ] || fail "theme switch did not persist"
pass "theme switch persisted"

# The startup snippet must find Oh My Posh without help from the installer.
path_check=$(fish -c "source '$FISH_CONF_D'; command -sq oh-my-posh; and echo yes" 2>/dev/null)
[ "$path_check" = "yes" ] || fail "the startup snippet did not put oh-my-posh on PATH"
pass "startup snippet finds oh-my-posh"

./install.sh --uninstall >/dev/null
[ ! -e "$FISH_CONF_D" ] && [ ! -e "$FISH_FUNC" ] || fail "uninstall left managed files behind"
grep -q '^oh-my-posh init fish | source$' "$FISH_CONFIG/config.fish" \
    || fail "uninstall did not restore the original init line"
pass "uninstall restored the original config"

echo
echo "All local tests passed."
