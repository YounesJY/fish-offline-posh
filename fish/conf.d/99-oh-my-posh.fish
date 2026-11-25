# Managed by fish-offline-posh (install.sh). Local edits are overwritten on
# reinstall; change the copy in the repo and run install.sh again.
#
# This file runs before config.fish. If config.fish also initialises Oh My
# Posh, that later init wins and the saved theme will not stick. install.sh
# comments out simple `oh-my-posh init` lines for this reason.

set -q XDG_CONFIG_HOME; or set -l XDG_CONFIG_HOME $HOME/.config
set -q XDG_DATA_HOME; or set -l XDG_DATA_HOME $HOME/.local/share

set -g __omp_config_dir $XDG_CONFIG_HOME/oh-my-posh
set -g __omp_theme_file $__omp_config_dir/theme
set -g __omp_user_theme_dir $__omp_config_dir/themes

# install.sh records the exact theme directory it used. The fallback keeps
# things working if that file is missing.
set -g __omp_vendored_theme_dir
if test -f $__omp_config_dir/themes-dir
    # No `-l`: inside this `if` block that would create a block-local
    # variable which is erased at `end`.
    read __omp_vendored_theme_dir < $__omp_config_dir/themes-dir
end
if test -z "$__omp_vendored_theme_dir"
    set __omp_vendored_theme_dir $XDG_DATA_HOME/fish-offline-posh/themes
end

set -g __omp_theme_dirs $__omp_user_theme_dir $__omp_vendored_theme_dir

# install.sh records where it put the Oh My Posh binary. Add that directory
# on every startup instead of relying on a persisted universal variable.
set -g __omp_bin_dir
if test -f $__omp_config_dir/bin-dir
    read __omp_bin_dir < $__omp_config_dir/bin-dir
end
if test -n "$__omp_bin_dir"; and test -d $__omp_bin_dir
    fish_add_path -g $__omp_bin_dir
end

# Escape hatch: `set -g __omp_disabled 1` before this file loads.
if set -q __omp_disabled; and test "$__omp_disabled" = 1
    return
end

# Prompts only matter in interactive shells; never break non-interactive ones.
status is-interactive; or return
command -sq oh-my-posh; or return

set -l theme_name
if test -f $__omp_theme_file
    read theme_name < $__omp_theme_file
end

set -l applied 0
if test -n "$theme_name"
    for dir in $__omp_theme_dirs
        if test -f $dir/$theme_name
            # Always pass an absolute path. A bare theme name makes Oh My Posh
            # fetch the theme from the network.
            oh-my-posh init fish --config $dir/$theme_name | source
            set applied 1
            break
        end
    end
end

# No saved theme (or it was deleted): keep Oh My Posh's built-in prompt.
if test $applied -eq 0
    oh-my-posh init fish | source
end
