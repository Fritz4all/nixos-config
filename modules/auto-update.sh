# Weekly automatic update, run by systemd as root (service nixos-auto-update, see auto-update.nix).
# 1. Updates flake.lock as the owner of the config directory (git refuses a repository owned by someone else).
# 2. Builds the new system for the next start (`boot`): nothing changes while you work, and the previous
#    version stays in the boot menu. `path:` lets root read the directory although it belongs to the user.
set -euo pipefail

CFG="${NIXOS_CONFIG_DIR:-/etc/nixos}"
VARIANT="${AUTO_UPDATE_VARIANT:?AUTO_UPDATE_VARIANT is not set}"
OWNER="$(stat -c %U "$CFG")"
NIX=(nix --extra-experimental-features 'nix-command flakes')

echo "Updating flake.lock in $CFG (as $OWNER) ..."
if [[ "$OWNER" == root ]]; then
  "${NIX[@]}" flake update --flake "$CFG"
else
  OWNER_HOME="$(getent passwd "$OWNER" | cut -d: -f6)"
  runuser -u "$OWNER" -- env HOME="$OWNER_HOME" "${NIX[@]}" flake update --flake "$CFG"
fi

echo "Building the new system for the next start ..."
nixos-rebuild boot --flake "path:$CFG#$VARIANT"
echo "Done: the update becomes active at the next start."
