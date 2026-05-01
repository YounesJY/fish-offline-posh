# Fish + Oh My Posh one‑click installer

Tested on Ubuntu 20.04 / 22.04 / 24.04, Debian 11 / 12, Zorin OS 17 / 18.

## Quick install (curl)

```bash
curl -fsSL https://raw.githubusercontent.com/YounesJY/fish-offline-posh/main/setup-fish-omp.sh | bash
```

## Or download and run manually

```bash
wget https://raw.githubusercontent.com/YounesJY/fish-offline-posh/main/setup-fish-omp.sh
chmod +x setup-fish-omp.sh
./setup-fish-omp.sh
```

## Install via Git clone

```bash
git clone https://github.com/YounesJY/fish-offline-posh.git
cd fish-offline-posh
./setup-fish-omp.sh
```

## After installation

```bash
fish          # start Fish
chooseposh    # pick your theme (interactive fuzzy finder)
```

## Make Fish your default shell (optional)

Set Fish as your default shell so it starts automatically when you open a terminal or log in.

**1. Find where Fish is installed** (usually `/usr/bin/fish`):

```bash
which fish
```

**2. Change your default shell:**

```bash
chsh -s /usr/bin/fish
```

If you don’t have permission, use `sudo`:

```bash
sudo chsh -s /usr/bin/fish $USER
```

**3. Log out and back in** (or restart your terminal) for the change to take effect.

> 💡 If your terminal still opens Bash after logout, you can add `exec fish` at the end of your `~/.bashrc` as a fallback.

## Notes

- This script was **AI‑generated** and **human‑reviewed**.
- Tested on **Ubuntu** and **Debian** (see list above).
- If you want to test **before using it on your main system**, you can try it in a **Docker** container:

  ```bash
  docker run -it ubuntu:22.04 bash
  apt update && apt install -y curl
  curl -fsSL https://raw.githubusercontent.com/YounesJY/fish-offline-posh/main/setup-fish-omp.sh | bash
  ```

  Then inside the container run `fish` and `chooseposh` to verify everything works.
