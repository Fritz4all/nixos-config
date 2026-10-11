# Shared part of the daily commands (rebuild, rebuild-boot, nixup, versions, nixos-release).
# Every command works with and without sudo: Nix and git always run as the owner of /etc/nixos
# (the user after installation, or root on older installations); only activation uses sudo.
set -euo pipefail

CFG="${NIXOS_CONFIG_DIR:-/etc/nixos}"
[[ -d "$CFG" ]] || { echo "ERROR: $CFG not found (this command is for an installed NixOS system)." >&2; exit 1; }
OWNER="$(stat -c %U "$CFG")"
# Which config in hosts/ this machine uses (written by the config itself, see modules/common.nix)
VARIANT="$(cat "${NIXOS_VARIANT_FILE:-/etc/nixos-variant}" 2>/dev/null || true)"
[[ -n "$VARIANT" ]] || VARIANT="$(cat /proc/sys/kernel/hostname 2>/dev/null || hostname)"  # older installations

# Runs a command as the owner of the config directory.
as_owner() {
  if [[ "$(id -un)" == "$OWNER" ]]; then
    "$@"
  elif [[ "$OWNER" == root ]]; then
    sudo "$@"
  else
    sudo -u "$OWNER" "$@"
  fi
}

# rebuild_with <switch|boot> [extra nixos-rebuild options]
rebuild_with() {
  local mode="$1"
  shift
  if [[ "$OWNER" == root ]]; then
    as_owner nixos-rebuild "$mode" --flake "$CFG#$VARIANT" "$@"
  else
    # Build as the owner; only the activation runs with sudo.
    as_owner nixos-rebuild "$mode" --flake "$CFG#$VARIANT" --sudo "$@"
  fi
}
