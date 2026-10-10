#!/usr/bin/env bash
# Creates a new machine in this repo: hosts/<hostname>/ with hardware detection and stateVersion.
#
# Usage: bash scripts/new-host.sh <hostname> [--root /mnt]
#   --root  where the new system is mounted (default /mnt, as in the installer)
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT="/mnt"
NAME=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --root)
      ROOT="${2:?--root needs a path}"
      shift 2
      ;;
    -h|--help)
      sed -n '2,/^set -/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    -*)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
    *)
      NAME="$1"
      shift
      ;;
  esac
done

if [[ -z "$NAME" ]]; then
  echo "Usage: bash scripts/new-host.sh <hostname> [--root /mnt]" >&2
  exit 1
fi

if [[ ! "$NAME" =~ ^[a-z][a-z0-9-]{0,62}$ ]]; then
  echo "Invalid hostname '$NAME': use lowercase letters, digits and hyphens, starting with a letter." >&2
  exit 1
fi

DEST="$REPO/hosts/$NAME"
if [[ -e "$DEST" ]]; then
  echo "hosts/$NAME already exists. Choose another name or remove that directory first." >&2
  exit 1
fi

# stateVersion = version of the system you are running now (the installer), e.g. "26.05"
STATE_VERSION="$(nixos-version 2>/dev/null | cut -d. -f1,2 || true)"
if [[ ! "$STATE_VERSION" =~ ^[0-9]{2}\.[0-9]{2}$ ]]; then
  STATE_VERSION="26.05"
fi

mkdir -p "$DEST"
trap 'echo "Failed; hosts/'"$NAME"' is removed again." >&2; rm -rf "$DEST"' ERR

sed "s/@STATE_VERSION@/$STATE_VERSION/" "$REPO/hosts/_template/default.nix" > "$DEST/default.nix"

echo "Detecting hardware (system mounted on $ROOT) ..."
nixos-generate-config --root "$ROOT" --show-hardware-config > "$DEST/hardware-configuration.nix"

trap - ERR

# Flakes only see files that Git knows about, so add them right away.
if git -C "$REPO" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git -C "$REPO" add -A "hosts/$NAME"
else
  echo "Note: $REPO is not a Git repo. Run 'git init -b main && git add -A' first (flakes need Git)." >&2
fi

echo
echo "Done: hosts/$NAME has been created (stateVersion $STATE_VERSION)."
# install.sh continues by itself; only point to the next step when used on its own.
if [[ -z "${NEW_HOST_QUIET:-}" ]]; then
  echo
  echo "Next step, install:"
  echo "  bash $REPO/scripts/install.sh $NAME"
fi
