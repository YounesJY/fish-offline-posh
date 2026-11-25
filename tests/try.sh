#!/usr/bin/env bash
# Start an interactive throwaway container with this repo at /repo.
set -euo pipefail

REPO_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)

if [ $# -lt 1 ]; then
    cat >&2 <<'EOF'
Usage: tests/try.sh IMAGE

Examples:
  ./tests/try.sh ubuntu:24.04
  ./tests/try.sh alpine:latest
  RUNTIME=podman ./tests/try.sh fedora:latest
EOF
    exit 2
fi

IMAGE=$1

if [ -z "${RUNTIME:-}" ]; then
    if command -v docker >/dev/null 2>&1; then
        RUNTIME=docker
    elif command -v podman >/dev/null 2>&1; then
        RUNTIME=podman
    else
        echo "docker or podman is required" >&2
        exit 1
    fi
fi

echo "Starting $IMAGE. The repo is mounted read-only at /repo."
echo "Inside, try:  ./install.sh && fish"
echo

exec "$RUNTIME" run --rm -it \
    -v "$REPO_DIR:/repo:ro" \
    -w /repo \
    "$IMAGE" /bin/sh -c '
        if command -v bash >/dev/null 2>&1; then
            exec bash
        fi
        echo "bash is not installed. Running ./install.sh will add it on Alpine." >&2
        exec /bin/sh
    '
