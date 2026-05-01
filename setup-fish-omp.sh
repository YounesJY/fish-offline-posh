#!/bin/bash
# Fish Shell + Oh My Posh + Nerd Fonts - One-Click Installer
# Tested on: Ubuntu 20.04/22.04/24.04, Zorin OS 17/18, Debian 11/12

set -e

# Suppress interactive prompts
export DEBIAN_FRONTEND=noninteractive
export TZ=Etc/UTC

# Detect if running as root
if [ "$EUID" -eq 0 ]; then
    sh_c=''
else
    sh_c='sudo'
fi

echo "🐟 Starting Fish + Oh My Posh setup..."

# Install dependencies
echo "📦 Installing dependencies..."
$sh_c apt update
$sh_c apt install -y --no-install-recommends \
    software-properties-common \
    gnupg \
    git curl wget unzip \
    fzf fish \
    fontconfig

# Ensure Fish is 3.6.0+ (fixes commandline --is-valid bug)
echo "🔍 Checking Fish version..."
current_fish_version=$(fish --version 2>/dev/null | grep -oP '\d+\.\d+\.\d+' || echo "0.0.0")
required_version="3.6.0"
if [ "$(printf '%s\n' "$required_version" "$current_fish_version" | sort -V | head -n1)" != "$required_version" ]; then
    echo "⚠️  Upgrading Fish via PPA..."
    $sh_c add-apt-repository -y ppa:fish-shell/release-3
    $sh_c apt update
    $sh_c apt install -y fish
fi

# Download Oh My Posh binary
echo "⬇️  Installing Oh My Posh..."
mkdir -p "$HOME/bin"
if [ ! -f "$HOME/bin/oh-my-posh" ]; then
    curl -L -o "$HOME/bin/oh-my-posh" https://github.com/JanDeDobbeleer/oh-my-posh/releases/latest/download/posh-linux-amd64
    chmod +x "$HOME/bin/oh-my-posh"
fi
fish -c 'if not contains "$HOME/bin" $fish_user_paths; set -U fish_user_paths $HOME/bin $fish_user_paths; end'

# Download all Oh My Posh themes
THEME_DIR="$HOME/.poshthemes"
mkdir -p "$THEME_DIR"
if [ ! -f "$THEME_DIR/jandedobbeleer.omp.json" ]; then
    echo "🎨 Downloading themes..."
    git clone --depth 1 https://github.com/JanDeDobbeleer/oh-my-posh.git "$THEME_DIR/temp"
    mv "$THEME_DIR/temp/themes"/* "$THEME_DIR/"
    rm -rf "$THEME_DIR/temp"
fi

# Install Nerd Font (optional, continues on failure)
echo "🔤 Installing Meslo Nerd Font..."
FONT_DIR="$HOME/.local/share/fonts"
mkdir -p "$FONT_DIR"
cd "$FONT_DIR"
if [ ! -f "Meslo LG S Regular Nerd Font Complete.ttf" ]; then
    wget -q --show-progress --timeout=30 https://github.com/ryanoasis/nerd-fonts/releases/latest/download/Meslo.zip 2>/dev/null || echo "⚠️  Font download failed, continuing..."
    if [ -f "Meslo.zip" ]; then
        unzip -o Meslo.zip 2>/dev/null
        rm Meslo.zip
        fc-cache -fv 2>/dev/null
    fi
fi
cd "$HOME"

# Create chooseposh function
mkdir -p "$HOME/.config/fish/functions"
cat << 'EOF' > "$HOME/.config/fish/functions/chooseposh.fish"
function chooseposh --description "Interactive Oh My Posh theme switcher"
    set theme_dir $HOME/.poshthemes
    set config_file $HOME/.config/fish/current_posh_theme
    set themes (find $theme_dir -maxdepth 1 \( -name "*.omp.*" \) -printf "%f\n" 2>/dev/null | sort)
    if test (count $themes) -eq 0
        echo "❌ No themes found in $theme_dir"
        return 1
    end
    set theme (printf "%s\n" $themes | fzf --prompt="Select a theme: " --height=40% --border)
    if test -z "$theme"
        echo "No theme selected."
        return
    end
    echo $theme > $config_file
    echo "✨ Applying theme: $theme"
    oh-my-posh init fish --config "$theme_dir/$theme" | source
end
EOF

# Configure Fish to load saved theme on startup
mkdir -p "$HOME/.config/fish"
cat << 'EOF' > "$HOME/.config/fish/config.fish"
set -g theme_dir $HOME/.poshthemes
set -g config_file $HOME/.config/fish/current_posh_theme

if test -f $config_file
    set last_theme (cat $config_file)
    if test -f "$theme_dir/$last_theme"
        oh-my-posh init fish --config "$theme_dir/$last_theme" | source
    else
        set first_theme (find $theme_dir -maxdepth 1 \( -name "*.omp.*" \) -printf "%f\n" 2>/dev/null | head -n1)
        if test -n "$first_theme"
            oh-my-posh init fish --config "$theme_dir/$first_theme" | source
        else
            oh-my-posh init fish | source
        end
    end
else
    set first_theme (find $theme_dir -maxdepth 1 \( -name "*.omp.*" \) -printf "%f\n" 2>/dev/null | head -n1)
    if test -n "$first_theme"
        oh-my-posh init fish --config "$theme_dir/$first_theme" | source
    else
        oh-my-posh init fish | source
    end
end
EOF

# Clean Oh My Posh cache
rm -rf "$HOME/.cache/oh-my-posh"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Setup complete!"
echo "👉 Start Fish by typing: fish"
echo "👉 Choose a theme with: chooseposh"
echo ""
echo "💡 Set your terminal font to a Nerd Font for icons"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
