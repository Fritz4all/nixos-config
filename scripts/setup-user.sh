#!/usr/bin/env bash
# Asks for the settings of the installation and writes them to the config in <MNT>/etc/nixos
# (default /mnt/etc/nixos): username, full name and desktop (vars.nix), and the NixOS release
# (flake.nix, via release.sh). Then it continues with the installation (install.sh).
#
# The current value is the default answer: press Enter to keep it.
# Run this after fetch-config.sh (otherwise "Download config" overwrites your change again).
#
# Usage: bash scripts/setup-user.sh [options]
#   --user NAME        username without asking
#   --fullname NAME    full name without asking
#   --desktop NAME     gnome or plasma, without asking
#   --release RELEASE  NixOS release without asking (format YY.MM, or unstable)
#   --no-continue      only change vars.nix, do not continue to install.sh
#   --dry-run          only show what would happen
# If the system is not mounted on /mnt: MNT=/path bash scripts/setup-user.sh
set -euo pipefail

MNT="${MNT:-/mnt}"
USER_ARG=""
FULL_ARG=""
DESK_ARG=""
REL_ARG=""
CONTINUE=1
DRY_RUN=0

die()   { echo "ERROR: $*" >&2; exit 1; }
warn()  { echo "Warning: $*" >&2; }
usage() { sed -n '2,/^set -/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'; }
prompt() { read -rp "$1" REPLY || { echo; die "No more input received."; }; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --user)        USER_ARG="${2:?--user needs a value}"; shift 2 ;;
    --fullname)    FULL_ARG="${2:?--fullname needs a value}"; shift 2 ;;
    --desktop)     DESK_ARG="${2:?--desktop needs gnome or plasma}"; shift 2 ;;
    --release)     REL_ARG="${2:?--release needs a release}"; shift 2 ;;
    --no-continue) CONTINUE=0; shift ;;
    --dry-run)     DRY_RUN=1; shift ;;
    -h|--help)     usage; exit 0 ;;
    *)             die "Unknown option: $1" ;;
  esac
done

CFG="$MNT/etc/nixos"
VARS="$CFG/vars.nix"
[[ -f "$VARS" ]] || die "No $VARS found. Run this first: bash scripts/fetch-config.sh"
[[ -w "$VARS" ]] || die "No write permission on $VARS (run this as root: sudo -i)."

# Read the current value of a variable from vars.nix (simple "string" values only)
current() {
  sed -n "s/^[[:space:]]*$1[[:space:]]*=[[:space:]]*\"\([^\"]*\)\".*/\1/p" "$VARS" | head -n 1
}

CUR_USER="$(current username)"
CUR_FULL="$(current fullName)"
CUR_DESK="$(current desktop)"

valid_user() { [[ "$1" =~ ^[a-z_][a-z0-9_-]{0,30}$ && "$1" != root ]]; }
valid_full() { [[ -n "$1" && "$1" != *\"* && "$1" != *\\* && "$1" != *\$* ]]; }

echo
echo "Settings for this and all other machines (stored in vars.nix and flake.nix)."
echo

##### Username #####

USERNAME="$USER_ARG"
if [[ -n "$USERNAME" ]]; then
  valid_user "$USERNAME" || die "'$USERNAME' is not a valid username (lowercase letters, digits, - and _; start with a letter; not 'root')."
else
  while true; do
    if [[ -n "$CUR_USER" ]]; then
      prompt "Username [$CUR_USER]: "
      USERNAME="${REPLY:-$CUR_USER}"
    else
      prompt "Username: "
      USERNAME="$REPLY"
    fi
    if valid_user "$USERNAME"; then break; fi
    echo "Invalid. Use lowercase letters, digits, - and _, starting with a letter (not 'root')."
  done
fi

##### Full name #####

FULLNAME="$FULL_ARG"
if [[ -n "$FULLNAME" ]]; then
  valid_full "$FULLNAME" || die "The full name must not contain \" \\ or \$."
else
  DEFAULT_FULL="${CUR_FULL:-$USERNAME}"
  while true; do
    prompt "Full name (for the login screen) [$DEFAULT_FULL]: "
    FULLNAME="${REPLY:-$DEFAULT_FULL}"
    if valid_full "$FULLNAME"; then break; fi
    echo "Invalid. Do not use \" \\ or \$ in the name."
  done
fi

##### Desktop #####

desk_name() { case "$1" in gnome) echo "GNOME" ;; plasma) echo "KDE Plasma" ;; *) echo "$1" ;; esac; }

DESKTOP="$DESK_ARG"
if [[ -n "$DESKTOP" ]]; then
  [[ "$DESKTOP" == gnome || "$DESKTOP" == plasma ]] || die "--desktop must be gnome or plasma."
else
  [[ "$CUR_DESK" == gnome || "$CUR_DESK" == plasma ]] || CUR_DESK=gnome
  echo
  echo "Desktop:"
  echo "  1) GNOME"
  echo "  2) KDE Plasma"
  while true; do
    prompt "Choose 1 or 2 [$(desk_name "$CUR_DESK")]: "
    case "$REPLY" in
      "") DESKTOP="$CUR_DESK"; break ;;
      1|gnome|GNOME) DESKTOP=gnome; break ;;
      2|plasma|kde|KDE) DESKTOP=plasma; break ;;
      *) echo "Invalid choice." ;;
    esac
  done
fi

##### Save #####

# Make values safe for the replacement text of sed
esc() { local v="$1"; v="${v//\\/\\\\}"; v="${v//&/\\&}"; v="${v//|/\\|}"; printf '%s' "$v"; }

set_var() {  # $1 = name, $2 = value
  if (( DRY_RUN )); then
    echo "+ vars.nix: $1 = \"$2\""
  else
    sed -i "s|^\([[:space:]]*$1[[:space:]]*=[[:space:]]*\)\"[^\"]*\"|\1\"$(esc "$2")\"|" "$VARS"
  fi
}

set_var username "$USERNAME"
set_var fullName "$FULLNAME"
set_var desktop "$DESKTOP"

if (( ! DRY_RUN )); then
  [[ "$(current username)" == "$USERNAME" && "$(current fullName)" == "$FULLNAME" && "$(current desktop)" == "$DESKTOP" ]] \
    || die "Saving to $VARS failed. Edit it by hand."
  if command -v nix-instantiate >/dev/null 2>&1; then
    nix-instantiate --parse "$VARS" >/dev/null 2>&1 || die "$VARS is no longer valid Nix after the change. Check the file."
  fi
  if git -C "$CFG" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git -C "$CFG" add vars.nix
  fi
fi

echo
if (( DRY_RUN )); then echo "Dry run: this would be written to $VARS:"; else echo "Saved in $VARS:"; fi
echo "  Username:   $USERNAME"
echo "  Full name:  $FULLNAME"
echo "  Desktop:    $(desk_name "$DESKTOP")"
echo "Language, time zone and keyboard can be changed in the same file, if you like."

##### NixOS release #####

REL_OPTS=(--dir "$CFG")
(( DRY_RUN )) && REL_OPTS+=(--dry-run)
[[ -n "$REL_ARG" ]] && REL_OPTS+=(--set "$REL_ARG")
bash "$CFG/scripts/release.sh" "${REL_OPTS[@]}" || die "Choosing the NixOS release failed."

##### Continue #####

(( CONTINUE )) || exit 0

echo
prompt "Continue with the installation (name this machine and install)? [Y/n]: "
case "$REPLY" in
  [nN]*)
    echo
    echo "OK. You can install later with:"
    if [[ "$MNT" == /mnt ]]; then echo "  bash $CFG/scripts/install.sh"; else echo "  MNT=$MNT bash $CFG/scripts/install.sh"; fi
    exit 0
    ;;
esac

ARGS=()
(( DRY_RUN )) && ARGS+=(--dry-run)
export MNT
exec bash "$CFG/scripts/install.sh" "${ARGS[@]}"
