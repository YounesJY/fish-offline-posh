# Testing

The repo has three test layers. Use the first one while editing, the second to
check the interactive picker, and the third before a release.

## Fast sandbox

```bash
./tests/local-test.sh
```

This creates a temporary `HOME`, writes a fake `config.fish` with an active
`oh-my-posh init` line, and runs the installer with `--no-deps --no-font`.
It then checks:

- the theme count matches `themes/`
- a default theme was saved
- the existing init line was disabled
- `--set` persists the new theme
- the startup snippet puts oh-my-posh on `PATH`
- `--uninstall` removes managed files and restores the init line

It needs `fish` and an existing `oh-my-posh` on `PATH`. It never downloads
anything and never reads or writes your real fish config. The temporary
directory is deleted on exit.

## Interactive sandbox

The picker needs a TTY, so run this in a real terminal:

```bash
cd ~/Projects/fish-offline-posh
export TESTHOME=/tmp/fish-omp-test
rm -rf "$TESTHOME" && mkdir -p "$TESTHOME/.config/fish"

printf 'set -g fish_greeting\noh-my-posh init fish | source\n' \
  > "$TESTHOME/.config/fish/config.fish"

env HOME="$TESTHOME" \
    XDG_CONFIG_HOME="$TESTHOME/.config" \
    XDG_DATA_HOME="$TESTHOME/.local/share" \
    ./install.sh --no-deps --no-font

env HOME="$TESTHOME" \
    XDG_CONFIG_HOME="$TESTHOME/.config" \
    XDG_DATA_HOME="$TESTHOME/.local/share" \
    fish
```

Inside that fish session:

```fish
chooseOhMyPosh                  # fzf picker, arrows preview each prompt
chooseOhMyPosh --current
exec fish                       # the choice should survive
chooseOhMyPosh --set agnoster   # non-interactive switch
chooseOhMyPosh --list | count
```

Remove the sandbox when done:

```bash
rm -rf /tmp/fish-omp-test
```

`--no-deps` keeps the host untouched and reuses your existing oh-my-posh.
Package installation belongs to the container matrix; running without
`--no-deps` on your machine can install system packages and is not needed to
test the picker.

## Container matrix

```bash
./tests/run.sh                         # all six images
./tests/run.sh ubuntu:24.04 debian:12  # selected images
RUNTIME=podman ./tests/run.sh          # force podman
```

Default images:

- `ubuntu:24.04`
- `debian:12`
- `fedora:latest`
- `archlinux:latest`
- `alpine:latest`
- `opensuse/tumbleweed`

For each image, `tests/container-test.sh` installs with `--no-font --theme
catppuccin_mocha`, checks the saved theme and the 125-theme list, renders the
prompt, switches to `agnoster`, verifies persistence in a new fish process, and
uninstalls the managed files.

The containers are throwaway. The repo is mounted read-only at `/repo`, so a
test run does not modify your working tree.

### Adding an image

Pass it on the command line first:

```bash
./tests/run.sh myimage:tag
```

Add it to `DISTROS` in `tests/run.sh` only if it should be covered by default.
The image needs `/bin/sh` and a package manager that `install.sh` supports
(`apt-get`, `dnf`, `pacman`, `zypper`, or `apk`).

## Testing the binary download

The normal sandbox reuses your installed oh-my-posh. To exercise the download
path, hide it from `PATH` and point the install at a temporary bin directory:

```bash
cd ~/Projects/fish-offline-posh
TESTHOME=/tmp/fish-omp-download
rm -rf "$TESTHOME"

env HOME="$TESTHOME" \
    XDG_CONFIG_HOME="$TESTHOME/.config" \
    XDG_DATA_HOME="$TESTHOME/.local/share" \
    XDG_BIN_HOME="$TESTHOME/.local/bin" \
    PATH=/usr/local/bin:/usr/bin:/bin \
    OMP_VERSION=v33.4.0 \
    ./install.sh --no-deps --no-font

"$TESTHOME/.local/bin/oh-my-posh" --version
```

This needs network access and a `curl` that trusts HTTPS. Pin `OMP_VERSION` for
repeatable results; `latest` resolves at download time. Remove the sandbox when
done.

## Diagnosing failures

Start with the test output. Each failing check prints what it expected and what
it got. To inspect a container by hand:

```bash
docker run --rm -it -v "$PWD:/repo:ro" alpine:latest /bin/sh
```

Then install bash if needed, run `./install.sh`, and inspect the state files:

```bash
fish -i -c 'chooseOhMyPosh --current'
fish -i -c 'echo $POSH_CONFIG'
ls ~/.config/fish/conf.d ~/.config/fish/functions
cat ~/.config/oh-my-posh/{theme,themes-dir,bin-dir}
```

Common causes:

| Symptom | Likely cause |
| --- | --- |
| `curl: (77) error setting certificate file` | No CA bundle; `ca-certificates` should be installed |
| `find: command not found` | Installer gained a findutils dependency |
| `bash: not found` | POSIX preamble was removed or skipped |
| Uninstall skips a fish file | Managed header changed, or `head \| grep -q` returned early under `pipefail` |
| New shell cannot find `oh-my-posh` | `bin-dir` was not recorded or the conf.d does not add it |
| Theme does not stick | Another `oh-my-posh init` line runs after `conf.d` |

`AGENTS.md` describes these pitfalls in more detail.

## Manual checklist

Before tagging a release, run the local test and the full matrix, then confirm
by hand in the interactive sandbox:

- `chooseOhMyPosh` opens the picker
- the preview renders a prompt for each theme
- selecting a theme repaints the current prompt
- `exec fish` starts with the selected theme
- `--reset` returns to Oh My Posh's built-in prompt
- a theme in `~/.config/oh-my-posh/themes` wins over a bundled theme with the
  same file name
- `--uninstall` restores the original `config.fish`
