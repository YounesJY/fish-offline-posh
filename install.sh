#!/bin/sh
# fish-offline-posh installer.
#
# The script itself is bash; this tiny POSIX preamble re-execs it so minimal
# containers (Alpine, for example) work after installing bash.
if [ -z "${BASH_VERSION:-}" ]; then
    if command -v bash >/dev/null 2>&1; then
        exec bash "$0" "$@"
    fi
    if command -v apk >/dev/null 2>&1; then
        if [ "$(id -u)" -eq 0 ]; then
            apk add --no-cache bash
        elif command -v sudo >/dev/null 2>&1; then
            sudo apk add --no-cache bash
        elif command -v doas >/dev/null 2>&1; then
            doas apk add --no-cache bash
        fi
        if command -v bash >/dev/null 2>&1; then
            exec bash "$0" "$@"
        fi
    fi
    echo "fish-offline-posh: bash is required; install bash and re-run." >&2
    exit 1
fi

set -euo pipefail

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
REPO_THEMES=$SCRIPT_DIR/themes

XDG_CONFIG_HOME=${XDG_CONFIG_HOME:-$HOME/.config}
XDG_DATA_HOME=${XDG_DATA_HOME:-$HOME/.local/share}
BIN_DIR=${XDG_BIN_HOME:-$HOME/.local/bin}

FISH_CONFIG_DIR=$XDG_CONFIG_HOME/fish
FISH_CONF_D=$FISH_CONFIG_DIR/conf.d/99-oh-my-posh.fish
FISH_FUNC=$FISH_CONFIG_DIR/functions/chooseOhMyPosh.fish

OMP_CONFIG_DIR=$XDG_CONFIG_HOME/oh-my-posh
OMP_THEME_FILE=$OMP_CONFIG_DIR/theme
OMP_THEME_DIR_FILE=$OMP_CONFIG_DIR/themes-dir
OMP_USER_THEMES=$OMP_CONFIG_DIR/themes
OMP_BIN=$BIN_DIR/oh-my-posh

INSTALL_THEMES=$XDG_DATA_HOME/fish-offline-posh/themes

OMP_VERSION=${OMP_VERSION:-latest}
SKIP_DEPS=0
SKIP_FONT=0
KEEP_CONFIG=0
NO_DEFAULT=0
UNINSTALL=0
THEME=

if [ -t 1 ]; then
    BOLD=$'\033[1m'
    DIM=$'\033[2m'
    RED=$'\033[31m'
    GREEN=$'\033[32m'
    YELLOW=$'\033[33m'
    BLUE=$'\033[34m'
    RESET=$'\033[0m'
else
    BOLD=''
    DIM=''
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    RESET=''
fi

info()  { printf '%s==>%s %s\n' "$BLUE" "$RESET" "$*"; }
ok()    { printf '%s ok %s %s\n' "$GREEN" "$RESET" "$*"; }
warn()  { printf '%swarn%s %s\n' "$YELLOW" "$RESET" "$*" >&2; }
die()   { printf '%serr %s %s\n' "$RED" "$RESET" "$*" >&2; exit 1; }

usage() {
    cat <<EOF
${BOLD}fish-offline-posh${RESET} - Fish + Oh My Posh, offline and reproducible

Usage: ./install.sh [options]

Options:
  --theme NAME         Apply and save a theme during install
  --no-default         Do not pick a default theme if none is saved
  --no-deps            Do not install missing system packages
  --no-font            Do not install a Nerd Font
  --keep-config        Do not comment out an existing 'oh-my-posh init'
                       line in config.fish (the line can override your theme)
  --uninstall          Remove the files this installer manages
  -h, --help           Show this help

Environment:
  OMP_VERSION          Oh My Posh release to install (default: latest)
                       Pin it with e.g. OMP_VERSION=v33.4.0
  XDG_CONFIG_HOME      Default: ~/.config
  XDG_DATA_HOME        Default: ~/.local/share
  XDG_BIN_HOME         Default: ~/.local/bin

After install:
  fish
  chooseOhMyPosh
EOF
}

while [ $# -gt 0 ]; do
    case $1 in
        -h|--help)
            usage
            exit 0
            ;;
        --theme)
            shift
            [ $# -gt 0 ] || die "--theme needs a value"
            THEME=$1
            ;;
        --theme=*)
            THEME=${1#*=}
            ;;
        --no-default)
            NO_DEFAULT=1
            ;;
        --no-deps)
            SKIP_DEPS=1
            ;;
        --no-font)
            SKIP_FONT=1
            ;;
        --keep-config)
            KEEP_CONFIG=1
            ;;
        --uninstall)
            UNINSTALL=1
            ;;
        *)
            die "unknown option: $1 (try --help)"
            ;;
    esac
    shift
done

# --- privilege handling ----------------------------------------------------
if [ "$(id -u)" -eq 0 ]; then
    SUDO=()
elif command -v sudo >/dev/null 2>&1; then
    SUDO=(sudo)
elif command -v doas >/dev/null 2>&1; then
    SUDO=(doas)
else
    SUDO=()
fi

run_privileged() {
    if [ ${#SUDO[@]} -eq 0 ]; then
        "$@"
    else
        "${SUDO[@]}" "$@"
    fi
}

PM=
for candidate in apt-get dnf pacman zypper apk; do
    if command -v "$candidate" >/dev/null 2>&1; then
        PM=$candidate
        break
    fi
done

# --- helpers ---------------------------------------------------------------

backup_path() {
    printf '%s.bak.%s.%s' "$1" "$(date +%Y%m%d%H%M%S)" "$$"
}

install_managed_file() {
    local src=$1 dst=$2
    [ -f "$src" ] || die "missing source file: $src"
    mkdir -p "$(dirname "$dst")"

    if [ -f "$dst" ] && cmp -s "$src" "$dst"; then
        ok "$dst is up to date"
        return 0
    fi

    if [ -e "$dst" ] || [ -L "$dst" ]; then
        local backup
        backup=$(backup_path "$dst")
        mv -f "$dst" "$backup"
        info "Backed up $dst -> $backup"
    fi

    cp -f "$src" "$dst"
    ok "Installed $dst"
}

remove_managed_file() {
    local dst=$1
    # Avoid `head | grep -q` here: with pipefail, grep -q can exit early,
    # SIGPIPE head, and make the pipeline look like a failure.
    if [ -f "$dst" ] && grep -q '^# Managed by fish-offline-posh' "$dst" 2>/dev/null; then
        rm -f "$dst"
        ok "Removed $dst"
    elif [ -L "$dst" ]; then
        rm -f "$dst"
        ok "Removed symlink $dst"
    elif [ -e "$dst" ]; then
        warn "Not removing $dst (not managed by fish-offline-posh)"
    fi
}

fish_path_env() {
    # Put the Oh My Posh binary on PATH for the fish subprocesses we launch.
    printf '%s:%s' "$(dirname "$OMP_BIN")" "${PATH:-}"
}

# --- uninstall -------------------------------------------------------------
if [ "$UNINSTALL" -eq 1 ]; then
    info "Uninstalling fish-offline-posh"
    remove_managed_file "$FISH_CONF_D"
    remove_managed_file "$FISH_FUNC"

    cfg=$FISH_CONFIG_DIR/config.fish
    if [ -f "$cfg" ] && grep -q '^# disabled by fish-offline-posh: ' "$cfg"; then
        backup=$(backup_path "$cfg")
        cp -p "$cfg" "$backup"
        awk '
            /^# disabled by fish-offline-posh: / {
                sub(/^# disabled by fish-offline-posh: /, "")
                print
                next
            }
            { print }
        ' "$cfg" > "$cfg.tmp.$$"
        mv -f "$cfg.tmp.$$" "$cfg"
        ok "Restored the commented Oh My Posh init line(s) in $cfg"
        info "Backup: $backup"
    fi

    rm -f "$OMP_THEME_DIR_FILE" "$OMP_CONFIG_DIR/bin-dir"
    rm -rf "$INSTALL_THEMES"
    rmdir "$XDG_DATA_HOME/fish-offline-posh" 2>/dev/null || true

    info "Left Oh My Posh itself, Nerd Fonts, your saved theme, and custom themes in place."
    info "Saved theme: $OMP_THEME_FILE"
    info "Custom themes: $OMP_USER_THEMES"
    exit 0
fi

# --- dependencies ----------------------------------------------------------
pm_install() {
    local pkgs=("$@")
    [ ${#pkgs[@]} -gt 0 ] || return 0

    info "Installing packages: ${pkgs[*]}"
    case $PM in
        apt-get)
            run_privileged env DEBIAN_FRONTEND=noninteractive apt-get update -qq \
                || warn "apt-get update failed; trying the install anyway"
            run_privileged env DEBIAN_FRONTEND=noninteractive \
                apt-get install -y --no-install-recommends "${pkgs[@]}"
            ;;
        dnf)
            run_privileged dnf install -y "${pkgs[@]}"
            ;;
        pacman)
            run_privileged pacman -Sy --needed --noconfirm "${pkgs[@]}"
            ;;
        zypper)
            run_privileged zypper --non-interactive install "${pkgs[@]}"
            ;;
        apk)
            run_privileged apk add --no-cache "${pkgs[@]}"
            ;;
        *)
            return 1
            ;;
    esac
}

install_dependencies() {
    if [ "$SKIP_DEPS" -eq 1 ]; then
        info "Skipping package installation (--no-deps)"
        return 0
    fi

    local required=()
    local optional=()
    command -v curl >/dev/null 2>&1 || required+=(curl)
    command -v fish >/dev/null 2>&1 || required+=(fish)
    command -v fzf >/dev/null 2>&1 || optional+=(fzf)
    command -v fc-cache >/dev/null 2>&1 || optional+=(fontconfig)

    # Minimal containers often have curl without a CA bundle. That makes the
    # Oh My Posh download fail with "error setting certificate file".
    if [ ! -f /etc/ssl/certs/ca-certificates.crt ] \
        && [ ! -f /etc/pki/tls/certs/ca-bundle.crt ] \
        && [ ! -f /etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem ]; then
        case $PM in
            pacman) required+=(ca-certificates-utils) ;;
            *)      required+=(ca-certificates) ;;
        esac
    fi

    if [ ${#required[@]} -eq 0 ] && [ ${#optional[@]} -eq 0 ]; then
        ok "Dependencies already installed"
        return 0
    fi

    if [ -z "$PM" ]; then
        warn "No supported package manager found. Install manually: ${required[*]} ${optional[*]}"
        return 0
    fi

    if [ "$(id -u)" -ne 0 ] && [ ${#SUDO[@]} -eq 0 ]; then
        warn "Cannot install packages without root/sudo. Install manually: ${required[*]} ${optional[*]}"
        return 0
    fi

    if [ ${#required[@]} -gt 0 ]; then
        pm_install "${required[@]}" || warn "Could not install required packages: ${required[*]}"
    fi
    if [ ${#optional[@]} -gt 0 ]; then
        pm_install "${optional[@]}" \
            || warn "Could not install optional packages: ${optional[*]} (the numbered picker still works)"
    fi
}

check_fish() {
    if ! command -v fish >/dev/null 2>&1; then
        die "fish is not installed. Install it with your package manager and re-run."
    fi

    local version
    version=$(fish --version 2>/dev/null | sed -n 's/.*version \([0-9][0-9.]*\).*/\1/p')
    case $version in
        0.*|1.*|2.*|3.0*|3.1*|3.2*)
            warn "fish $version is old; fish 3.3 or newer is recommended"
            ;;
        '')
            warn "Could not determine the fish version"
            ;;
        *)
            ok "fish $version"
            ;;
    esac
}

# --- Oh My Posh binary -----------------------------------------------------
install_omp() {
    if [ -x "$OMP_BIN" ] && "$OMP_BIN" --version >/dev/null 2>&1; then
        ok "Oh My Posh $("$OMP_BIN" --version 2>/dev/null) at $OMP_BIN"
        return 0
    fi

    local existing
    existing=$(command -v oh-my-posh 2>/dev/null || true)
    if [ -n "$existing" ] && "$existing" --version >/dev/null 2>&1; then
        OMP_BIN=$existing
        ok "Using existing Oh My Posh at $OMP_BIN"
        return 0
    fi

    command -v curl >/dev/null 2>&1 \
        || die "curl is required to download Oh My Posh; install curl and re-run"

    local arch
    case $(uname -m) in
        x86_64|amd64)       arch=amd64 ;;
        aarch64|arm64)      arch=arm64 ;;
        armv7*|armv6*|arm)  arch=arm ;;
        i386|i486|i586|i686) arch=386 ;;
        *) die "unsupported CPU architecture: $(uname -m)" ;;
    esac

    local version=$OMP_VERSION
    if [ "$version" != latest ]; then
        case $version in
            v*) ;;
            *) version="v$version" ;;
        esac
    fi

    local url="https://cdn.ohmyposh.dev/releases/$version/posh-linux-$arch"
    local tmp="$OMP_BIN.tmp.$$"
    mkdir -p "$BIN_DIR"

    local curl_args=(-fL --retry 3 --connect-timeout 15 -sS)
    if [ -t 1 ]; then
        curl_args+=(--progress-bar)
    fi

    info "Downloading Oh My Posh ($version, linux-$arch)"
    if ! curl "${curl_args[@]}" -o "$tmp" "$url"; then
        rm -f "$tmp"
        die "download failed: $url"
    fi

    chmod +x "$tmp"
    if ! "$tmp" --version >/dev/null 2>&1; then
        rm -f "$tmp"
        die "the downloaded binary does not run on this system"
    fi

    mv -f "$tmp" "$OMP_BIN"
    ok "Oh My Posh $("$OMP_BIN" --version 2>/dev/null) installed at $OMP_BIN"
}

record_bin_dir() {
    local dir
    dir=$(dirname "$OMP_BIN")
    mkdir -p "$OMP_CONFIG_DIR"
    printf '%s\n' "$dir" > "$OMP_CONFIG_DIR/bin-dir"
    ok "Recorded Oh My Posh binary directory: $dir"
}

# --- themes ---------------------------------------------------------------
install_themes() {
    # Use globbing instead of find: minimal images (e.g. openSUSE Tumbleweed)
    # ship without findutils.
    local theme theme_count=0
    for theme in "$REPO_THEMES"/*.omp.*; do
        [ -e "$theme" ] || continue
        theme_count=$((theme_count + 1))
    done
    [ "$theme_count" -gt 0 ] || die "no bundled themes found in $REPO_THEMES"

    rm -rf "$INSTALL_THEMES"
    mkdir -p "$INSTALL_THEMES"
    cp -f "$REPO_THEMES"/*.omp.* "$INSTALL_THEMES"/

    mkdir -p "$OMP_CONFIG_DIR" "$OMP_USER_THEMES"
    printf '%s\n' "$INSTALL_THEMES" > "$OMP_THEME_DIR_FILE"
    ok "$theme_count themes installed in $INSTALL_THEMES"
}

# --- fish config -----------------------------------------------------------
install_fish_files() {
    install_managed_file "$SCRIPT_DIR/fish/conf.d/99-oh-my-posh.fish" "$FISH_CONF_D"
    install_managed_file "$SCRIPT_DIR/fish/functions/chooseOhMyPosh.fish" "$FISH_FUNC"
}

disable_existing_omp() {
    local cfg=$FISH_CONFIG_DIR/config.fish
    [ -f "$cfg" ] || return 0

    local active_pattern='^[[:space:]]*(oh-my-posh[[:space:]]+init|source[[:space:]]*\(.*oh-my-posh[[:space:]]+init|eval[[:space:]].*oh-my-posh[[:space:]]+init)'
    if ! grep -Eq "$active_pattern" "$cfg"; then
        if grep -Eq '^[[:space:]]*[^#[:space:]].*oh-my-posh[[:space:]]+init' "$cfg"; then
            warn "Found an Oh My Posh init line in $cfg that this installer cannot safely disable."
            warn "Remove it manually, or it will override your chosen theme."
        fi
        return 0
    fi

    if [ "$KEEP_CONFIG" -eq 1 ]; then
        warn "Leaving $cfg alone (--keep-config)."
        warn "Its Oh My Posh init line runs after conf.d and can override the saved theme."
        return 0
    fi

    local backup
    backup=$(backup_path "$cfg")
    cp -p "$cfg" "$backup"

    awk '
        /^[[:space:]]*#/ { print; next }
        /^[[:space:]]*oh-my-posh[[:space:]]+init/ {
            print "# disabled by fish-offline-posh: " $0
            next
        }
        /^[[:space:]]*source[[:space:]]*\(.*oh-my-posh[[:space:]]+init/ {
            print "# disabled by fish-offline-posh: " $0
            next
        }
        /^[[:space:]]*eval[[:space:]].*oh-my-posh[[:space:]]+init/ {
            print "# disabled by fish-offline-posh: " $0
            next
        }
        { print }
    ' "$cfg" > "$cfg.tmp.$$"

    if cmp -s "$cfg" "$cfg.tmp.$$"; then
        rm -f "$cfg.tmp.$$"
        warn "Found Oh My Posh init in $cfg but could not safely disable it; remove it manually."
        return 0
    fi

    mv -f "$cfg.tmp.$$" "$cfg"
    ok "Commented out the existing Oh My Posh init line in $cfg"
    info "Backup: $backup"

    local other
    for other in "$FISH_CONFIG_DIR"/conf.d/*.fish; do
        [ -e "$other" ] || continue
        [ "$other" = "$FISH_CONF_D" ] && continue
        if grep -Eq '^[[:space:]]*[^#[:space:]].*oh-my-posh[[:space:]]+init' "$other"; then
            warn "Also found an Oh My Posh init line in $other; remove it to avoid overriding your theme."
        fi
    done
}

# --- initial theme ---------------------------------------------------------
set_initial_theme() {
    if [ -n "$THEME" ]; then
        return 0
    fi

    [ -f "$OMP_THEME_FILE" ] && return 0

    # Migrate the state file used by the old setup-fish-omp.sh script.
    local old_file=$FISH_CONFIG_DIR/current_posh_theme
    if [ -f "$old_file" ]; then
        local old_theme
        old_theme=$(head -n 1 "$old_file" 2>/dev/null || true)
        if [ -n "$old_theme" ]; then
            if [ ! -f "$INSTALL_THEMES/$old_theme" ] && [ -f "$HOME/.poshthemes/$old_theme" ]; then
                cp -f "$HOME/.poshthemes/$old_theme" "$OMP_USER_THEMES/$old_theme"
            fi
            if [ -f "$INSTALL_THEMES/$old_theme" ] || [ -f "$OMP_USER_THEMES/$old_theme" ]; then
                printf '%s\n' "$old_theme" > "$OMP_THEME_FILE"
                ok "Migrated saved theme from the old installer: $old_theme"
                return 0
            fi
        fi
    fi

    [ "$NO_DEFAULT" -eq 1 ] && return 0

    local default=jandedobbeleer.omp.json
    if [ ! -f "$INSTALL_THEMES/$default" ]; then
        local candidate
        for candidate in "$INSTALL_THEMES"/*.omp.json; do
            [ -e "$candidate" ] || continue
            default=${candidate##*/}
            break
        done
    fi
    if [ -n "$default" ] && [ -f "$INSTALL_THEMES/$default" ]; then
        printf '%s\n' "$default" > "$OMP_THEME_FILE"
        ok "Default theme: $default (change it with chooseOhMyPosh)"
    fi
}

apply_requested_theme() {
    [ -n "$THEME" ] || return 0
    if ! PATH=$(fish_path_env) fish --no-config -c 'source $argv[1]; chooseOhMyPosh --set $argv[2]' \
        "$FISH_FUNC" "$THEME"; then
        die "could not apply theme '$THEME' (see chooseOhMyPosh --list)"
    fi
}

# --- font ------------------------------------------------------------------
install_font() {
    if [ "$SKIP_FONT" -eq 1 ]; then
        info "Skipping Nerd Font installation (--no-font)"
        return 0
    fi

    if [ -f /.dockerenv ] || [ -f /run/.containerenv ]; then
        info "Container detected; skipping Nerd Font installation (fonts belong on the host)"
        return 0
    fi

    if command -v fc-list >/dev/null 2>&1 && fc-list 2>/dev/null | grep -i 'nerd font' >/dev/null; then
        ok "A Nerd Font is already installed"
        return 0
    fi

    info "Installing Meslo Nerd Font (this can take a minute)"
    if "$OMP_BIN" font install Meslo >/dev/null 2>&1; then
        if command -v fc-cache >/dev/null 2>&1; then
            fc-cache -f >/dev/null 2>&1 || warn "fc-cache failed; log out and back in"
        fi
        ok "Meslo Nerd Font installed; set your terminal font to 'MesloLGM Nerd Font'"
    else
        warn "Nerd Font install failed. See https://ohmyposh.dev/docs/installation/fonts"
    fi
}

# --- verify ----------------------------------------------------------------
verify_install() {
    local count
    count=$(fish --no-config -c 'source $argv[1]; chooseOhMyPosh --list | count' "$FISH_FUNC" 2>/dev/null || echo 0)
    if [ "${count:-0}" -gt 0 ]; then
        ok "chooseOhMyPosh loads ($count local themes)"
    else
        warn "chooseOhMyPosh did not list any themes; re-run install.sh"
    fi

    local current
    current=$(head -n 1 "$OMP_THEME_FILE" 2>/dev/null || true)
    if [ -n "$current" ]; then
        local path=$INSTALL_THEMES/$current
        [ -f "$path" ] || path=$OMP_USER_THEMES/$current
        if [ -f "$path" ] && "$OMP_BIN" print primary --config "$path" --shell fish --plain >/dev/null 2>&1; then
            ok "Saved theme renders: $current"
        else
            warn "Saved theme '$current' could not be rendered; run chooseOhMyPosh to pick another"
        fi
    fi
}

# --- main ------------------------------------------------------------------
if [ "$(id -u)" -eq 0 ]; then
    warn "Running as root: files go under /root and fonts are installed system-wide."
    warn "For a normal desktop, run this as your user instead (without sudo)."
fi

info "fish-offline-posh setup"
info "Repo: $SCRIPT_DIR"

install_dependencies
check_fish
install_omp
install_themes
record_bin_dir
install_fish_files
apply_requested_theme
disable_existing_omp
set_initial_theme
verify_install
install_font

printf '\n%s✓ fish-offline-posh is installed%s\n\n' "$GREEN" "$RESET"
cat <<EOF
Next steps:
  1. Open a new terminal (or run: exec fish)
  2. Run: chooseOhMyPosh
  3. Use a Nerd Font in your terminal settings for icons

Files managed by this installer:
  $FISH_CONF_D
  $FISH_FUNC

Themes:  $INSTALL_THEMES
Saved:   $OMP_THEME_FILE
Custom:  $OMP_USER_THEMES

Remove the managed files with: ./install.sh --uninstall
EOF
