#!/usr/bin/env bash
# Shows which NixOS release this config uses and lets you choose another one.
# The release is the branch in flake.nix: inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-<release>";
# Available releases are looked up online (channels.nixos.org), so new releases appear automatically.
#
# Used during installation (by settings.sh, step 4 of the installer) and later to upgrade (command: nixos-release).
# After changing the release on an installed machine: rebuild-boot, reboot, commit and push.
#
# Usage: bash scripts/release.sh [options]
#   (no option)      show the current and the available releases, and ask which one to use
#   --list           only show the available releases
#   --set RELEASE    use this release without asking (format YY.MM, or unstable)
#   --dir DIR        the config directory (default: the repo this script is in)
#   --no-update      do not update flake.lock after a change
#   --dry-run        only show what would happen
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SET=""
LIST_ONLY=0
UPDATE=1
DRY_RUN=0

die()  { echo "ERROR: $*" >&2; exit 1; }
warn() { echo "Warning: $*" >&2; }
prompt() { read -rp "$1" REPLY || { echo; die "No more input received."; }; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --list)      LIST_ONLY=1; shift ;;
    --set)       SET="${2:?--set needs a release (format YY.MM, or unstable)}"; shift 2 ;;
    --dir)       DIR="${2:?--dir needs a path}"; shift 2 ;;
    --no-update) UPDATE=0; shift ;;
    --dry-run)   DRY_RUN=1; shift ;;
    -h|--help)   sed -n '2,/^set -/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'; exit 0 ;;
    *)           die "Unknown option: $1" ;;
  esac
done

FLAKE="$DIR/flake.nix"
[[ -f "$FLAKE" ]] || die "No flake.nix found in $DIR."

URL_RE='^([[:space:]]*inputs\.nixpkgs\.url[[:space:]]*=[[:space:]]*"github:NixOS/nixpkgs/nixos-)([^"]+)(".*)$'

# Release in flake.nix: "YY.MM" or "unstable"
current_release() {
  local line
  line="$(grep -E "$URL_RE" "$FLAKE" | head -n 1 || true)"
  [[ "$line" =~ $URL_RE ]] && echo "${BASH_REMATCH[2]}"
  return 0
}

valid_release() { [[ "$1" =~ ^[0-9]{2}\.(05|11)$ || "$1" == unstable ]]; }

channel_exists() { curl -fsS --max-time 8 -o /dev/null "https://channels.nixos.org/nixos-$1" >/dev/null 2>&1; }

# NixOS releases come out twice a year (YY.05 and YY.11). A new channel exists a few weeks before the
# release date (beta), so a release from this month or later is marked as possibly still in beta.
maybe_beta() {
  local yy="${1%.*}" mm="${1#*.}"
  (( 10#$yy * 100 + 10#$mm >= 10#$(date +%y) * 100 + 10#$(date +%m) ))
}

RELEASES=()   # available stable releases, oldest first
find_releases() {
  local y yy mm r
  y=$((10#$(date +%y)))
  RELEASES=()
  for yy in $((y - 1)) "$y" $((y + 1)); do
    for mm in 05 11; do
      r="$(printf '%02d.%s' "$yy" "$mm")"
      channel_exists "$r" && RELEASES+=("$r")
    done
  done
  # Only offer releases that still get updates. A release gets updates until about a month after the
  # next stable release comes out, so an older release is only shown in the month after that.
  local newest kept=() months
  newest="$(newest_stable)"
  [[ -n "$newest" ]] || return 0
  months=$(( (10#$(date +%y) * 12 + 10#$(date +%m)) - (10#${newest%.*} * 12 + 10#${newest#*.}) ))
  for r in "${RELEASES[@]}"; do
    if [[ "$r" < "$newest" ]]; then
      [[ "$r" == "$(older_of "$newest")" ]] && (( months <= 1 )) && kept+=("$r")
    else
      kept+=("$r")   # the newest stable one, and a newer one that may still be in beta
    fi
  done
  RELEASES=("${kept[@]}")
  return 0
}

older_of() {  # the stable release before YY.MM
  local yy="${1%.*}" mm="${1#*.}"
  if [[ "$mm" == 11 ]]; then printf '%s.05' "$yy"; else printf '%02d.11' $((10#$yy - 1)); fi
}

newest_stable() {  # newest release that is not marked as possibly beta
  local i
  for (( i = ${#RELEASES[@]} - 1; i >= 0; i-- )); do
    maybe_beta "${RELEASES[$i]}" || { echo "${RELEASES[$i]}"; return 0; }
  done
  [[ ${#RELEASES[@]} -gt 0 ]] && echo "${RELEASES[-1]}"
  return 0
}

label() {  # label <release> <current> <recommended>
  local notes=() out
  [[ "$1" == "$2" ]] && notes+=("current")
  [[ "$1" == "$3" ]] && notes+=("recommended: newest stable")
  [[ "$1" != unstable && -n "$3" && "$1" < "$3" ]] && notes+=("older: updates stop soon")
  [[ "$1" != unstable ]] && maybe_beta "$1" && notes+=("may still be in beta")
  [[ "$1" == unstable ]] && notes+=("newest software, changes daily, less tested")
  (( ${#notes[@]} )) || return 0
  out="$(printf '%s, ' "${notes[@]}")"
  echo "  (${out%, })"
}

set_release() {  # set_release <old release> <new release>
  local old="$1" new="$2"
  if [[ "$old" == "$new" ]]; then echo "The config already uses NixOS $new; nothing changed."; return 0; fi
  if [[ "$old" != unstable && "$new" != unstable ]] && [[ "$new" < "$old" ]]; then
    warn "$new is older than $old. Going back to an older release is not supported on an installed machine."
  fi
  if (( DRY_RUN )); then
    echo "+ flake.nix: nixos-$old -> nixos-$new"
  else
    sed -i -E "s#$URL_RE#\\1$new\\3#" "$FLAKE"
    [[ "$(current_release)" == "$new" ]] || die "Changing $FLAKE failed. Edit the inputs.nixpkgs.url line by hand."
  fi
  echo "The config now uses NixOS $new (was $old)."

  if [[ -f "$DIR/flake.lock" ]] && (( UPDATE )); then
    if command -v nix >/dev/null 2>&1; then
      echo "Updating flake.lock to the new release ..."
      if (( DRY_RUN )); then
        echo "+ nix flake update --flake $DIR"
      else
        nix --extra-experimental-features 'nix-command flakes' flake update --flake "$DIR" \
          || warn "Updating flake.lock failed; run 'nixup' later."
      fi
    else
      warn "nix not found; flake.lock is updated at the next 'nixup' or installation."
    fi
  fi
  if (( ! DRY_RUN )) && git -C "$DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git -C "$DIR" add flake.nix flake.lock 2>/dev/null || git -C "$DIR" add flake.nix || true
  fi
  if [[ -e /run/current-system && "$DIR" == /etc/nixos ]]; then
    echo "Apply it with: rebuild-boot, then reboot. Do not change system.stateVersion in hosts/."
  fi
  return 0
}

CURRENT="$(current_release)"
[[ -n "$CURRENT" ]] || die "Cannot find the line inputs.nixpkgs.url = \"github:NixOS/nixpkgs/nixos-…\" in $FLAKE."

if [[ -n "$SET" ]]; then
  valid_release "$SET" || die "'$SET' is not a NixOS release (format YY.MM with 05 or 11, or unstable)."
  set_release "$CURRENT" "$SET"
  exit 0
fi

echo
echo "NixOS release"
echo "  This config uses: $CURRENT"
if ! curl -fsS --max-time 6 -o /dev/null https://channels.nixos.org >/dev/null 2>&1; then
  echo "  The available releases cannot be checked (no internet). Keeping $CURRENT."
  exit 0
fi
find_releases
(( ${#RELEASES[@]} > 0 )) || { echo "  No releases found online. Keeping $CURRENT."; exit 0; }
RECOMMENDED="$(newest_stable)"

OPTIONS=("${RELEASES[@]}" unstable)
echo "  Available:"
for i in "${!OPTIONS[@]}"; do
  printf '    %d) %-9s%s\n' "$((i + 1))" "${OPTIONS[$i]}" "$(label "${OPTIONS[$i]}" "$CURRENT" "$RECOMMENDED")"
done
if [[ "$CURRENT" != unstable && -n "$RECOMMENDED" && "$CURRENT" < "$RECOMMENDED" ]]; then
  echo "  A newer release than $CURRENT is available: $RECOMMENDED."
fi
(( LIST_ONLY )) && exit 0

echo
while true; do
  prompt "Which release? Type the number (Enter = keep $CURRENT): "
  [[ -z "$REPLY" ]] && { echo "Keeping NixOS $CURRENT."; exit 0; }
  if [[ "$REPLY" =~ ^[0-9]+$ ]] && (( REPLY >= 1 && REPLY <= ${#OPTIONS[@]} )); then
    set_release "$CURRENT" "${OPTIONS[$((REPLY - 1))]}"
    exit 0
  fi
  echo "Invalid choice."
done
