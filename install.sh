#!/usr/bin/env bash
# The NixOS installer: an installation menu with every step in one overview.
#
#   1. Internet connection   (set up Wi-Fi if needed; also checks whether the repo can be downloaded)
#   2. Prepare disk          scripts/prepare-disk.sh
#   3. Fetch config          scripts/fetch-config.sh
#   4. Settings              scripts/settings.sh (username, desktop, Full or Minimal apps, NixOS release)
#   5. Install               scripts/install-system.sh (machine name, nixos-install, passwords, versions)
#   6. Reboot
#
# The menu shows which steps are already done. Enter runs the next step,
# 'a' runs all remaining steps one after another, 'i' shows info (the versions of the installed system).
#
# At the start it checks that all tools it needs are present (git, curl, disk tools, nixos-install).
# Missing tools are installed only when you agree, and only for this session (via nix-shell).
#
# Usage (in the NixOS installer, from a directory outside /mnt, e.g. /root/nixos-config):
#   bash install.sh [--dry-run]
#   --dry-run     only show what would happen (can also be toggled in the menu)
#   --root DIR    where the new system gets mounted (default /mnt; meant for testing only)
set -euo pipefail

SELF_REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MNT="/mnt"
DRY_RUN=0
ORIG_ARGS=("$@")

die()   { echo "ERROR: $*" >&2; exit 1; }
usage() { sed -n '2,/^set -/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    --root)    MNT="${2:?--root needs a path}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *)         die "Unknown option: $1" ;;
  esac
done
MNT="${MNT%/}"
CFG="$MNT/etc/nixos"

# Root is required (except for a dry run). In the installer, sudo works without a password.
if (( EUID != 0 && ! DRY_RUN )); then
  command -v sudo >/dev/null 2>&1 || die "Run this as root (type: sudo -i first)."
  echo "This script needs root privileges and restarts itself with sudo ..."
  exec sudo bash "$0" "${ORIG_ARGS[@]}"
fi

# Vendor, model and kind of this computer (scripts/machine-info.sh)
# shellcheck source=scripts/machine-info.sh
source "$SELF_REPO/scripts/machine-info.sh"

##### Styling #####

if [[ -t 1 && "${TERM:-dumb}" != dumb ]]; then
  B=$'\e[1m'; D=$'\e[2m'; G=$'\e[32m'; Y=$'\e[33m'; R=$'\e[31m'; C=$'\e[36m'; N=$'\e[0m'
  clear_screen() { printf '\e[H\e[2J'; }
else
  B=""; D=""; G=""; Y=""; R=""; C=""; N=""
  clear_screen() { echo; }
fi

prompt() { read -rp "$1" REPLY || { echo; echo "No more input received; stopped."; exit 0; }; }

ask_yes() {  # ask_yes "question" y|n  -> exit code 0 for yes
  local hint="[y/N]"; [[ "$2" == y ]] && hint="[Y/n]"
  prompt "$1 $hint: "
  case "$REPLY" in
    [yYjJ]*) return 0 ;;
    [nN]*)   return 1 ;;
    *)       [[ "$2" == y ]] ;;
  esac
}

pause() { echo; prompt "${D}Enter = back to the menu${N} "; }

##### Required tools #####

# "command:nix package that provides it"
TOOLS=(git:git curl:curl lsblk:util-linux wipefs:util-linux findmnt:util-linux parted:parted
       mkfs.fat:dosfstools mkfs.ext4:e2fsprogs cryptsetup:cryptsetup
       nixos-install:nixos-install-tools nixos-enter:nixos-install-tools nixos-generate-config:nixos-install-tools)
MISSING_CMDS=()
MISSING_PKGS=()

check_tools() {
  local t c p
  MISSING_CMDS=(); MISSING_PKGS=()
  for t in "${TOOLS[@]}"; do
    c="${t%%:*}"; p="${t#*:}"
    command -v "$c" >/dev/null 2>&1 && continue
    MISSING_CMDS+=("$c")
    [[ " ${MISSING_PKGS[*]} " == *" $p "* ]] || MISSING_PKGS+=("$p")
  done
  return 0
}

# Asks whether missing tools may be installed. They are installed only for this session: the menu
# restarts inside 'nix-shell -p <packages>'; nothing is added to the system permanently.
offer_tools() {
  local cmd
  check_tools
  (( ${#MISSING_CMDS[@]} == 0 )) && return 0
  echo
  echo "${Y}Missing tools:${N} ${MISSING_CMDS[*]}"
  echo "They are needed for some steps (packages: ${MISSING_PKGS[*]})."
  if [[ -n "${MENU_TOOLS_TRIED:-}" ]]; then
    echo "They were already installed once in this session, but are still missing. Steps that need them may fail."
    pause; return 0
  fi
  if ! command -v nix-shell >/dev/null 2>&1; then
    echo "They cannot be installed automatically here (nix-shell is missing). Install them yourself."
    pause; return 0
  fi
  if ! has_internet; then
    echo "Installing them needs internet. Connect first (step 1), then press t in the menu."
    pause; return 0
  fi
  if ! ask_yes "Install them now, only for this session?" y; then
    echo "Not installed. Press t in the menu to change your mind."
    pause; return 0
  fi
  cmd="$(printf '%q ' bash "$0" "${ORIG_ARGS[@]}")"
  if (( DRY_RUN )); then
    echo "+ nix-shell -p ${MISSING_PKGS[*]} --run \"$cmd\"   (dry run: not installed)"
    pause; return 0
  fi
  echo "Installing ${MISSING_PKGS[*]} ... the menu then starts again."
  if MENU_TOOLS_TRIED=1 nix-shell -p "${MISSING_PKGS[@]}" --run "$cmd"; then
    exit 0   # the menu inside nix-shell has finished
  fi
  echo "${R}Installing the tools failed${N} (see the messages above)."
  pause
}

##### Status of each step #####

declare -A DONE=()   # steps that succeeded in this session (needed for dry runs)

has_internet() { curl -fsS --max-time 4 -o /dev/null https://cache.nixos.org/nix-cache-info >/dev/null 2>&1; }

# Current value from vars.nix (simple "string" values only), same approach as scripts/settings.sh
var_of() {
  [[ -f "$CFG/vars.nix" ]] || return 0
  sed -n "s/^[[:space:]]*$1[[:space:]]*=[[:space:]]*\"\([^\"]*\)\".*/\1/p" "$CFG/vars.nix" | head -n 1
}

# NixOS release in the config's flake.nix ("YY.MM" or "unstable")
release_of() {
  [[ -f "$CFG/flake.nix" ]] || return 0
  sed -n 's/.*inputs\.nixpkgs\.url.*"github:NixOS\/nixpkgs\/nixos-\([^"]*\)".*/\1/p' "$CFG/flake.nix" | head -n 1
}
desk_name() { case "$1" in gnome) echo "GNOME" ;; plasma) echo "KDE Plasma" ;; *) echo "$1" ;; esac; }

st_disk()      { mountpoint -q "$MNT" 2>/dev/null && mountpoint -q "$MNT/boot" 2>/dev/null; }
st_config()    { [[ -f "$CFG/flake.nix" && -f "$CFG/vars.nix" ]]; }
st_user()      { local u; u="$(var_of username)"; [[ -n "$u" && "$u" != changeme ]]; }
# Choice from step 4 (config variant and machine name), saved by scripts/settings.sh
choice_of()    { sed -n "s/^$1=//p" "$CFG/.install-choice" 2>/dev/null | head -n 1; }
st_choice()    { [[ -n "$(choice_of VARIANT)" && -n "$(choice_of MACHINE_NAME)" ]]; }
# Started from an ISO made by build-iso.sh? Then it has this repo, and the systems of some configs (offline)
ISO_MARKER="${ISO_MARKER:-/etc/nixos-config-iso}"
from_iso()     { [[ -f "$ISO_MARKER" ]]; }
iso_has()      { from_iso && grep -qx "$1" "$ISO_MARKER"; }
st_installed() { [[ -L "$MNT/nix/var/nix/profiles/system" ]]; }  # link into /nix/store, hence -L

# Online address of this config: the 'origin' of this copy, else repoUrl in its vars.nix (same as fetch-config.sh).
repo_url() {
  local u=""
  if command -v git >/dev/null 2>&1 && [[ -e "$SELF_REPO/.git" ]]; then
    u="$(git -c safe.directory='*' -C "$SELF_REPO" remote get-url origin 2>/dev/null || true)"
  fi
  if [[ -z "$u" && -f "$SELF_REPO/vars.nix" ]]; then
    u="$(sed -n 's/^[[:space:]]*repoUrl[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' "$SELF_REPO/vars.nix" | head -n 1)"
  fi
  echo "$u"
}

# Can the repo be downloaded? 0 = yes, 1 = no, 2 = cannot be checked without git (e.g. an ssh URL)
repo_check() {
  case "$1" in
    http://*|https://*)
      curl -fsS --max-time 8 -o /dev/null "${1%/}/info/refs?service=git-upload-pack" >/dev/null 2>&1 ;;
    *)
      command -v git >/dev/null 2>&1 || return 2
      GIT_TERMINAL_PROMPT=0 timeout 15 git ls-remote --exit-code "$1" HEAD >/dev/null 2>&1 ;;
  esac
}

ONLINE=0
REPO_URL=""
REPO_STATE=""   # text for the menu
refresh() {
  local rc=0
  check_tools
  ONLINE=0; has_internet && ONLINE=1
  REPO_URL="$(repo_url)"
  if [[ -z "$REPO_URL" ]]; then
    REPO_STATE="${D}not set (repoUrl in vars.nix) – the config will be copied locally${N}"
  elif (( ! ONLINE )); then
    REPO_STATE="${D}not checked (no internet) – the config will be copied locally${N}"
  else
    repo_check "$REPO_URL" || rc=$?
    case "$rc" in
      0) REPO_STATE="${G}can be downloaded${N} ${D}($REPO_URL)${N}" ;;
      2) REPO_STATE="${D}cannot be checked ($REPO_URL)${N}" ;;
      *) REPO_STATE="${Y}cannot be downloaded${N} ${D}($REPO_URL) – the config will be copied locally${N}" ;;
    esac
  fi
  return 0
}

is_done() {  # is_done <step>
  [[ -n "${DONE[$1]:-}" ]] && return 0
  case "$1" in
    1) (( ONLINE )) ;;
    2) st_disk ;;
    3) st_config ;;
    4) st_config && st_user && st_choice ;;
    5) st_installed ;;
    *) return 1 ;;
  esac
}

detail() {  # short note next to a step
  local src hosts=()
  case "$1" in
    1) if (( ONLINE )); then echo "connected"; else echo "no connection"; fi ;;
    2) if st_disk; then
         src="$(findmnt -no SOURCE "$MNT" 2>/dev/null || true)"
         echo "mounted on $MNT${src:+ ($src)}"
       fi ;;
    3) st_config && echo "in $CFG" ;;
    4) st_config && st_user && st_choice && echo "$(var_of username) · $(choice_of MACHINE_NAME) · $(choice_of VARIANT) · NixOS $(release_of)" ;;
    5) if st_installed; then
         echo "installed ($(cat "$MNT/etc/hostname" 2>/dev/null || choice_of MACHINE_NAME), config $(choice_of VARIANT))"
       fi ;;
  esac
  return 0
}

TITLES=("" "Internet connection" "Prepare disk" "Fetch config" "Settings"
        "Install" "Reboot")

next_step() {
  local i
  for i in 1 2 3 4 5; do is_done "$i" || { echo "$i"; return 0; }; done
  echo 6
}

##### Drawing the menu #####

draw() {
  local i mark nr ram uefi next
  next="$(next_step)"
  ram="$(awk '/MemTotal/ {printf "%.0f GB", $2/1024/1024}' /proc/meminfo 2>/dev/null || true)"
  uefi="no (boot the USB stick in UEFI mode!)"; [[ -d /sys/firmware/efi ]] && uefi="yes"

  clear_screen
  echo "${C}╭────────────────────────────────────────────────────────────╮${N}"
  echo "${C}│${N}${B}               Install NixOS  ·  nixos-config               ${N}${C}│${N}"
  echo "${C}╰────────────────────────────────────────────────────────────╯${N}"
  printf '  %-11s %s\n' "UEFI" "$uefi" "Memory" "${ram:-?}"
  printf '  %-11s %s\n' "Internet" "$( (( ONLINE )) && echo "${G}yes${N}" || echo "${R}no${N}")"
  printf '  %-11s %s\n' "Repo" "$REPO_STATE"
  if (( ${#MISSING_CMDS[@]} > 0 )); then
    printf '  %-11s %s\n' "Tools" "${Y}missing: ${MISSING_CMDS[*]}${N} ${D}(t = install)${N}"
  fi
  printf '  %-11s %s\n' "This PC" "$(machine_vendor) $(machine_model) ($(machine_kind))"
  if st_choice; then
    printf '  %-11s %s\n' "Config" "$(choice_of VARIANT) ${D}(machine name: $(choice_of MACHINE_NAME))${N}"
  fi
  if from_iso; then
    printf '  %-11s %s\n' "ISO" "offline packages for: $(paste -sd' ' "$ISO_MARKER")"
  fi
  [[ -n "$(release_of)" ]] && printf '  %-11s %s\n' "NixOS" "$(release_of)"
  if (( DRY_RUN )); then
    printf '  %-11s %s\n' "Mode" "${Y}DRY RUN${N} – nothing will be changed"
  fi
  echo
  for i in 1 2 3 4 5 6; do
    if (( i <= 5 )) && is_done "$i"; then mark="${G}✔${N}"; else mark="${D}·${N}"; fi
    nr="   "; [[ "$i" == "$next" ]] && nr="${Y}${B}▶${N}  "
    printf '  %s%s %s%d%s  %-22s %s%s%s\n' "$nr" "$mark" "$B" "$i" "$N" "${TITLES[$i]}" "$D" "$(detail "$i")" "$N"
  done
  echo
  echo "  ${B}Enter${N} = run step $next   ${B}1-6${N} = choose a step   ${B}a${N} = run everything"
  echo "  ${B}d${N} = dry run $( (( DRY_RUN )) && echo off || echo on)   ${B}i${N} = info (versions)   ${B}r${N} = refresh   ${B}q${N} = quit"
  (( ${#MISSING_CMDS[@]} > 0 )) && echo "  ${B}t${N} = install missing tools"
  return 0
  echo
}

##### Steps #####

DRY=()
set_dry() { DRY=(); (( DRY_RUN )) && DRY=(--dry-run); return 0; }

# After step 3 the scripts are also in the config on the new disk; use that copy from then on.
script_in_cfg() {
  if [[ -f "$CFG/scripts/$1" ]]; then echo "$CFG/scripts/$1"; else echo "$SELF_REPO/scripts/$1"; fi
}

# Exit codes of a step: 0 = done, 1 = failed, 2 = skipped (you chose not to continue).

# Warns when an earlier step has not been done yet. Exit code 0 = continue.
require() {  # require <step> <message>
  is_done "$1" && return 0
  (( DRY_RUN )) && { echo "${Y}Note:${N} $2 (dry run, continuing)"; return 0; }
  echo "${Y}Note:${N} $2"
  ask_yes "Continue anyway?" n
}

# In a dry run the config is usually not really on the disk yet; then only explain.
dry_without_config() {
  (( DRY_RUN )) && ! st_config || return 1
  echo "Dry run: the config is not in $CFG yet, so this script cannot really be run."
  echo "In a real installation this runs: ${B}$(script_in_cfg "$1")${N}"
  return 0
}

step_1() {
  if has_internet; then
    echo "${G}Internet is available.${N}"
    refresh
    echo "Repo: $REPO_STATE"
    return 0
  fi
  echo "${R}No internet connection.${N}"
  echo "The installation has to download packages. Plug in a network cable or pick a Wi-Fi network"
  echo "(top right in the live environment, or below with nmtui)."
  if command -v nmtui >/dev/null 2>&1 && ask_yes "Set up Wi-Fi with nmtui?" y; then
    if (( DRY_RUN )); then echo "+ nmtui connect"; else nmtui connect || true; fi
  fi
  echo "Checking again ..."
  if has_internet; then echo "${G}Internet is available.${N}"; return 0; fi
  echo "${R}Still no internet.${N}"
  return 1
}

step_2() {
  case "$SELF_REPO" in
    "$MNT"|"$MNT"/*) echo "Step 2 cannot run from $SELF_REPO: $MNT is about to be repartitioned."
                     echo "Fetch the scripts to e.g. /root/nixos-config first (see README, step 3)."; return 1 ;;
  esac
  if st_installed && (( ! DRY_RUN )); then
    echo "${Y}Note:${N} $MNT already holds an installed system. Repartitioning erases it."
    ask_yes "Continue anyway?" n || return 2
  fi
  [[ "$MNT" == /mnt ]] || echo "${Y}Note:${N} prepare-disk.sh always works with /mnt."
  INSTALL_MENU=1 bash "$SELF_REPO/scripts/prepare-disk.sh" "${DRY[@]}"
}

step_3() {
  require 2 "the disk has not been prepared yet (step 2)." || return 2
  if from_iso; then
    # The ISO has this repo with the matching versions: use that copy (and the packages that are on the ISO)
    echo "Started from an ISO with this config on it: the config is copied from the ISO."
    INSTALL_MENU=1 bash "$SELF_REPO/scripts/fetch-config.sh" --root "$MNT" --local --source "$SELF_REPO" --yes "${DRY[@]}"
  else
    INSTALL_MENU=1 bash "$SELF_REPO/scripts/fetch-config.sh" --root "$MNT" "${DRY[@]}"
  fi
}

step_4() {
  require 3 "the config has not been fetched yet (step 3)." || return 2
  dry_without_config settings.sh && return 0
  MNT="$MNT" bash "$(script_in_cfg settings.sh)" --no-continue "${DRY[@]}"
}

step_5() {
  if ! iso_has "$(choice_of VARIANT)"; then
    require 1 "there is no internet; nixos-install has to download packages (step 1)." || return 2
  fi
  require 4 "the settings have not been made yet (step 4)." || return 2
  dry_without_config install-system.sh && return 0
  MNT="$MNT" bash "$(script_in_cfg install-system.sh)" --no-reboot "${DRY[@]}"
}

step_6() {
  if ! st_installed && (( ! DRY_RUN )); then
    echo "${Y}Note:${N} nothing has been installed yet. After a reboot you start over."
    ask_yes "Reboot anyway?" n || return 2
  else
    echo "Remove the USB stick as soon as the screen goes black."
    if [[ -e /dev/mapper/cryptroot ]]; then
      echo "During boot the computer will first ask for the disk passphrase."
    fi
    ask_yes "Reboot now?" y || { echo "Not rebooted. You can do that later with step 6 or the reboot command."; return 2; }
  fi
  if (( DRY_RUN )); then echo "+ reboot"; else reboot; fi
}

# Info (key i): the versions of the installed system, or what is going to be installed.
show_info() {
  clear_screen
  echo "${C}${B}── Info ──${N}"
  echo
  if st_installed; then
    bash "$(script_in_cfg versions.sh)" --root "$MNT" || echo "${R}The versions could not be read.${N}"
  else
    echo "Nothing has been installed yet; after step 5 this shows the versions of the installed system."
    if st_config; then
      echo
      echo "What is going to be installed (from $CFG):"
      echo "  User:           $(var_of username)"
      if st_choice; then
        local h="$CFG/hosts/$(choice_of VARIANT)/default.nix" d a
        d="$(sed -n 's/^[[:space:]]*my.desktop[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' "$h" 2>/dev/null)"
        a="$(sed -n 's/^[[:space:]]*my.desktopApps[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' "$h" 2>/dev/null)"
        [[ -n "$d" ]] || { d="$(choice_of DESKTOP)"; a="$(choice_of APPS)"; }
        echo "  Machine name:   $(choice_of MACHINE_NAME) (only on this machine)"
        echo "  Config:         $(choice_of VARIANT)"
        echo "  Desktop:        $(desk_name "$d") ($a)"
      else
        echo "  Config:         not chosen yet (step 4)"
      fi
      echo "  NixOS release:  $(release_of)"
      echo "  Always:         Firefox, Google Chrome, Brave, Bitwarden, VLC"
    fi
    if from_iso; then
      echo
      echo "This ISO has everything for offline installation of: $(paste -sd' ' "$ISO_MARKER")"
    fi
  fi
  return 0
}

# Runs a step. Ctrl+C stops only the step, not the menu.
run_step() {
  local n="$1" rc=0
  set_dry
  clear_screen
  echo "${C}${B}── Step $n: ${TITLES[$n]} ──${N}"
  echo
  trap 'echo; echo "Interrupted (Ctrl+C)."' INT
  "step_$n" || rc=$?
  trap - INT
  echo
  if (( rc == 0 )); then
    echo "${G}✔ Step $n is done.${N}"
    (( DRY_RUN )) && DONE[$n]=1
  elif (( rc == 2 )); then
    echo "${Y}– Step $n was skipped.${N}"
  else
    echo "${R}✘ Step $n failed or was aborted.${N} Read the messages above; you can choose the step again."
  fi
  return "$rc"
}

run_all() {
  local n
  while true; do
    refresh
    n="$(next_step)"
    if [[ "$n" == 6 ]]; then
      run_step 6 || true
      return 0
    fi
    run_step "$n" || return 0
    echo
    echo "${D}On to the next step ...${N}"
    sleep 2
  done
}

##### Main loop #####

refresh
offer_tools
refresh
while true; do
  draw
  prompt "Choice: "
  case "$REPLY" in
    "")   run_step "$(next_step)" || true; pause; refresh ;;
    [1-6]) run_step "$REPLY" || true; pause; refresh ;;
    a|A)
      echo "All remaining steps will run one after another; it stops at the first error."
      if ask_yes "Start?" y; then run_all; pause; fi
      refresh ;;
    d|D)
      if (( DRY_RUN && EUID != 0 )); then
        echo "A real installation requires root. Quit the menu (q) and start it again without --dry-run;"
        echo "it will then ask for root privileges itself (sudo)."
        pause
      else
        DRY_RUN=$(( ! DRY_RUN )); DONE=()
      fi ;;
    i|I) show_info; pause ;;
    r|R) refresh ;;
    t|T) offer_tools; refresh ;;
    q|Q)  echo "Stopped. Continue later? Run again: bash $SELF_REPO/install.sh"; exit 0 ;;
    *)    ;;
  esac
done
