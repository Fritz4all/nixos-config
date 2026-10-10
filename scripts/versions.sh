#!/usr/bin/env bash
# Shows the versions of the system and the most important programs.
#
# Usage: bash scripts/versions.sh [--root /mnt]
#   --root  a freshly installed system that is mounted (e.g. /mnt, after nixos-install)
#   without options: the system you are running now
set -euo pipefail

ROOT="/"

die() { echo "ERROR: $*" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --root) ROOT="${2:?--root needs a path}"; shift 2 ;;
    -h|--help) sed -n '2,/^set -/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) die "Unknown option: $1" ;;
  esac
done
ROOT="${ROOT%/}"; [[ -n "$ROOT" ]] || ROOT="/"

command -v nix-store >/dev/null 2>&1 || die "nix-store not found."

STORE_ARGS=()
if [[ "$ROOT" == "/" ]]; then
  SYSTEM="$(readlink -f /run/current-system)" || die "No running NixOS system found."
  LOCK="/etc/nixos/flake.lock"
else
  profiles="$ROOT/nix/var/nix/profiles"
  link="$(readlink "$profiles/system")" || die "No installed system found in $ROOT (has nixos-install finished?)."
  SYSTEM="$(readlink "$profiles/$link")" || die "Cannot find the system in $ROOT."
  STORE_ARGS=(--store "$ROOT")
  LOCK="$ROOT/etc/nixos/flake.lock"
fi

# All packages in the system, as "name-version" (without the hash prefix)
mapfile -t NAMES < <(nix-store "${STORE_ARGS[@]}" --query --requisites "$SYSTEM" \
  | sed -E 's|^.*/[a-z0-9]{32}-||' | sort -u)

# Highest version of a package: version_of <prefix> [regex for the part after the name]
# The default regex allows no hyphens, so outputs such as "-man" or "-dev" do not count.
# Always returns exit code 0 (also when the package is missing), otherwise 'set -e' stops the script.
version_of() {
  local prefix="$1" re="${2:-[0-9][0-9A-Za-z._+]*}" hit
  hit="$(printf '%s\n' "${NAMES[@]}" | grep -E "^${prefix}-${re}\$" | sort -V | tail -n 1 || true)"
  if [[ -n "$hit" ]]; then echo "${hit#"${prefix}"-}"; fi
  return 0
}

row() { printf '  %-22s %s\n' "$1" "${2:-not found}"; }

# NixOS version from the name of the system, e.g. nixos-system-laptop-26.05.20260610.abc123
nixos_ver="$(printf '%s\n' "${NAMES[@]}" | grep -E '^nixos-system-.*-[0-9]{2}\.[0-9]{2}\.' | head -n 1 \
  | sed -E 's/^nixos-system-.*-([0-9]{2}\.[0-9]{2}\..*)$/\1/' || true)"

# nixpkgs version from flake.lock
nixpkgs_info=""
if [[ -f "$LOCK" ]] && command -v nix-instantiate >/dev/null 2>&1; then
  # Without --raw (only newer Nix versions know it); we strip the quotes ourselves.
  rev="$(nix-instantiate --eval -E "(builtins.fromJSON (builtins.readFile $LOCK)).nodes.nixpkgs.locked.rev" 2>/dev/null | tr -d '"' || true)"
  ts="$(nix-instantiate --eval -E "(builtins.fromJSON (builtins.readFile $LOCK)).nodes.nixpkgs.locked.lastModified" 2>/dev/null || true)"
  if [[ -n "$rev" ]]; then
    nixpkgs_info="${rev:0:8}"
    if [[ "$ts" =~ ^[0-9]+$ ]]; then nixpkgs_info="$nixpkgs_info ($(date -u -d "@$ts" +%Y-%m-%d))"; fi
  fi
fi

(( ${#NAMES[@]} > 0 )) || die "Could not get the package list of the system."

echo
if [[ "$ROOT" == "/" ]]; then
  echo "Versions of the running system"
else
  echo "Versions of the system on $ROOT"
fi
echo
echo "System"
row "NixOS" "$nixos_ver"
row "Linux kernel" "$(version_of linux '[0-9]+(\.[0-9]+)+')"
row "systemd" "$(version_of systemd)"
if [[ -f "$LOCK" ]]; then
  row "nixpkgs (flake.lock)" "${nixpkgs_info:-unknown (flake.lock not readable)}"
else
  row "nixpkgs (flake.lock)" "unknown (no flake.lock)"
fi
echo
echo "Desktop"
shown=0
gnome="$(version_of gnome-shell)"
plasma="$(version_of plasma-workspace)"
if [[ -n "$gnome" ]];  then row "GNOME"        "$gnome";  shown=1; fi
if [[ -n "$plasma" ]]; then row "KDE Plasma"   "$plasma"; shown=1; fi
if (( ! shown )); then row "Desktop"; fi
echo
echo "Programs"
row "Firefox"       "$(version_of firefox)"
row "Google Chrome" "$(version_of google-chrome)"
row "Brave"         "$(version_of brave)"
row "Bitwarden"     "$(version_of bitwarden-desktop)"
row "VLC"           "$(version_of vlc)"
echo
