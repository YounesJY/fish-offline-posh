# AGENTS.md

Notes for agents and humans who change this repo. Read this before editing
`install.sh` or the fish files.

## What this project does

Installs Fish, Oh My Posh, and a local copy of the official themes without
taking over the user's config. Four constraints shape the code:

- Theme selection works offline.
- Running the installer twice produces the same result.
- An existing `config.fish` is preserved. The one exception is an active
  `oh-my-posh init` line that would override the chosen theme.
- The install is user-local unless the user runs it as root.

## Layout

| Path | What it is |
| --- | --- |
| `install.sh` | Installer, uninstaller, dependency handling, theme copy, config migration |
| `fish/conf.d/99-oh-my-posh.fish` | Runs before `config.fish`; sets paths and applies the saved theme |
| `fish/functions/chooseOhMyPosh.fish` | Picker, `--list`, `--current`, `--set`, `--reset`, persistence |
| `themes/` | 125 vendored `.omp.*` files plus `ATTRIBUTION.md` |
| `tests/local-test.sh` | Fast sandbox test; needs fish and an existing oh-my-posh |
| `tests/container-test.sh` | Assertions that run inside a fresh container |
| `tests/run.sh` | Docker/podman matrix for six distros |
| `tests/try.sh` | Starts an interactive container with the repo at `/repo` |
| `README.md` | User-facing install, usage, uninstall |
| `docs/TESTING.md` | Test recipes and failure diagnosis |

## How the pieces fit

`install.sh` copies the themes into `$XDG_DATA_HOME/fish-offline-posh/themes`
and records three pieces of state in `$XDG_CONFIG_HOME/oh-my-posh`:

- `theme`: the saved theme file name
- `themes-dir`: absolute path to the installed theme copy
- `bin-dir`: directory containing the Oh My Posh binary

The conf.d snippet reads those files at shell startup, adds `bin-dir` to
`PATH`, and applies `theme` by absolute path. The function repeats the same
lookup, so it also works when sourced directly, which is what
`install.sh --theme` does.

`install.sh` is bash, but begins with a POSIX preamble that installs bash with
`apk` and re-execs itself. That preamble is why `./install.sh` works on Alpine
before bash exists.

## Invariants

These prevent failures that are easy to miss in review.

1. **Load themes by absolute path.** `oh-my-posh init --config agnoster` treats
   the name as a remote theme and hits the network. Always pass a path.
2. **Copy files; do not symlink them.** The install must keep working if the
   repo is deleted.
3. **Keep the managed-file header.** Both fish files begin with
   `# Managed by fish-offline-posh`. Uninstall only removes files with that
   header. If you change the header, update `remove_managed_file` too.
4. **Keep the picker offline.** It may list and preview local files only. No
   remote fetch and no cache downloads.
5. **Support fish 3.3+.** No `path` builtin and no fish 4-only syntax. Guard
   interactive-only calls with `status is-interactive`.
6. **Do not add runtime dependencies casually.** The installer assumes bash,
   POSIX tools, curl, and fish. It does not assume `find`, because minimal
   images such as openSUSE Tumbleweed omit findutils. If you need a new tool,
   add it to `install_dependencies` and the README.
7. **Do not overwrite user files.** Installer-managed files are backed up
   before replacement. `config.fish` is modified only to comment out an active
   `oh-my-posh init` line, and uninstall reverses that.
8. **Keep the theme count honest.** `tests/container-test.sh` asserts 125
   themes; `tests/local-test.sh` compares the listed count with the number of
   bundled files. Update `themes/ATTRIBUTION.md` when refreshing the snapshot.

## Pitfalls already paid for

- **`set -o pipefail` plus `grep -q` in a pipeline.** `head -n 5 file | grep -q
  ...` lets `grep` exit early, SIGPIPE `head`, and turn a successful match into
  a failed pipeline. Run `grep -q` directly on the file.
- **`read` inside fish blocks.** Without `-l`, `read` can create a block-local
  variable that disappears at `end`. Either predeclare the variable in the
  function scope or omit `-l` deliberately, as the existing comments explain.
- **`fish_add_path -U` in a subprocess.** It did not reach later shells in the
  Alpine container. The installer records `bin-dir` and the conf.d adds it on
  every startup instead.
- **Missing CA bundle.** Minimal Debian and Ubuntu images have curl but no
  `/etc/ssl/certs/ca-certificates.crt`; downloads fail with `curl: (77)`.
  `install_dependencies` installs `ca-certificates` when no common bundle
  exists.
- **Missing bash.** Alpine does not ship it. Keep the POSIX preamble.
- **`fish -i` without `TERM`.** Containers print terminal warnings. They are
  noise, not failures.
- **Bare theme names.** See invariant 1. Both `--set` and the conf.d must
  resolve a path first.

## Commands

Run these before committing:

```bash
bash -n install.sh
fish -n fish/conf.d/99-oh-my-posh.fish
fish -n fish/functions/chooseOhMyPosh.fish

./tests/local-test.sh          # fast, isolated HOME, no network
./tests/run.sh                 # six-distro matrix, needs Docker or podman
./tests/run.sh alpine:latest   # one image while iterating
./tests/try.sh alpine:latest   # interactive container, repo mounted at /repo
```

`tests/local-test.sh` needs `fish` and an existing `oh-my-posh` on `PATH`.
`tests/run.sh` downloads Oh My Posh inside each container, so it needs network.

## Style

- Four spaces, no tabs.
- `install.sh` uses `info`, `ok`, `warn`, and `die` for output. Keep messages
  short and literal.
- Fish helper functions are prefixed with `__chooseOhMyPosh_`.
- Quote variables unless word splitting is intended.
- Update the README when behavior or options change. Add a test when fixing a
  bug whose behavior a test can observe.

## Refreshing themes

```bash
git clone --depth 1 https://github.com/JanDeDobbeleer/oh-my-posh.git /tmp/omp
cp /tmp/omp/themes/*.omp.* themes/
```

Update the snapshot line in `themes/ATTRIBUTION.md`, then run both test
scripts. A partial copy shows up as a count mismatch.
