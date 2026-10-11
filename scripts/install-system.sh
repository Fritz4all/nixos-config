#!/usr/bin/env bash
# Step 5 of the installer: installs NixOS on the disk mounted on /mnt (see prepare-disk.sh), with the choices
# from step 4 (settings.sh, saved in <config>/.install-choice):
#   1. creates the config hosts/<variant> when it is a new variant (new-host.sh), or checks the existing one
#   2. runs nixos-install --flake /mnt/etc/nixos#<variant>
#   3. writes the machine name to /etc/hostname on the new system (not in Git)
#   4. lets you set the passwords for root and your user
#   5. shows an overview of all versions
#
# Usage: bash scripts/install-system.sh [--dry-run] [--no-reboot]
#   --dry-run    only show what would happen, nothing is installed
#   --no-reboot  do not ask to reboot at the end (used by install.sh, the installation menu)
set -euo pipefail

MNT="${MNT:-/mnt}"
CFG="$MNT/etc/nixos"
CHOICE="$CFG/.install-choice"
ISO_MARKER="${ISO_MARKER:-/etc/nixos-config-iso}"
DRY_RUN=0
NO_REBOOT=0

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
    *) die "Unknown option: $arg" ;;
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
[[ -f "$CHOICE" ]] || die "The settings have not been made yet. Run step 4 first: bash $CFG/scripts/settings.sh"

VARIANT=""; NEW_VARIANT=0; DESKTOP=""; APPS=""; MACHINE_NAME=""
while IFS='=' read -r k v; do
  case "$k" in
    VARIANT) VARIANT="$v" ;; NEW_VARIANT) NEW_VARIANT="$v" ;; DESKTOP) DESKTOP="$v" ;;
    APPS) APPS="$v" ;; MACHINE_NAME) MACHINE_NAME="$v" ;;
  esac
done < "$CHOICE"
[[ -n "$VARIANT" && -n "$MACHINE_NAME" ]] || die "$CHOICE is incomplete. Run step 4 again."

OFFLINE_ISO=0
if [[ -f "$ISO_MARKER" ]] && grep -qx "$VARIANT" "$ISO_MARKER"; then OFFLINE_ISO=1; fi
if (( ! OFFLINE_ISO )) && ! curl -fsS --max-time 8 -o /dev/null https://cache.nixos.org/nix-cache-info >/dev/null 2>&1; then
  check "No internet connection. nixos-install has to download packages; connect first (Wi-Fi or cable) and try again."
fi

read_var() {
  command -v nix-instantiate >/dev/null 2>&1 || return 0
  nix-instantiate --eval --strict -E "(import $CFG/vars.nix).$1" 2>/dev/null | tr -d '"' || true
}
USERNAME="$(read_var username)"
if [[ -z "$USERNAME" ]]; then
  read -rp "What is the username from vars.nix? " USERNAME
  [[ -n "$USERNAME" ]] || die "No username."
fi

str_of()  { sed -n "s/.*\b$1[[:space:]]*=[[:space:]]*\"\([^\"]*\)\".*/\1/p" "$2" 2>/dev/null | head -n 1; }
bool_of() { sed -n "s/.*\b$1[[:space:]]*=[[:space:]]*\(true\|false\).*/\1/p" "$2" 2>/dev/null | head -n 1; }
DISK_ENC=false
[[ "$(findmnt -no SOURCE "$MNT" 2>/dev/null || true)" == /dev/mapper/cryptroot ]] && DISK_ENC=true

##### The config: new variant or existing one #####

HOST="$CFG/hosts/$VARIANT"
CREATE=0
if (( NEW_VARIANT )); then
  if [[ -d "$HOST" ]]; then
    echo
    echo "The config '$VARIANT' exists already (probably from an earlier attempt on this machine)."
    echo "  1) Use it as it is"
    echo "  2) Make it again (detect the hardware again)"
    read -rp "Choose 1 or 2 [1]: " c
    if [[ "$c" == 2 ]]; then run rm -rf "$HOST"; CREATE=1; fi
  else
    CREATE=1
  fi
else
  [[ -d "$HOST" ]] || die "The config '$VARIANT' does not exist in hosts/. Run step 4 again."
  enc="$(bool_of my.disk.encrypted "$HOST/default.nix")"
  if (( ! DRY_RUN )) && [[ "${enc:-true}" != "$DISK_ENC" ]]; then
    die "The config '$VARIANT' expects a disk that is $([[ "${enc:-true}" == true ]] && echo encrypted || echo "not encrypted"), but this disk is not. Redo step 2, or choose another config in step 4."
  fi
  DESKTOP="$(str_of my.desktop "$HOST/default.nix")"; APPS="$(str_of my.desktopApps "$HOST/default.nix")"
fi

##### Offline from the ISO: is really everything there? #####

# Evaluates the system that is going to be installed (without network) and checks that it is in the ISO's store.
# Only then the installation runs without internet. (Verified in a VM without network: nixos-install does not take
# the system from the ISO's store by itself, so it is copied to the new disk before nixos-install runs.)
NIXF=(nix --extra-experimental-features 'nix-command flakes')
SYSTEM_PATH=""
if (( OFFLINE_ISO && ! DRY_RUN && ! CREATE )); then
  echo
  echo "Checking that everything for '$VARIANT' is on the ISO (without network) ..."
  SYSTEM_PATH="$("${NIXF[@]}" eval --offline --raw "$CFG#nixosConfigurations.$VARIANT.config.system.build.toplevel.outPath" 2>/dev/null || true)"
  if [[ -n "$SYSTEM_PATH" ]] && "${NIXF[@]}" path-info --offline "$SYSTEM_PATH" >/dev/null 2>&1; then
    echo "Everything is on the ISO: the installation needs no internet."
  else
    warn "Not everything is on the ISO (another username or full name, another release, or a changed config?)."
    OFFLINE_ISO=0
    SYSTEM_PATH=""
    if ! curl -fsS --max-time 8 -o /dev/null https://cache.nixos.org/nix-cache-info >/dev/null 2>&1; then
      die "The missing parts have to be downloaded, but there is no internet. Connect (step 1), or use the values the ISO was made for."
    fi
    echo "The missing parts are downloaded from the internet."
  fi
fi

##### Update versions (optional) #####

UPDATE=0
if (( OFFLINE_ISO )); then
  echo
  echo "Installing from an ISO that already has everything for '$VARIANT': no internet needed."
elif [[ -f "$CFG/flake.lock" ]]; then
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
echo "  Machine name:   $MACHINE_NAME (only on this machine)"
echo "  Config:         $VARIANT$( (( CREATE )) && echo " (new)")"
echo "  User:           $USERNAME"
echo "  Desktop:        ${DESKTOP:-unknown}${APPS:+ ($APPS)}"
echo "  Disk:           $([[ "$DISK_ENC" == true ]] && echo encrypted || echo "not encrypted")"
echo "  NixOS release:  $(sed -n 's/.*inputs\.nixpkgs\.url.*nixos-\([^"]*\)".*/\1/p' "$CFG/flake.nix" | head -n 1)"
echo "  Target system:  $MNT"
VIRT="$(systemd-detect-virt --vm 2>/dev/null || true)"
if [[ -n "$VIRT" && "$VIRT" != none ]]; then
  echo "  Virtual machine: $VIRT (guest tools are turned on)"
fi
echo
read -rp "Continue with the installation? [Y/n]: " go
[[ "$go" =~ ^[nN] ]] && { echo "Stopped, nothing was installed."; exit 0; }

##### Create the config #####

if (( CREATE )); then
  run bash "$CFG/scripts/new-host.sh" "$VARIANT" --root "$MNT" --desktop "$DESKTOP" --apps "$APPS" \
    --encrypted "$([[ "$DISK_ENC" == true ]] && echo yes || echo no)"
fi
if (( UPDATE )); then
  run nix --extra-experimental-features 'nix-command flakes' flake update --flake "$CFG"
  if git -C "$CFG" rev-parse --is-inside-work-tree >/dev/null 2>&1; then run git -C "$CFG" add -A; fi
fi

##### Install #####

trap 'echo; echo "The installation did not finish. Read the error message above; then run step 5 again." >&2' ERR

echo
if (( OFFLINE_ISO )); then
  echo "nixos-install is starting (everything comes from the ISO; this takes a few minutes) ..."
else
  echo "nixos-install is starting (this takes 10 to 30 minutes) ..."
fi
echo "After that you set two passwords: one for root (the administrator account) and one for $USERNAME."
# --no-root-passwd: the root password is set below, where a typo only means trying again
# (when nixos-install asks for it itself, a typo makes the whole installation fail).
# Offline from the ISO: first copy the config's sources (nixpkgs) and the complete system from the ISO's store to
# the new disk; nixos-install then finds everything there and needs no internet.
if (( OFFLINE_ISO )) && [[ -n "$SYSTEM_PATH" ]]; then
  echo "Copying the software from the ISO to the new disk ..."
  run "${NIXF[@]}" flake archive --offline --no-check-sigs --to "$MNT" "$CFG"
  run "${NIXF[@]}" copy --offline --no-check-sigs --to "$MNT" "$SYSTEM_PATH"
fi
# --no-channel-copy: this config uses flakes only (nix.channel.enable = false); copying the installer's channels
# only causes "channels exist, but channels have been disabled" warnings on the new system
run nixos-install --no-root-passwd --no-channel-copy --flake "$CFG#$VARIANT"
run rm -rf "$MNT/root/.nix-defexpr/channels"

trap - ERR

##### Machine name (only on this machine) #####

if (( DRY_RUN )); then
  echo "+ $MNT/etc/hostname: $MACHINE_NAME"
else
  echo "$MACHINE_NAME" > "$MNT/etc/hostname"
fi

##### Passwords #####

# Sets a password in the new system. You type it twice; if they do not match, you simply try again.
set_password() {  # set_password <account> <description>
  local again
  while true; do
    echo
    echo "Set the password for $2 (type it twice):"
    if run nixos-enter --root "$MNT" -c "passwd $1"; then return 0; fi
    echo "That did not work (the two passwords probably did not match)."
    read -rp "Try again? [Y/n]: " again || again=n
    if [[ "$again" =~ ^[nN] ]]; then
      warn "The password for $1 was not set. Set it later with: nixos-enter --root $MNT -c 'passwd $1'"
      return 0
    fi
  done
}

set_password root "root (the administrator account)"
set_password "$USERNAME" "your user $USERNAME"

# Add flake.lock and a new config to Git right away, so you can commit them later
if git -C "$CFG" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  run git -C "$CFG" add -A
fi

# Give /etc/nixos to the user, so editing the config, git and the daily commands work without sudo
run nixos-enter --root "$MNT" -c "chown -R $USERNAME:users /etc/nixos" \
  || warn "Could not give /etc/nixos to $USERNAME. After the first start run: sudo chown -R \$USER:users /etc/nixos"

##### Versions #####

run bash "$CFG/scripts/versions.sh" --root "$MNT"

echo "Installation of '$MACHINE_NAME' (config $VARIANT) is finished."
(( NO_REBOOT )) && exit 0
echo
echo "Next steps:"
echo "  1. Remove the USB stick and reboot."
echo "  2. Optional: save the config to GitHub (see README, 2.5)."
echo "  3. You can view the versions again later with: versions"
echo
read -rp "Reboot now? [y/N]: " rb
if [[ "$rb" =~ ^[yYjJ] ]]; then
  run reboot
fi
