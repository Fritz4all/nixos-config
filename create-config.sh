#!/usr/bin/env bash
# Creates a config for the type of the machine this script runs on, from its hardware, and puts it next to this
# script (hosts/<config>/), ready to be pushed to GitHub. After that every machine of this type can be installed
# with it, also offline from an ISO made by build-iso.sh. Nothing is installed or changed on the machine itself.
#
# Run it on the machine whose hardware you want: in the NixOS installer (live USB), on an installed NixOS, or on
# another Linux system with Nix (e.g. Ubuntu). Manual: docs/create-config.md
#
#   1. shows this machine (vendor, model, kind) and the configs that already exist for its type
#   2. asks for the desktop (GNOME / KDE Plasma), its apps (Minimal / Full), disk encryption and the config name
#   3. detects the hardware (nixos-generate-config, without disks) and creates the config with scripts/new-host.sh
#      (including guest tools in a VM, and Solaar when a Logitech receiver or mouse is attached)
#   4. checks the new config with Nix
#   5. offers to save it to GitHub (git commit + git push)
#
# Usage: bash create-config.sh [options]
#   --desktop NAME      gnome or plasma, without asking
#   --apps SET          minimal or full, without asking
#   --encrypted yes|no  disk encryption of the machines that will use it, without asking
#   --name NAME         name of the config, without asking
#   --no-push           do not offer to save it to GitHub
#   --dry-run           only show what would happen
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DESK_ARG=""; APPS_ARG=""; ENC_ARG=""; NAME_ARG=""; PUSH=1; DRY_RUN=0

die()   { echo "ERROR: $*" >&2; exit 1; }
usage() { sed -n '2,/^set -/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'; }
prompt() { read -rp "$1" REPLY || { echo; die "No more input received."; }; }
ask_yes() {  # ask_yes "question" y|n
  local hint="[y/N]"; [[ "$2" == y ]] && hint="[Y/n]"
  prompt "$1 $hint: "
  case "$REPLY" in [yYjJ]*) return 0 ;; [nN]*) return 1 ;; *) [[ "$2" == y ]] ;; esac
}
desk_name() { case "$1" in gnome) echo "GNOME" ;; plasma) echo "KDE Plasma" ;; *) echo "$1" ;; esac; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --desktop)   DESK_ARG="${2:?--desktop needs gnome or plasma}"; shift 2 ;;
    --apps)      APPS_ARG="${2:?--apps needs minimal or full}"; shift 2 ;;
    --encrypted) ENC_ARG="${2:?--encrypted needs yes or no}"; shift 2 ;;
    --name)      NAME_ARG="${2:?--name needs a value}"; shift 2 ;;
    --no-push)   PUSH=0; shift ;;
    --dry-run)   DRY_RUN=1; shift ;;
    -h|--help)   usage; exit 0 ;;
    *)           die "Unknown option: $1" ;;
  esac
done

[[ -w "$REPO/hosts" ]] || die "Cannot write to $REPO/hosts (read-only USB stick or ISO?). Copy the folder to a writable place first, e.g.: cp -r $REPO ~/nixos-config"
# shellcheck source=scripts/machine-info.sh
source "$REPO/scripts/machine-info.sh"
var_of() { sed -n "s/^[[:space:]]*$1[[:space:]]*=[[:space:]]*\"\([^\"]*\)\".*/\1/p" "$REPO/vars.nix" | head -n 1; }
release_of() { sed -n 's/.*inputs\.nixpkgs\.url.*nixos-\([^"]*\)".*/\1/p' "$REPO/flake.nix" | head -n 1; }

##### 1. This machine #####

VENDOR="$(machine_vendor)"; MODEL="$(machine_model)"; KIND="$(machine_kind)"; TYPE="$(machine_type)"
echo
echo "This machine: $VENDOR $MODEL ($KIND)"
echo "Machine type: $TYPE"
EXISTING=()
while IFS='|' read -r v ven mod _kind desk apps enc; do
  [[ -n "$v" && "$ven" == "$VENDOR" && "$mod" == "$MODEL" ]] || continue
  EXISTING+=("$v")
  printf '  existing config: %-44s %s (%s), %s\n' "$v" "$(desk_name "$desk")" "$apps" "$([[ "$enc" == true ]] && echo encrypted || echo "not encrypted")"
done < <(bash "$REPO/scripts/hosts-overview.sh" --list --dir "$REPO")
(( ${#EXISTING[@]} )) || echo "  There is no config for this machine type yet."

##### 2. The new config: desktop, apps, encryption, name #####

DESKTOP="$DESK_ARG"
if [[ -z "$DESKTOP" ]]; then
  d="$(var_of desktop)"; [[ "$d" == gnome || "$d" == plasma ]] || d=gnome
  echo
  echo "Desktop:  1) GNOME   2) KDE Plasma"
  while true; do
    prompt "Choose 1 or 2 [$(desk_name "$d")]: "
    case "$REPLY" in "") DESKTOP="$d"; break ;; 1|gnome) DESKTOP=gnome; break ;; 2|plasma|kde) DESKTOP=plasma; break ;; *) echo "Invalid choice." ;; esac
  done
fi
[[ "$DESKTOP" == gnome || "$DESKTOP" == plasma ]] || die "--desktop must be gnome or plasma."

APPS="$APPS_ARG"
if [[ -z "$APPS" ]]; then
  a="$(var_of desktopApps)"; [[ "$a" == full || "$a" == minimal ]] || a=minimal
  echo
  echo "Apps:  1) Full (the desktop's usual set)   2) Minimal (only what you need to work)"
  while true; do
    prompt "Choose 1 or 2 [$([[ "$a" == minimal ]] && echo Minimal || echo Full)]: "
    case "$REPLY" in "") APPS="$a"; break ;; 1|full) APPS=full; break ;; 2|minimal) APPS=minimal; break ;; *) echo "Invalid choice." ;; esac
  done
fi
[[ "$APPS" == full || "$APPS" == minimal ]] || die "--apps must be minimal or full."

ENCRYPTED="$ENC_ARG"
if [[ -z "$ENCRYPTED" ]]; then
  echo
  if ask_yes "Will the machines of this type be installed with disk encryption (recommended for laptops)?" y; then ENCRYPTED=yes; else ENCRYPTED=no; fi
fi
[[ "$ENCRYPTED" == yes || "$ENCRYPTED" == no ]] || die "--encrypted must be yes or no."

base="$TYPE-$DESKTOP"; [[ "$APPS" == minimal ]] && base+="-minimal"; [[ "$ENCRYPTED" == no ]] && base+="-unencrypted"
suggestion="$base"; n=2
while [[ -e "$REPO/hosts/$suggestion" ]]; do suggestion="$base-$n"; n=$((n + 1)); done
NAME="$NAME_ARG"
if [[ -z "$NAME" ]]; then
  echo
  while true; do
    prompt "Name of the new config [$suggestion]: "
    NAME="${REPLY:-$suggestion}"
    [[ "$NAME" =~ ^[a-z][a-z0-9-]{0,62}$ ]] || { echo "Invalid. Use lowercase letters, digits and hyphens, starting with a letter."; continue; }
    [[ -e "$REPO/hosts/$NAME" ]] && { echo "That config exists already; choose another name."; continue; }
    break
  done
fi
[[ "$NAME" =~ ^[a-z][a-z0-9-]{0,62}$ && ! -e "$REPO/hosts/$NAME" ]] || die "'$NAME' is not a valid new config name (or it exists already)."

##### 3. Detect the hardware and create the config #####

# nixos-generate-config: on NixOS it is there; elsewhere it is run through Nix
NIX=()
if command -v nix >/dev/null 2>&1; then NIX=(nix --extra-experimental-features 'nix-command flakes')
elif [[ -x "${NIX_DEFAULT_BIN:-/nix/var/nix/profiles/default/bin/nix}" ]]; then NIX=("${NIX_DEFAULT_BIN:-/nix/var/nix/profiles/default/bin/nix}" --extra-experimental-features 'nix-command flakes'); fi
TOOLS_DIR=""
if ! command -v nixos-generate-config >/dev/null 2>&1; then
  (( ${#NIX[@]} )) || die "nixos-generate-config and Nix are both missing. Run this in the NixOS installer, or install Nix first (see docs/create-config.md)."
  TOOLS_DIR="$(mktemp -d)"
  trap 'rm -rf "$TOOLS_DIR"' EXIT
  cat > "$TOOLS_DIR/nixos-generate-config" <<EOF
#!/usr/bin/env bash
exec $(printf '%q ' "${NIX[@]}") shell $(printf '%q' "github:NixOS/nixpkgs/nixos-$(release_of)#nixos-install-tools") -c nixos-generate-config "\$@"
EOF
  chmod +x "$TOOLS_DIR/nixos-generate-config"
  echo "(nixos-generate-config is not on this system; it is run through Nix.)"
fi

echo
echo "Creating hosts/$NAME: $VENDOR $MODEL, $(desk_name "$DESKTOP") ($APPS), encrypted: $ENCRYPTED"
if (( DRY_RUN )); then
  echo "+ scripts/new-host.sh $NAME --root / --desktop $DESKTOP --apps $APPS --encrypted $ENCRYPTED"
  echo "Dry run: nothing was created."
  exit 0
fi
PATH="${TOOLS_DIR:+$TOOLS_DIR:}$PATH" bash "$REPO/scripts/new-host.sh" "$NAME" --root / \
  --desktop "$DESKTOP" --apps "$APPS" --encrypted "$ENCRYPTED"

##### 4. Check it with Nix #####

if (( ${#NIX[@]} )); then
  echo
  echo "Checking the new config with Nix ..."
  if "${NIX[@]}" eval --raw "path:$REPO#nixosConfigurations.$NAME.config.system.build.toplevel.drvPath" >/dev/null 2>&1; then
    echo "OK: the config is valid."
  else
    echo "Warning: Nix could not evaluate the new config. Details: nix eval path:$REPO#nixosConfigurations.$NAME.config.system.build.toplevel.drvPath"
  fi
fi

##### 5. Save to GitHub #####

echo
echo "Created: $REPO/hosts/$NAME/ (default.nix, machine.nix, hardware-configuration.nix) and hosts/README.md"
if (( PUSH )) && git -C "$REPO" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  if ask_yes "Save it to GitHub now (git commit + git push)?" y; then
    git -C "$REPO" add "hosts/$NAME" hosts/README.md
    git -C "$REPO" commit -q -m "Add config $NAME ($VENDOR $MODEL)" && echo "Committed."
    if git -C "$REPO" push -q; then
      echo "Pushed: every machine of this type can now be installed with '$NAME' (and build-iso.sh can put it on an ISO)."
    else
      echo "Pushing failed (not logged in? run: gh auth login). Push later with: cd $REPO && git push"
    fi
  else
    echo "Not saved. Later: cd $REPO && git add -A && git commit -m \"Add config $NAME\" && git push"
  fi
else
  echo "Save it to GitHub from this folder with: git add -A && git commit -m \"Add config $NAME\" && git push"
fi
