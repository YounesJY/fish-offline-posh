# --- Fish + Oh My Posh full setup for Linux (Zorin/Mint/Ubuntu) ---
sudo apt update && sudo apt install -y git curl fzf fish

# --- Install Oh My Posh binary ---
mkdir -p $HOME/bin
curl -Lo $HOME/bin/oh-my-posh https://github.com/JanDeDobbeleer/oh-my-posh/releases/latest/download/posh-linux-amd64
chmod +x $HOME/bin/oh-my-posh

# --- Add binary path to Fish ---
fish -c 'set -U fish_user_paths $HOME/bin $fish_user_paths'

# --- Download all Oh My Posh themes ---
mkdir -p ~/.poshthemes
cd ~/.poshthemes
git clone https://github.com/JanDeDobbeleer/oh-my-posh.git
cp -r oh-my-posh/themes/* .
rm -rf oh-my-posh
cd ~

# --- Create chooseposh function ---
fish -c '
function chooseposh
    set theme_dir ~/.poshthemes
    set config_file ~/.config/fish/current_posh_theme

    set theme (ls $theme_dir/*.omp.* 2>/dev/null | xargs -n 1 basename | fzf --prompt="Select a theme: ")

    if test -z "$theme"
        echo "No theme selected."
        return
    end

    echo $theme > $config_file
    echo "Applying theme: $theme"
    oh-my-posh init fish --config "$theme_dir/$theme" | source
end
funcsave chooseposh
'

# --- Configure persistent theme loading ---
mkdir -p ~/.config/fish
cat << 'EOF' > ~/.config/fish/config.fish
# --- Oh My Posh persistent theme setup ---
set theme_dir $HOME/.poshthemes
set config_file $HOME/.config/fish/current_posh_theme

if test -f $config_file
    set last_theme (cat $config_file)
    if test -f "$theme_dir/$last_theme"
        oh-my-posh init fish --config "$theme_dir/$last_theme" | source
    else
        oh-my-posh init fish --config "$theme_dir/montys.omp.json" | source
    end
else
    oh-my-posh init fish --config "$theme_dir/montys.omp.json" | source
end

if status is-interactive
    # Interactive commands can go here
end
EOF

echo
echo


mkdir -p ~/.local/share/fonts
cd ~/.local/share/fonts
wget https://github.com/ryanoasis/nerd-fonts/releases/latest/download/Meslo.zip
unzip Meslo.zip
rm Meslo.zip
fc-cache -fv

echo
echo

echo "✅ All done!"
echo "👉 Start Fish by running: fish"
echo "👉 Then choose a theme with: chooseposh"
echo
