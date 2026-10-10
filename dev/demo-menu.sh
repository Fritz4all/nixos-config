#!/usr/bin/env bash
# Opens the installation menu in dry-run mode with fake installer commands (dev/stubs/),
# so you can click through it safely on any Linux machine. Nothing is changed.
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/mnt"
PATH="$REPO/dev/stubs:$PATH" bash "$REPO/scripts/menu.sh" --dry-run --root "$WORK/mnt"
