#!/usr/bin/env bash
# Installs NixOS on the disk mounted on /mnt (see prepare-disk.sh):
#   1. asks what this machine should be called and creates hosts/<name>
#   2. runs nixos-install --flake /mnt/etc/nixos#<name>
#   3. lets you set the password of your user
#   4. shows an overview of all versions
#
# Usage: bash scripts/install.sh [hostname] [--dry-run] [--no-reboot]
#   --dry-run    only show what would happen, nothing is installed
#   --no-reboot  do not ask to reboot at the end (used by menu.sh)
set -euo pipefail

MNT="${MNT:-/mnt}"
CFG="$MNT/etc/nixos"
DRY_RUN=0
NO_REBOOT=0
NAME=""

die()  { echo "ERROR: $*" >&2; exit 1; }
warn() { echo "Warning: $*" >&2; }

run() {
  if (( DRY_RUN )); then
    printf '+ '; printf '%q ' "$@"; echo
  else
    "$@"
  fi
}

check() {
  if (( DRY_RUN )); then warn "$1 (dry run, continuing)"; else die "$1"; fi
}

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    --no-reboot) NO_REBOOT=1 ;;
    -h|--help) sed -n '2,/^set -/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*) die "Unknown option: $arg" ;;
    *) NAME="$arg" ;;
  esac
done

##### Checks #####

(( EUID == 0 )) || check "Run this as root (type: sudo -i first)."
for cmd in nixos-install nixos-enter nixos-generate-config mountpoint; do
  command -v "$cmd" >/dev/null 2>&1 || check "Program '$cmd' not found."
done
if ! { command -v mountpoint >/dev/null 2>&1 && mountpoint -q "$MNT" && mountpoint -q "$MNT/boot"; }; then
  check "No disk is mounted on $MNT (and $MNT/boot) yet. Run this first: bash scripts/prepare-disk.sh"
fi
[[ -f "$CFG/flake.nix" ]] || die "No config found in $CFG. Run prepare-disk.sh and then fetch-config.sh first."

if ! curl -fsS --max-time 8 -o /dev/null https://cache.nixos.org/nix-cache-info >/dev/null 2>&1; then
  check "No internet connection. nixos-install has to download packages; connect first (Wi-Fi or cable) and try again."
fi

read_var() {
  command -v nix-instantiate >/dev/null 2>&1 || return 0
  nix-instantiate --eval --strict -E "(import $CFG/vars.nix).$1" 2>/dev/null | tr -d '"' || true
}

USERNAME="$(read_var username)"
DESKTOP="$(read_var desktop)"
if [[ -z "$USERNAME" ]]; then
  read -rp "What is the username from vars.nix? " USERNAME
  [[ -n "$USERNAME" ]] || die "No username."
fi

##### Machine name #####

EXISTING=()
for d in "$CFG"/hosts/*/; do
  [[ -d "$d" ]] || continue
  n="$(basename "$d")"
  [[ "$n" == _* ]] || EXISTING+=("$n")
done

echo
if (( ${#EXISTING[@]} > 0 )); then
  echo "Machines already in this config: ${EXISTING[*]}"
  echo "(For a new machine, choose a new, unique name.)"
else
  echo "There are no machines in this config yet."
fi
echo

REUSE=0
REGEN=0
while true; do
  if [[ -z "$NAME" ]]; then
    read -rp "What should this machine be called? (lowercase letters, digits and hyphens, e.g. laptop): " NAME
  fi
  if [[ ! "$NAME" =~ ^[a-z][a-z0-9-]{0,62}$ ]]; then
    echo "Invalid name. Use lowercase letters, digits and hyphens, starting with a letter."
    NAME=""
    continue
  fi
  if [[ -d "$CFG/hosts/$NAME" ]]; then
    echo "The machine '$NAME' already exists in this config."
    echo "  1) Reuse (only choose this if it is the same computer, e.g. after a failed installation)"
    echo "  2) Recreate (detect the hardware again)"
    echo "  3) Choose another name"
    read -rp "Choose 1, 2 or 3: " c
    case "$c" in
      1) REUSE=1; break ;;
      2) REGEN=1; break ;;
      *) NAME=""; continue ;;
    esac
  fi
  break
done

##### Update versions (optional) #####

UPDATE=0
if [[ -f "$CFG/flake.lock" ]]; then
  echo
  echo "There is a flake.lock: package versions are pinned to the moment it was created."
  echo "If it is old, downloading Google Chrome (among others) may fail."
  read -rp "Update all packages first (nix flake update)? [y/N]: " u
  [[ "$u" =~ ^[yYjJ] ]] && UPDATE=1
else
  echo
  echo "There is no flake.lock yet; it is created now with the latest packages."
fi

##### Overview and confirmation #####

echo
echo "Overview"
echo "  Machine:        $NAME"
echo "  User:           $USERNAME"
echo "  Desktop:        ${DESKTOP:-unknown}"
echo "  NixOS release:  $(sed -n 's/.*inputs\.nixpkgs\.url.*nixos-\([^"]*\)".*/\1/p' "$CFG/flake.nix" | head -n 1)"
echo "  Config:         $CFG"
echo "  Target system:  $MNT"
echo
read -rp "Continue with the installation? [Y/n]: " go
[[ "$go" =~ ^[nN] ]] && { echo "Stopped, nothing was installed."; exit 0; }

##### Create machine #####

if (( REGEN )); then
  run rm -rf "$CFG/hosts/$NAME"
fi
if (( ! REUSE )); then
  run env NEW_HOST_QUIET=1 bash "$CFG/scripts/new-host.sh" "$NAME" --root "$MNT"
fi
if (( UPDATE )); then
  run nix --extra-experimental-features 'nix-command flakes' flake update --flake "$CFG"
  if git -C "$CFG" rev-parse --is-inside-work-tree >/dev/null 2>&1; then run git -C "$CFG" add -A; fi
fi

##### Check: does the hardware configuration match the disk that is mounted now? #####
# After repartitioning the UUIDs are different. An old hardware-configuration.nix
# then produces a system that does not boot.

HW="$CFG/hosts/$NAME/hardware-configuration.nix"
ROOT_UUID="$(findmnt -no UUID "$MNT" 2>/dev/null || true)"
if (( ! DRY_RUN )) && [[ -n "$ROOT_UUID" ]]; then
  [[ -f "$HW" ]] || die "hosts/$NAME/hardware-configuration.nix is missing. Run this script again and choose 'Recreate'."
  grep -q "$ROOT_UUID" "$HW" || die "hosts/$NAME/hardware-configuration.nix does not belong to the disk now on $MNT (different UUID). Run this script again and choose 'Recreate' for the name."
fi

##### Install #####

trap 'echo; echo "The installation did not finish. Read the error message above; then run this script again (choose reuse for the name)." >&2' ERR

echo
echo "nixos-install is starting (this takes 10 to 30 minutes) ..."
echo "At the end it asks for a root password."
run nixos-install --flake "$CFG#$NAME"

trap - ERR

##### Password of your user #####

echo
echo "Now set the password for $USERNAME:"
ok=0
for _ in 1 2 3; do
  if run nixos-enter --root "$MNT" -c "passwd $USERNAME"; then ok=1; break; fi
  echo "That did not work, please try again."
done
if (( ! ok )); then
  warn "The password was not set. Do it by hand with: nixos-enter --root $MNT -c 'passwd $USERNAME'"
fi

# Add flake.lock and the new machine to Git right away, so you can commit them later
if git -C "$CFG" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  run git -C "$CFG" add -A
fi

##### Versions #####

run bash "$CFG/scripts/versions.sh" --root "$MNT"

echo "Installation of '$NAME' is finished."
(( NO_REBOOT )) && exit 0
echo
echo "Next steps:"
echo "  1. Remove the USB stick and reboot."
echo "  2. After the first boot: sudo chown -R \$USER:users /etc/nixos, then commit and push (see README)."
echo "  3. You can view the versions again later with: versions"
echo
read -rp "Reboot now? [y/N]: " rb
if [[ "$rb" =~ ^[yYjJ] ]]; then
  run reboot
fi
