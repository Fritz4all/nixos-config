#!/usr/bin/env bash
# Creates a new machine in this repo: hosts/<hostname>/ with hardware detection and stateVersion.
# In a virtual machine it also turns on the guest tools for that kind of VM (QEMU/KVM, VMware); NixOS's own
# hardware detection already handles VirtualBox, Hyper-V and Parallels.
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

# stateVersion = the NixOS release this machine is first installed with (format YY.MM).
# Taken from flake.nix; for nixos-unstable from the installer that is running now.
STATE_VERSION="$(sed -n 's/.*inputs\.nixpkgs\.url.*nixos-\([0-9][0-9]\.[0-9][0-9]\)".*/\1/p' "$REPO/flake.nix" | head -n 1)"
if [[ ! "$STATE_VERSION" =~ ^[0-9]{2}\.[0-9]{2}$ ]]; then
  STATE_VERSION="$(nixos-version 2>/dev/null | cut -d. -f1,2 || true)"
fi
if [[ ! "$STATE_VERSION" =~ ^[0-9]{2}\.[0-9]{2}$ ]]; then
  echo "Cannot determine the NixOS release for system.stateVersion (no release in flake.nix, no nixos-version)." >&2
  exit 1
fi

mkdir -p "$DEST"
trap 'echo "Failed; hosts/'"$NAME"' is removed again." >&2; rm -rf "$DEST"' ERR

sed "s/@STATE_VERSION@/$STATE_VERSION/" "$REPO/hosts/_template/default.nix" > "$DEST/default.nix"

echo "Detecting hardware (system mounted on $ROOT) ..."
nixos-generate-config --root "$ROOT" --show-hardware-config > "$DEST/hardware-configuration.nix"

# Virtual machine? Then add the guest tools for that kind of VM to this machine's settings.
VIRT="$(systemd-detect-virt --vm 2>/dev/null || true)"
GUEST=""
case "$VIRT" in
  kvm|qemu|bochs)
    GUEST="  services.qemuGuest.enable = true;       # lets the VM host shut this machine down cleanly
  services.spice-vdagentd.enable = true;  # shared clipboard; the screen size follows the window" ;;
  vmware)
    GUEST="  virtualisation.vmware.guest.enable = true;  # open-vm-tools: clipboard, screen size, drag and drop" ;;
esac
if [[ -n "$GUEST" ]]; then
  # Insert the block before the final closing brace of default.nix
  { sed '$d' "$DEST/default.nix"
    printf '\n  # Virtual machine (%s): guest tools, added by new-host.sh during installation.\n%s\n}\n' "$VIRT" "$GUEST"
  } > "$DEST/default.nix.new"
  mv "$DEST/default.nix.new" "$DEST/default.nix"
  echo "Virtual machine detected ($VIRT): guest tools are turned on for this machine."
elif [[ -n "$VIRT" && "$VIRT" != none ]]; then
  echo "Virtual machine detected ($VIRT): NixOS's hardware detection takes care of the guest tools."
fi

trap - ERR

# Flakes only see files that Git knows about, so add them right away.
if git -C "$REPO" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git -C "$REPO" add -A "hosts/$NAME"
else
  echo "Note: $REPO is not a Git repo. Run 'git init -b main && git add -A' first (flakes need Git)." >&2
fi

echo
echo "Done: hosts/$NAME has been created (stateVersion $STATE_VERSION)."
# install-system.sh continues by itself; only point to the next step when used on its own.
if [[ -z "${NEW_HOST_QUIET:-}" ]]; then
  echo
  echo "Next step, install:"
  echo "  bash $REPO/scripts/install-system.sh $NAME"
fi
