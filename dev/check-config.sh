#!/usr/bin/env bash
# Checks that the NixOS configuration really evaluates and builds, using a test machine
# (dev/testvm/) instead of real hardware. Works on any Linux machine with Nix or nix-portable.
#
# Usage: bash dev/check-config.sh [--build] [--vm]
#   (no option)  nix flake check, and evaluate both GNOME and KDE Plasma   (fast, ~1 minute)
#   --build      also build the complete system (downloads ~11 GB)
#   --vm         build and start a VM with the desktop (closing the window stops it)
#
# Without Nix: download nix-portable (one file, no root needed) and point to it, e.g.
#   curl -L -o ~/nix-portable https://github.com/DavHau/nix-portable/releases/latest/download/nix-portable-x86_64
#   chmod +x ~/nix-portable
#   NIX_PORTABLE=~/nix-portable bash dev/check-config.sh
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD=0
VM=0
for arg in "$@"; do
  case "$arg" in
    --build) BUILD=1 ;;
    --vm)    VM=1 ;;
    -h|--help) sed -n '2,/^set -/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown option: $arg" >&2; exit 1 ;;
  esac
done

if command -v nix >/dev/null 2>&1; then
  nixc() { nix --extra-experimental-features 'nix-command flakes' "$@"; }
  run_in_store() { bash -c "$1"; }
elif [[ -n "${NIX_PORTABLE:-}" && -x "${NIX_PORTABLE:-}" ]]; then
  nixc() { "$NIX_PORTABLE" nix --extra-experimental-features 'nix-command flakes' "$@"; }
  # Store paths of nix-portable only exist inside its own environment
  run_in_store() { "$NIX_PORTABLE" nix-shell -p bash --run "$1"; }
else
  echo "Nix not found. Install Nix, or use nix-portable (see the top of this script)." >&2
  exit 1
fi

# Copy of the repo with the test machine added (the real repo is not changed).
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
cp -a "$REPO/." "$WORK/"
rm -rf "$WORK/.git"
mkdir -p "$WORK/hosts/testvm"
cp "$REPO/dev/testvm/"*.nix "$WORK/hosts/testvm/"
[[ -f "$REPO/flake.lock" ]] || echo "Note: there is no flake.lock yet; the newest nixos-26.05 is used."
FLAKE="path:$WORK"
SYS="$FLAKE#nixosConfigurations.testvm.config"

echo "== nix flake check"
nixc flake check "$FLAKE"

for desk in gnome plasma; do
  echo "== evaluate with desktop = $desk"
  sed -i "s/desktop = \"[a-z]*\"/desktop = \"$desk\"/" "$WORK/vars.nix"
  nixc eval --raw "$SYS.system.build.toplevel.drvPath" >/dev/null
  warnings="$(nixc eval --json "$SYS.warnings")"
  [[ "$warnings" == "[]" ]] || echo "Warnings: $warnings"
done
sed -i "s/desktop = \"[a-z]*\"/desktop = \"$(sed -n 's/^[[:space:]]*desktop[[:space:]]*=[[:space:]]*"\([a-z]*\)".*/\1/p' "$REPO/vars.nix")\"/" "$WORK/vars.nix"

echo "== versions in this configuration"
nixc eval --json "$FLAKE#nixosConfigurations.testvm" --apply 'n: let p = n.pkgs; in {
  kernel = n.config.boot.kernelPackages.kernel.version; gnome = p.gnome-shell.version;
  plasma = p.kdePackages.plasma-workspace.version; firefox = n.config.programs.firefox.package.version;
  chrome = p.google-chrome.version; brave = p.brave.version; bitwarden = p.bitwarden-desktop.version;
  vlc = p.vlc.version; }'
echo

if (( BUILD )); then
  echo "== building the complete system (this can take a while)"
  nixc build --no-link --print-out-paths "$SYS.system.build.toplevel"
fi

if (( VM )); then
  echo "== building and starting the VM (close its window to stop it)"
  vm="$(nixc build --no-link --print-out-paths "$SYS.system.build.vm")"
  ( cd "$WORK" && NIX_DISK_IMAGE="$WORK/testvm.qcow2" run_in_store "$vm/bin/run-testvm-vm" )
fi

echo "All checks passed."
