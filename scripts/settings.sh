#!/usr/bin/env bash
# Step 4 of the installer: the settings for this installation, in this order:
#   1. username and full name                         (vars.nix, shared by all machines)
#   2. config for this machine: the installer recognises the machine type (vendor + model) and shows every
#      variant of that type in hosts/ (e.g. a GNOME and a KDE Plasma variant), or makes a new variant
#      (then it asks for the desktop and its apps)
#   3. the machine name, e.g. nix-<serial number>   (only on this machine, never in Git)
#   4. the NixOS release                              (flake.nix, via release.sh, shared by all machines)
# The choice is saved in <config>/.install-choice (not in Git) for install-system.sh, which it starts next.
# The current value is the default answer each time: press Enter to keep it.
#
# Usage: bash scripts/settings.sh [options]
#   --user NAME          username without asking
#   --fullname NAME      full name without asking
#   --variant NAME       use this existing config from hosts/ without asking
#   --new-variant NAME   make a new variant with this name (with --desktop and --apps)
#   --desktop NAME       gnome or plasma (for a new variant)
#   --apps SET           full or minimal (for a new variant)
#   --name NAME          machine name without asking
#   --release RELEASE    NixOS release without asking (format YY.MM, or unstable)
#   --no-continue        only save the settings, do not continue to install-system.sh
#   --dry-run            only show what would happen
# If the system is not mounted on /mnt: MNT=/path bash scripts/settings.sh
set -euo pipefail

MNT="${MNT:-/mnt}"
USER_ARG=""; FULL_ARG=""; VARIANT_ARG=""; NEWVAR_ARG=""; DESK_ARG=""; APPS_ARG=""; NAME_ARG=""; REL_ARG=""
CONTINUE=1
DRY_RUN=0
ISO_MARKER="${ISO_MARKER:-/etc/nixos-config-iso}"   # on an ISO from build-iso.sh: variants that are on it

die()   { echo "ERROR: $*" >&2; exit 1; }
warn()  { echo "Warning: $*" >&2; }
usage() { sed -n '2,/^set -/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'; }
prompt() { read -rp "$1" REPLY || { echo; die "No more input received."; }; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --user)        USER_ARG="${2:?--user needs a value}"; shift 2 ;;
    --fullname)    FULL_ARG="${2:?--fullname needs a value}"; shift 2 ;;
    --variant)     VARIANT_ARG="${2:?--variant needs a name}"; shift 2 ;;
    --new-variant) NEWVAR_ARG="${2:?--new-variant needs a name}"; shift 2 ;;
    --desktop)     DESK_ARG="${2:?--desktop needs gnome or plasma}"; shift 2 ;;
    --apps)        APPS_ARG="${2:?--apps needs full or minimal}"; shift 2 ;;
    --name)        NAME_ARG="${2:?--name needs a value}"; shift 2 ;;
    --release)     REL_ARG="${2:?--release needs a release}"; shift 2 ;;
    --no-continue) CONTINUE=0; shift ;;
    --dry-run)     DRY_RUN=1; shift ;;
    -h|--help)     usage; exit 0 ;;
    *)             die "Unknown option: $1" ;;
  esac
done

CFG="$MNT/etc/nixos"
VARS="$CFG/vars.nix"
CHOICE="$CFG/.install-choice"
[[ -f "$VARS" ]] || die "No $VARS found. Run this first: bash scripts/fetch-config.sh"
[[ -w "$VARS" ]] || die "No write permission on $VARS (run this as root: sudo -i)."
# shellcheck source=machine-info.sh
source "$CFG/scripts/machine-info.sh"

current() { sed -n "s/^[[:space:]]*$1[[:space:]]*=[[:space:]]*\"\([^\"]*\)\".*/\1/p" "$VARS" | head -n 1; }
desk_name() { case "$1" in gnome) echo "GNOME" ;; plasma) echo "KDE Plasma" ;; *) echo "$1" ;; esac; }
apps_name() { case "$1" in full) echo "Full" ;; minimal) echo "Minimal" ;; *) echo "$1" ;; esac; }
valid_user()    { [[ "$1" =~ ^[a-z_][a-z0-9_-]{0,30}$ && "$1" != root ]]; }
valid_full()    { [[ -n "$1" && "$1" != *\"* && "$1" != *\\* && "$1" != *\$* ]]; }
valid_variant() { [[ "$1" =~ ^[a-z][a-z0-9-]{0,62}$ ]]; }
valid_machine() { [[ "$1" =~ ^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$ ]]; }

echo
echo "Settings for this installation."
echo

##### 1. Username and full name (shared by all machines) #####

CUR_USER="$(current username)"; CUR_FULL="$(current fullName)"
USERNAME="$USER_ARG"
if [[ -n "$USERNAME" ]]; then
  valid_user "$USERNAME" || die "'$USERNAME' is not a valid username (lowercase letters, digits, - and _; start with a letter; not 'root')."
else
  while true; do
    if [[ -n "$CUR_USER" && "$CUR_USER" != changeme ]]; then prompt "Username [$CUR_USER]: "; USERNAME="${REPLY:-$CUR_USER}"
    else prompt "Username: "; USERNAME="$REPLY"; fi
    valid_user "$USERNAME" && break
    echo "Invalid. Use lowercase letters, digits, - and _, starting with a letter (not 'root')."
  done
fi

FULLNAME="$FULL_ARG"
if [[ -n "$FULLNAME" ]]; then
  valid_full "$FULLNAME" || die "The full name must not contain \" \\ or \$."
else
  DEFAULT_FULL="$CUR_FULL"; [[ -z "$DEFAULT_FULL" || "$DEFAULT_FULL" == "Change Me" ]] && DEFAULT_FULL="$USERNAME"
  while true; do
    prompt "Full name (for the login screen) [$DEFAULT_FULL]: "
    FULLNAME="${REPLY:-$DEFAULT_FULL}"
    valid_full "$FULLNAME" && break
    echo "Invalid. Do not use \" \\ or \$ in the name."
  done
fi

if [[ -s "$ISO_MARKER" && "$USERNAME" != "$CUR_USER" ]]; then
  warn "The systems on this ISO were made for user '$CUR_USER'. With another username the installation needs internet."
fi

##### 2. Config for this machine: type and variant #####

VENDOR="$(machine_vendor)"; MODEL="$(machine_model)"; KIND="$(machine_kind)"; TYPE="$(machine_type)"
DISK_ENC=true
if (( ! DRY_RUN )) && [[ "$(findmnt -no SOURCE "$MNT" 2>/dev/null || true)" != /dev/mapper/cryptroot ]]; then DISK_ENC=false; fi

ALL=(); MATCH=()
while IFS= read -r line; do
  [[ -n "$line" ]] || continue
  ALL+=("$line")
  IFS='|' read -r _v ven mod _rest <<<"$line"
  [[ "$ven" == "$VENDOR" && "$mod" == "$MODEL" ]] && MATCH+=("$line")
done < <(bash "$CFG/scripts/hosts-overview.sh" --list --dir "$CFG")

on_iso() { [[ -f "$ISO_MARKER" ]] && grep -qx "$1" "$ISO_MARKER"; }
describe() {  # describe <line>: "GNOME (full)  encrypted  [on this ISO]"
  local v ven mod kind desk apps enc t
  IFS='|' read -r v ven mod kind desk apps enc <<<"$1"
  t="$(desk_name "$desk") ($apps)"
  [[ "$enc" == true ]] && t+=", encrypted" || t+=", not encrypted"
  on_iso "$v" && t+="  [on this ISO: offline]"
  echo "$t"
}
fits_disk() { local enc; enc="$(cut -d'|' -f7 <<<"$1")"; [[ "$enc" == "$DISK_ENC" ]]; }

VARIANT=""; NEW_VARIANT=0; DESKTOP=""; APPS=""

choose_desktop_apps() {
  local cur_d cur_a
  cur_d="$(current desktop)"; [[ "$cur_d" == gnome || "$cur_d" == plasma ]] || cur_d=gnome
  cur_a="$(current desktopApps)"; [[ "$cur_a" == full || "$cur_a" == minimal ]] || cur_a=full
  DESKTOP="$DESK_ARG"
  if [[ -n "$DESKTOP" ]]; then
    [[ "$DESKTOP" == gnome || "$DESKTOP" == plasma ]] || die "--desktop must be gnome or plasma."
  else
    echo
    echo "Desktop for the new variant:"
    echo "  1) GNOME"
    echo "  2) KDE Plasma"
    while true; do
      prompt "Choose 1 or 2 [$(desk_name "$cur_d")]: "
      case "$REPLY" in
        "") DESKTOP="$cur_d"; break ;;
        1|gnome|GNOME) DESKTOP=gnome; break ;;
        2|plasma|kde|KDE) DESKTOP=plasma; break ;;
        *) echo "Invalid choice." ;;
      esac
    done
  fi
  APPS="$APPS_ARG"
  if [[ -n "$APPS" ]]; then
    [[ "$APPS" == full || "$APPS" == minimal ]] || die "--apps must be full or minimal."
  else
    echo
    echo "Apps that come with $(desk_name "$DESKTOP") (Firefox, Chrome, Brave, Bitwarden and VLC are always installed):"
    if [[ "$DESKTOP" == gnome ]]; then
      echo "  1) Full     GNOME's usual set: Files, Terminal, Text Editor, System Monitor, Disks, Calculator,"
      echo "              Image Viewer, Document Viewer, plus Calendar, Contacts, Maps, Weather, Clocks, Music,"
      echo "              Video player, Camera, Document Scanner, Characters, Fonts, Logs, Disk Usage, Help, ..."
      echo "  2) Minimal  only what you need to work: Files, Terminal, Text Editor, System Monitor, Disks,"
      echo "              Calculator, Image Viewer, Document Viewer (PDF)"
    else
      echo "  1) Full     Plasma's usual set: Dolphin (files), Konsole (terminal), Kate (text editor), Gwenview"
      echo "              (images), Okular (PDF), Ark (archives), Spectacle (screenshots), System Monitor,"
      echo "              plus Elisa (music), Discover (app store), Help, remote desktop, QR scanner, browser add-on"
      echo "  2) Minimal  only what you need to work: Dolphin, Konsole, Kate, Gwenview, Okular, Ark, Spectacle,"
      echo "              System Settings, System Monitor"
    fi
    while true; do
      prompt "Choose 1 or 2 [$(apps_name "$cur_a")]: "
      case "$REPLY" in
        "") APPS="$cur_a"; break ;;
        1|full|Full) APPS=full; break ;;
        2|minimal|Minimal) APPS=minimal; break ;;
        *) echo "Invalid choice." ;;
      esac
    done
  fi
}

new_variant() {
  local base suggestion n=2
  choose_desktop_apps
  base="$TYPE-$DESKTOP"; [[ "$APPS" == minimal ]] && base+="-minimal"
  [[ "$DISK_ENC" == false ]] && base+="-unencrypted"
  suggestion="$base"
  while [[ -e "$CFG/hosts/$suggestion" ]]; do suggestion="$base-$n"; n=$((n + 1)); done
  VARIANT="$NEWVAR_ARG"
  if [[ -n "$VARIANT" ]]; then
    valid_variant "$VARIANT" && [[ ! -e "$CFG/hosts/$VARIANT" ]] || die "'$VARIANT' is not a valid new config name (or it exists already)."
  else
    while true; do
      prompt "Name of the new config [$suggestion]: "
      VARIANT="${REPLY:-$suggestion}"
      if ! valid_variant "$VARIANT"; then echo "Invalid. Use lowercase letters, digits and hyphens, starting with a letter."; continue; fi
      if [[ -e "$CFG/hosts/$VARIANT" ]]; then echo "That config exists already; choose another name."; continue; fi
      break
    done
  fi
  NEW_VARIANT=1
}

pick_from() {  # pick_from <title> <lines...>: VARIANT = chosen existing config
  local title="$1" i v; shift
  local -a list=("$@")
  echo
  echo "$title"
  for i in "${!list[@]}"; do
    v="$(cut -d'|' -f1 <<<"${list[$i]}")"
    printf '  %d) %-46s %s %s\n' "$((i + 1))" "$v" "$(cut -d'|' -f2,3 <<<"${list[$i]}" | tr '|' ' ')" "– $(describe "${list[$i]}")"
  done
  while true; do
    prompt "Choose a number (Enter = back): "
    [[ -z "$REPLY" ]] && return 1
    if [[ "$REPLY" =~ ^[0-9]+$ ]] && (( REPLY >= 1 && REPLY <= ${#list[@]} )); then
      if ! fits_disk "${list[$((REPLY - 1))]}"; then echo "That config does not fit this disk (encryption differs, see step 2)."; continue; fi
      VARIANT="$(cut -d'|' -f1 <<<"${list[$((REPLY - 1))]}")"
      return 0
    fi
    echo "Invalid choice."
  done
}

if [[ -n "$VARIANT_ARG" ]]; then
  [[ -d "$CFG/hosts/$VARIANT_ARG" ]] || die "Config '$VARIANT_ARG' does not exist in hosts/."
  VARIANT="$VARIANT_ARG"
elif [[ -n "$NEWVAR_ARG" ]]; then
  new_variant
else
  echo
  echo "This computer: $VENDOR $MODEL ($KIND), disk $([[ "$DISK_ENC" == true ]] && echo encrypted || echo "not encrypted")"
  while [[ -z "$VARIANT" ]]; do
    default=""
    echo
    if (( ${#MATCH[@]} )); then
      echo "Configs for this machine type:"
      for i in "${!MATCH[@]}"; do
        v="$(cut -d'|' -f1 <<<"${MATCH[$i]}")"
        note=""; fits_disk "${MATCH[$i]}" || note="  (does not fit this disk)"
        printf '  %d) %-46s %s%s\n' "$((i + 1))" "$v" "$(describe "${MATCH[$i]}")" "$note"
        [[ -z "$default" && -z "$note" ]] && default=$((i + 1))
      done
    else
      echo "There is no config for this machine type yet."
    fi
    n_new=$(( ${#MATCH[@]} + 1 )); n_other=$(( ${#MATCH[@]} + 2 ))
    echo "  $n_new) New variant of this type        (you choose the desktop and its apps)"
    (( ${#ALL[@]} )) && echo "  $n_other) Another config                  (all configs of all types)"
    [[ -n "$default" ]] || default="$n_new"
    prompt "Choose [$default]: "
    c="${REPLY:-$default}"
    if [[ "$c" == "$n_new" ]]; then
      new_variant
    elif [[ "$c" == "$n_other" ]] && (( ${#ALL[@]} )); then
      if pick_from "All configs:" "${ALL[@]}"; then
        echo "Note: $VARIANT was made for another machine type; the hardware may differ."
      fi
    elif [[ "$c" =~ ^[0-9]+$ ]] && (( c >= 1 && c <= ${#MATCH[@]} )); then
      if fits_disk "${MATCH[$((c - 1))]}"; then VARIANT="$(cut -d'|' -f1 <<<"${MATCH[$((c - 1))]}")"
      else echo "That config does not fit this disk (encryption differs). Choose another, or redo step 2."; fi
    else
      echo "Invalid choice."
    fi
  done
fi

##### 3. Machine name (only on this machine) #####

SUGGESTED_NAME="$(suggest_machine_name)"
MACHINE_NAME="$NAME_ARG"
if [[ -n "$MACHINE_NAME" ]]; then
  valid_machine "$MACHINE_NAME" || die "'$MACHINE_NAME' is not a valid machine name."
else
  echo
  echo "The machine name stays on this machine only (it is not stored in Git)."
  while true; do
    prompt "Machine name [$SUGGESTED_NAME]: "
    MACHINE_NAME="${REPLY:-$SUGGESTED_NAME}"
    valid_machine "$MACHINE_NAME" && break
    echo "Invalid. Use lowercase letters, digits and hyphens (not at the start or end), at most 63 characters."
  done
fi

##### Save #####

esc() { local v="$1"; v="${v//\\/\\\\}"; v="${v//&/\\&}"; v="${v//|/\\|}"; printf '%s' "$v"; }
set_var() {  # $1 = name, $2 = value
  if (( DRY_RUN )); then echo "+ vars.nix: $1 = \"$2\""
  else sed -i "s|^\([[:space:]]*$1[[:space:]]*=[[:space:]]*\)\"[^\"]*\"|\1\"$(esc "$2")\"|" "$VARS"; fi
}
set_var username "$USERNAME"
set_var fullName "$FULLNAME"

if (( DRY_RUN )); then
  echo "+ $CHOICE: VARIANT=$VARIANT NEW_VARIANT=$NEW_VARIANT DESKTOP=$DESKTOP APPS=$APPS MACHINE_NAME=$MACHINE_NAME"
else
  [[ "$(current username)" == "$USERNAME" && "$(current fullName)" == "$FULLNAME" ]] || die "Saving to $VARS failed. Edit it by hand."
  if command -v nix-instantiate >/dev/null 2>&1; then
    nix-instantiate --parse "$VARS" >/dev/null 2>&1 || die "$VARS is no longer valid Nix after the change. Check the file."
  fi
  printf 'VARIANT=%s\nNEW_VARIANT=%s\nDESKTOP=%s\nAPPS=%s\nMACHINE_NAME=%s\n' \
    "$VARIANT" "$NEW_VARIANT" "$DESKTOP" "$APPS" "$MACHINE_NAME" > "$CHOICE"
  if git -C "$CFG" rev-parse --is-inside-work-tree >/dev/null 2>&1; then git -C "$CFG" add vars.nix; fi
fi

echo
if (( DRY_RUN )); then echo "Dry run: these settings would be saved:"; else echo "Saved:"; fi
echo "  Username:      $USERNAME ($FULLNAME)"
if (( NEW_VARIANT )); then
  echo "  Config:        $VARIANT (new: $(desk_name "$DESKTOP"), $(apps_name "$APPS"))"
else
  echo "  Config:        $VARIANT"
fi
echo "  Machine name:  $MACHINE_NAME (only on this machine)"
echo "Language, time zone and keyboard are in vars.nix, if you want to change them."

##### 4. NixOS release (shared by all machines) #####

REL_OPTS=(--dir "$CFG")
(( DRY_RUN )) && REL_OPTS+=(--dry-run)
[[ -n "$REL_ARG" ]] && REL_OPTS+=(--set "$REL_ARG")
if [[ -s "$ISO_MARKER" && -z "$REL_ARG" ]]; then
  echo
  echo "Installing from an ISO with everything on it: the NixOS release stays as it is (changing it needs internet)."
else
  bash "$CFG/scripts/release.sh" "${REL_OPTS[@]}" || die "Choosing the NixOS release failed."
fi

##### Continue #####

(( CONTINUE )) || exit 0
echo
prompt "Continue with the installation? [Y/n]: "
case "$REPLY" in
  [nN]*)
    echo
    echo "OK. You can install later with:"
    if [[ "$MNT" == /mnt ]]; then echo "  bash $CFG/scripts/install-system.sh"; else echo "  MNT=$MNT bash $CFG/scripts/install-system.sh"; fi
    exit 0 ;;
esac
ARGS=()
(( DRY_RUN )) && ARGS+=(--dry-run)
export MNT
exec bash "$CFG/scripts/install-system.sh" "${ARGS[@]}"
