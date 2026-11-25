#!/usr/bin/env bash
# Run the real installer in fresh containers.
set -euo pipefail

REPO_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
RUNTIME=${RUNTIME:-}

if [ -z "$RUNTIME" ]; then
    if command -v docker >/dev/null 2>&1; then
        RUNTIME=docker
    elif command -v podman >/dev/null 2>&1; then
        RUNTIME=podman
    else
        echo "docker or podman is required" >&2
        exit 1
    fi
fi

if [ $# -gt 0 ]; then
    DISTROS=("$@")
else
    DISTROS=(
        ubuntu:24.04
        debian:12
        fedora:latest
        archlinux:latest
        alpine:latest
        opensuse/tumbleweed
    )
fi

failed=()

run_one() {
    local image=$1
    echo
    echo "================================================================"
    echo "  $image"
    echo "================================================================"
    if "$RUNTIME" run --rm \
        -v "$REPO_DIR:/repo:ro" \
        -v "$REPO_DIR/tests/container-test.sh:/tmp/container-test.sh:ro" \
        "$image" /bin/sh /tmp/container-test.sh; then
        echo "PASS: $image"
    else
        echo "FAIL: $image" >&2
        failed+=("$image")
    fi
}

for image in "${DISTROS[@]}"; do
    run_one "$image"
done

echo
if [ ${#failed[@]} -gt 0 ]; then
    echo "Failed images:" >&2
    printf '  %s\n' "${failed[@]}" >&2
    exit 1
fi

echo "All container tests passed."
