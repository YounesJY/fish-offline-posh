# Managed by fish-offline-posh (install.sh). Local edits are overwritten on
# reinstall; change the copy in the repo and run install.sh again.

function chooseOhMyPosh --description "List local Oh My Posh themes, apply one now, and remember it"

    # ------------------------------------------------------------------
    # Paths (the conf.d snippet sets the same globals at shell startup)
    # ------------------------------------------------------------------
    set -q XDG_CONFIG_HOME; or set -l XDG_CONFIG_HOME $HOME/.config
    set -q XDG_DATA_HOME; or set -l XDG_DATA_HOME $HOME/.local/share

    set -l config_dir $XDG_CONFIG_HOME/oh-my-posh
    set -l theme_file $config_dir/theme
    set -l user_theme_dir $config_dir/themes

    set -l vendored_theme_dir
    if test -f $config_dir/themes-dir
        # No `-l`: inside this `if` block that would create a block-local
        # variable which is erased at `end`.
        read vendored_theme_dir < $config_dir/themes-dir
    end
    if test -z "$vendored_theme_dir"
        set vendored_theme_dir $XDG_DATA_HOME/fish-offline-posh/themes
    end

    # User themes first so they win over a vendored theme with the same name.
    set -l theme_dirs $user_theme_dir $vendored_theme_dir

    # ------------------------------------------------------------------
    # Arguments
    # ------------------------------------------------------------------
    set -l mode pick
    set -l requested

    set -l args $argv
    while set -q args[1]
        switch $args[1]
            case -h --help
                __chooseOhMyPosh_usage
                return 0
            case -l --list
                set mode list
            case -c --current
                set mode current
            case -r --reset
                set mode reset
            case -s --set
                set -e args[1]
                if not set -q args[1]
                    echo "chooseOhMyPosh: --set needs a theme name" >&2
                    return 2
                end
                set requested $args[1]
                set mode set
            case '--set=*'
                set requested (string replace -- '--set=' '' $args[1])
                set mode set
            case --
                set -e args[1]
                break
            case '-*'
                echo "chooseOhMyPosh: unknown option $args[1]" >&2
                __chooseOhMyPosh_usage >&2
                return 2
            case '*'
                set requested $args[1]
                set mode set
        end
        set -e args[1]
    end

    # Anything after `--` is treated as a theme name.
    if set -q args[1]; and test -z "$requested"
        set requested $args[1]
        set mode set
    end

    # ------------------------------------------------------------------
    # Modes
    # ------------------------------------------------------------------
    switch $mode
        case list
            set -l themes (__chooseOhMyPosh_themes $theme_dirs)
            if test (count $themes) -eq 0
                echo "chooseOhMyPosh: no themes found in:" >&2
                for dir in $theme_dirs
                    echo "  $dir" >&2
                end
                echo "Re-run install.sh to restore the bundled themes." >&2
                return 1
            end
            for theme in $themes
                __chooseOhMyPosh_basename $theme
            end
            return 0

        case current
            set -l current
            if test -f $theme_file
                read current < $theme_file
            end
            if test -n "$current"
                echo $current
            else
                echo "(none - using Oh My Posh's default prompt)"
            end
            return 0

        case reset
            rm -f $theme_file
            if not command -sq oh-my-posh
                echo "chooseOhMyPosh: oh-my-posh is not on PATH; re-run install.sh." >&2
                return 1
            end
            oh-my-posh init fish | source
            commandline -f repaint 2>/dev/null
            echo "Reset to Oh My Posh's default prompt."
            return 0

        case set
            set -l theme_path (__chooseOhMyPosh_find $requested $theme_dirs)
            set -l found $status
            if test $found -eq 2
                echo "chooseOhMyPosh: '$requested' matches more than one theme; be more specific." >&2
                return 1
            end
            if test $found -ne 0; or test -z "$theme_path"
                echo "chooseOhMyPosh: no theme named '$requested'." >&2
                echo "Run 'chooseOhMyPosh --list' to see the local themes." >&2
                return 1
            end
            __chooseOhMyPosh_commit $theme_path $config_dir $theme_file
            return $status
    end

    # ------------------------------------------------------------------
    # Interactive picker
    # ------------------------------------------------------------------
    if not status is-interactive
        echo "chooseOhMyPosh: the picker needs an interactive shell." >&2
        echo "Use --list, --current, or --set NAME instead." >&2
        return 2
    end

    set -l themes (__chooseOhMyPosh_themes $theme_dirs)
    if test (count $themes) -eq 0
        echo "chooseOhMyPosh: no themes found in:" >&2
        for dir in $theme_dirs
            echo "  $dir" >&2
        end
        echo "Re-run install.sh to restore the bundled themes." >&2
        return 1
    end

    set -l theme_path

    if command -sq fzf
        # Show only the file name (last path component), preview the prompt.
        set -l selection (printf '%s\n' $themes | fzf \
            --delimiter=/ --with-nth=-1 \
            --prompt='Oh My Posh theme > ' \
            --height=60% --border --reverse \
            --preview='oh-my-posh print primary --plain --config {} --shell fish 2>/dev/null' \
            --preview-window='down:3:wrap')

        if test -z "$selection"
            echo "No theme selected."
            return 0
        end
        set theme_path $selection
    else
        echo "Local Oh My Posh themes:"
        for i in (seq (count $themes))
            printf '  %3d) %s\n' $i (__chooseOhMyPosh_basename $themes[$i])
        end

        set -l answer
        read -l -P 'Theme number or name (empty to cancel): ' answer
        if test -z "$answer"
            echo "No theme selected."
            return 0
        end

        if string match -qr '^\d+$' -- $answer
            if test $answer -ge 1 -a $answer -le (count $themes)
                set theme_path $themes[$answer]
            else
                echo "chooseOhMyPosh: invalid theme number." >&2
                return 1
            end
        else
            set theme_path (__chooseOhMyPosh_find $answer $theme_dirs)
            if test $status -ne 0; or test -z "$theme_path"
                echo "chooseOhMyPosh: no unique theme matches '$answer'." >&2
                return 1
            end
        end
    end

    __chooseOhMyPosh_commit $theme_path $config_dir $theme_file
end


function __chooseOhMyPosh_usage
    echo "Usage: chooseOhMyPosh [options]"
    echo
    echo "List local Oh My Posh themes, apply one immediately, and remember it."
    echo "With no options, opens an fzf picker with a live prompt preview."
    echo
    echo "Options:"
    echo "  -l, --list           Print local theme names, one per line"
    echo "  -c, --current        Print the saved theme"
    echo "  -s, --set NAME       Apply and save NAME (no picker)"
    echo "  -r, --reset          Forget the saved theme; use Oh My Posh's default"
    echo "  -h, --help           Show this help"
    echo
    echo "Theme directories (first match wins):"
    echo "  \$XDG_CONFIG_HOME/oh-my-posh/themes"
    echo "  \$XDG_DATA_HOME/fish-offline-posh/themes"
end


function __chooseOhMyPosh_basename --description "Last path component without needing the path builtin"
    string replace -r '^.*/' '' -- $argv[1]
end


function __chooseOhMyPosh_themes --description "Print local theme paths, de-duplicated by name"
    set -l dirs $argv
    set -l seen
    set -l paths

    for dir in $dirs
        test -d $dir; or continue
        for file in $dir/*.omp.json $dir/*.omp.toml $dir/*.omp.yaml $dir/*.omp.yml
            test -f $file; or continue
            set -l base (__chooseOhMyPosh_basename $file)
            contains -- $base $seen; and continue
            set -a seen $base
            set -a paths $file
        end
    end

    test (count $paths) -eq 0; and return 0
    printf '%s\n' $paths | sort
end


function __chooseOhMyPosh_find --description "Resolve a theme name to a path (0 found, 1 missing, 2 ambiguous)"
    set -l name $argv[1]
    set -l dirs $argv[2..-1]

    # Never let a name escape the theme directories.
    if test -z "$name"
        return 1
    end
    if string match -q -- '*/*' $name; or string match -q -- '-*' $name
        return 1
    end

    # Exact match, respecting directory priority (user themes first).
    for dir in $dirs
        for file in $dir/$name $dir/$name.omp.json $dir/$name.omp.toml $dir/$name.omp.yaml $dir/$name.omp.yml
            if test -f $file
                echo $file
                return 0
            end
        end
    end

    # Fall back to a unique substring match, e.g. "mocha".
    set -l candidates
    set -l seen
    for dir in $dirs
        test -d $dir; or continue
        for file in $dir/*.omp.json $dir/*.omp.toml $dir/*.omp.yaml $dir/*.omp.yml
            test -f $file; or continue
            set -l base (__chooseOhMyPosh_basename $file)
            contains -- $base $seen; and continue
            set -a seen $base
            if string match -qi -- "*$name*" $base
                set -a candidates $file
            end
        end
    end

    if test (count $candidates) -eq 1
        echo $candidates[1]
        return 0
    else if test (count $candidates) -gt 1
        return 2
    end

    return 1
end


function __chooseOhMyPosh_apply --description "Source an Oh My Posh theme into the current shell"
    set -l theme_path $argv[1]

    if not command -sq oh-my-posh
        echo "chooseOhMyPosh: oh-my-posh is not on PATH; re-run install.sh." >&2
        return 1
    end

    oh-my-posh init fish --config $theme_path | source
    set -l pipe_status $pipestatus
    commandline -f repaint 2>/dev/null
    return $pipe_status[1]
end


function __chooseOhMyPosh_save --description "Persist the theme name atomically"
    set -l config_dir $argv[1]
    set -l theme_file $argv[2]
    set -l name $argv[3]

    mkdir -p $config_dir; or return 1
    set -l tmp $theme_file.tmp.$fish_pid
    printf '%s\n' $name > $tmp; or return 1
    mv -f $tmp $theme_file
end


function __chooseOhMyPosh_commit --description "Apply, persist, and report a theme"
    set -l theme_path $argv[1]
    set -l config_dir $argv[2]
    set -l theme_file $argv[3]

    __chooseOhMyPosh_apply $theme_path
    or begin
        echo "chooseOhMyPosh: failed to apply $theme_path" >&2
        return 1
    end

    __chooseOhMyPosh_save $config_dir $theme_file (__chooseOhMyPosh_basename $theme_path)
    or begin
        echo "chooseOhMyPosh: applied the theme, but could not save the choice to $theme_file" >&2
        return 1
    end

    set -g __omp_current_theme (__chooseOhMyPosh_basename $theme_path)
    echo "✨ $__omp_current_theme applied. New shells will start with it."
end
