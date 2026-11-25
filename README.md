# fish-offline-posh

Fish shell + [Oh My Posh](https://ohmyposh.dev) setup that is **offline-first**,
**repeatable across Linux distros**, and **non-destructive** to your existing
fish config.

- Bundles all **125 official Oh My Posh themes** in the repo.
- `chooseOhMyPosh`: fuzzy picker with a live prompt preview, plus a numbered
  menu when `fzf` is not installed.
- Applies the theme **immediately** in the current shell and **remembers** it
  for every new shell.
- Never overwrites `~/.config/fish/config.fish`; it only comments out a simple
  existing `oh-my-posh init` line (with a timestamped backup) because that line
  would otherwise override the chosen theme.
- Works with **apt, dnf, pacman, zypper, and apk**. User-local by default; no
  sudo is needed for Oh My Posh, themes, or the fish config.

## Quick start

```bash
git clone https://github.com/YounesJY/fish-offline-posh.git
cd fish-offline-posh
./install.sh
fish
chooseOhMyPosh
```

To test in a throwaway container first:

```bash
./tests/run.sh ubuntu:24.04
```

## What `install.sh` does

| Item | Location |
| --- | --- |
| Oh My Posh binary (if missing) | `~/.local/bin/oh-my-posh` |
| Bundled themes | `~/.local/share/fish-offline-posh/themes` |
| Saved theme name | `~/.config/oh-my-posh/theme` |
| Custom themes (yours) | `~/.config/oh-my-posh/themes` |
| Startup snippet | `~/.config/fish/conf.d/99-oh-my-posh.fish` |
| `chooseOhMyPosh` function | `~/.config/fish/functions/chooseOhMyPosh.fish` |

The installer is idempotent. Re-running it updates the managed files, restores
missing themes, and leaves your saved theme and custom themes alone.

### Options

```text
--theme NAME      Apply and save a theme during install
--no-default      Do not pick a default theme if none is saved
--no-deps         Do not install missing system packages
--no-font         Do not install a Nerd Font
--keep-config     Do not comment out an existing oh-my-posh init line
--uninstall       Remove the files this installer manages
-h, --help        Show help
```

Pin the Oh My Posh version for a reproducible install:

```bash
OMP_VERSION=v33.4.0 ./install.sh
```

`OMP_VERSION` accepts `latest` (the default), `v33.4.0`, or `33.4.0`.

## Using `chooseOhMyPosh`

```bash
chooseOhMyPosh                 # fzf picker with prompt preview
chooseOhMyPosh --list          # print all local theme names
chooseOhMyPosh --current       # print the saved theme
chooseOhMyPosh --set agnoster  # apply and save without the picker
chooseOhMyPosh --reset         # forget the saved theme, use OMP's default
```

The picker searches only local files, so it works with no network. The preview
runs `oh-my-posh print primary --config <absolute path>`.

## Custom themes

Put any `.omp.json`, `.omp.toml`, `.omp.yaml`, or `.omp.yml` file in:

```text
~/.config/oh-my-posh/themes
```

Custom themes are listed **before** the bundled themes. If a custom theme has
the same file name as a bundled one, the custom one wins.

## Fonts

Oh My Posh icons need a [Nerd Font](https://www.nerdfonts.com/). The installer
tries `oh-my-posh font install Meslo` and then runs `fc-cache`. It skips this in
containers, because the font belongs on the host and must be selected in your
terminal emulator.

Set your terminal font to **MesloLGM Nerd Font** (or another Nerd Font). If the
installer could not install one:

```bash
oh-my-posh font install meslo
fc-cache -f
```

If icons show as boxes, the terminal font is the problem, not fish.

## How it works

- Themes are **vendored in the repo** and copied to an XDG data directory, not
  to the Oh My Posh cache. `oh-my-posh cache clear` therefore cannot delete
  them.
- Every theme is loaded by **absolute path**. A bare name such as
  `--config agnoster` makes Oh My Posh fetch the theme from the network.
- `99-oh-my-posh.fish` lives in `conf.d`, which fish loads before
  `config.fish`. The installer comments out a simple
  `oh-my-posh init fish | source` line in `config.fish` so it cannot override
  the saved theme. The original file is backed up first.
- The saved theme is a plain text file, so it survives restarts and is easy to
  inspect.
- `chooseOhMyPosh` re-sources the Oh My Posh init script in the current shell
  and repaints the prompt, so no restart is required.

## Requirements

- Linux with fish **3.3+** (3.6+ or 4.x recommended).
- `curl` to download the Oh My Posh binary if it is not already installed.
- `fzf` is optional; without it you get a numbered menu.
- Network is needed only for the Oh My Posh binary and the optional font.
  The themes are already in the repo.

The installer adds `curl`, `fish`, `fzf`, `fontconfig`, and (on minimal
Debian/Ubuntu images) `ca-certificates` through your package manager. The CA
bundle matters because a bare `curl` without it fails with
`error setting certificate file`. Use `--no-deps` only when those tools are
already present.

Only standard POSIX tools plus bash are assumed. `findutils` is not required,
so minimal images such as `opensuse/tumbleweed` work as-is.

## Testing

Two scripts cover the project. Both leave your real config alone.

```bash
./tests/local-test.sh   # throwaway HOME, needs fish + oh-my-posh, no network
./tests/run.sh          # fresh containers, needs Docker or podman
```

`local-test.sh` installs into a temporary directory, checks theme listing,
persistence, the startup path, and uninstall, then deletes everything.

The container matrix runs the real installer in fresh images:

```bash
./tests/run.sh                         # all distros
./tests/run.sh ubuntu:24.04 debian:12  # selected images
RUNTIME=podman ./tests/run.sh          # force podman
```

Covered images:

- `ubuntu:24.04`
- `debian:12`
- `fedora:latest`
- `archlinux:latest`
- `alpine:latest`
- `opensuse/tumbleweed`

Each test installs fish, Oh My Posh, and the themes, switches themes, checks
persistence, and uninstalls the managed files. The Alpine and openSUSE images
do not ship bash, so the installer's POSIX preamble installs it with `apk`
before re-executing itself. All six images pass.

See [docs/TESTING.md](docs/TESTING.md) for the interactive sandbox, the binary
download test, and failure diagnosis.

## Development

[AGENTS.md](AGENTS.md) documents the repo layout, invariants, commands, and the
container bugs that shaped the current code. Read it before changing
`install.sh` or the fish files.

## Migration from `setup-fish-omp.sh`

The old installer wrote `~/.config/fish/current_posh_theme` and kept themes in
`~/.poshthemes`. This installer reads that file on first run. If the saved theme
is missing from the bundled set, it copies the file from `~/.poshthemes` into
your custom theme directory.

The old `chooseposh` function is not removed automatically. Delete
`~/.config/fish/functions/chooseposh.fish` if you no longer need it.

## Uninstall

```bash
./install.sh --uninstall
```

This removes the managed fish files and the installed theme copy, restores any
`oh-my-posh init` lines that the installer commented out, and leaves the Oh My
Posh binary, fonts, your saved theme, and your custom themes in place.

## Troubleshooting

**The prompt does not change after choosing a theme.**
`config.fish` runs after `conf.d`. Check for another `oh-my-posh init` line in
`~/.config/fish/config.fish` or another `conf.d` file, and remove it or re-run
the installer without `--keep-config`.

**`chooseOhMyPosh: no themes found`.**
Re-run `./install.sh`; the bundled themes are copied from the repo.

**A theme looks broken or a segment is missing.**
Some themes expect tools you may not have installed (git, node, python, etc.).
That is normal. Pick another theme or install the tool.

**Icons are boxes.**
Install a Nerd Font and select it in the terminal emulator. See
[Fonts](#fonts).

**I want to temporarily disable the prompt.**
Start fish with `set -g __omp_disabled 1` before the conf.d file loads, or
remove the managed snippet with `./install.sh --uninstall`.

## Credits

Themes and Oh My Posh itself are MIT-licensed by
[Jan De Dobbeleer and contributors](https://github.com/JanDeDobbeleer/oh-my-posh).
The vendored theme snapshot is documented in
[`themes/ATTRIBUTION.md`](themes/ATTRIBUTION.md).
