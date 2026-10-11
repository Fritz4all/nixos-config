#!/usr/bin/env bash
# Builds an installer ISO from what is on GitHub, with a menu in the same style as the installer.
# Run it on your own computer (e.g. Ubuntu) as yourself, not in the NixOS installer.
#
#   1. ISO with all configs           every config in hosts/, all installable without internet
#   2. ISO for chosen configs         choose one or more configs (or all variants of one machine type)
#   3. Generic ISO                    only the installer and the config, for new machine types (needs internet)
#   4. Test an ISO in a VM            starts it in virt-manager WITHOUT network: is it really offline?
#   5. Write an ISO to a USB stick    only USB sticks are offered; you confirm by typing the name
#   i  Info                           Nix, free space, the ISOs you built (and removing old ones)
#
# The ISO always contains exactly what is on GitHub (main): the repo is downloaded fresh before each build,
# and local changes that are not pushed are NOT on it (you get a warning). The installer on the ISO starts by
# itself; on a computer of a type that is on the ISO it offers those configs and installs them offline.
# ISOs with Google Chrome are for your own use only: Chrome's license does not allow sharing them.
#
# Usage: bash build-iso.sh [--dry-run] [--source DIR]
#   --dry-run     only show what would happen (can also be toggled in the menu)
#   --source DIR  build from this directory instead of GitHub (for testing)
# Where things go: ISOs in ~/ISOs (ISO_DIR), work files in ~/.cache/nixos-config-iso (ISO_WORK).
set -euo pipefail

SELF_REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ORIG_ARGS=("$@")
DRY_RUN=0
SOURCE=""
OUT="${ISO_DIR:-$HOME/ISOs}"
WORK="${ISO_WORK:-${XDG_CACHE_HOME:-$HOME/.cache}/nixos-config-iso}"
VM_NAME="nixos-iso-test"

die()   { echo "ERROR: $*" >&2; exit 1; }
usage() { sed -n '2,/^set -/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    --source)  SOURCE="$(cd "${2:?--source needs a directory}" && pwd)"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *)         die "Unknown option: $1" ;;
  esac
done
(( EUID == 0 )) && die "Run this as yourself, not as root (it asks for sudo itself where needed)."

##### Styling and questions (same as install.sh) #####

if [[ -t 1 && "${TERM:-dumb}" != dumb ]]; then
  B=$'\e[1m'; D=$'\e[2m'; G=$'\e[32m'; Y=$'\e[33m'; R=$'\e[31m'; C=$'\e[36m'; N=$'\e[0m'
  clear_screen() { printf '\e[H\e[2J'; }
else
  B=""; D=""; G=""; Y=""; R=""; C=""; N=""
  clear_screen() { echo; }
fi
prompt() { read -rp "$1" REPLY || { echo; echo "No more input received; stopped."; exit 0; }; }
ask_yes() {  # ask_yes "question" y|n
  local hint="[y/N]"; [[ "$2" == y ]] && hint="[Y/n]"
  prompt "$1 $hint: "
  case "$REPLY" in [yYjJ]*) return 0 ;; [nN]*) return 1 ;; *) [[ "$2" == y ]] ;; esac
}
pause() { echo; prompt "${D}Enter = back to the menu${N} "; }
run() { if (( DRY_RUN )); then printf '+ '; printf '%q ' "$@"; echo; else "$@"; fi; }
desk_name() { case "$1" in gnome) echo "GNOME" ;; plasma) echo "KDE Plasma" ;; *) echo "$1" ;; esac; }

##### Nix #####

NIX=()
find_nix() {
  NIX=()
  if [[ -n "${NIX_PORTABLE:-}" && -x "${NIX_PORTABLE:-}" ]]; then
    NIX=("$NIX_PORTABLE" nix --extra-experimental-features 'nix-command flakes')
  elif command -v nix >/dev/null 2>&1; then
    NIX=(nix --extra-experimental-features 'nix-command flakes')
  elif [[ -x "${NIX_DEFAULT_BIN:-/nix/var/nix/profiles/default/bin/nix}" ]]; then
    NIX=("${NIX_DEFAULT_BIN:-/nix/var/nix/profiles/default/bin/nix}" --extra-experimental-features 'nix-command flakes')
  fi
  (( ${#NIX[@]} ))
}
nix_version() { find_nix && "${NIX[@]}" --version 2>/dev/null | awk '{print $NF}' || true; }

# Asks whether Nix may be installed (the official installer from nixos.org, multi-user, needs sudo)
offer_nix() {
  find_nix && return 0
  echo "${Y}Nix is not installed.${N} It is needed to build an ISO."
  echo "The official installer from nixos.org installs it for all users (it asks for your sudo password)."
  ask_yes "Install Nix now?" y || { echo "Not installed."; return 1; }
  if (( DRY_RUN )); then echo "+ sh <(curl -L https://nixos.org/nix/install) --daemon"; return 1; fi
  sh <(curl --proto '=https' --tlsv1.2 -L https://nixos.org/nix/install) --daemon || { echo "${R}Installing Nix failed.${N}"; return 1; }
  # shellcheck disable=SC1091
  [[ -f /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]] && . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
  find_nix
}

##### The source: what is on GitHub #####

repo_url() { sed -n 's/^[[:space:]]*repoUrl[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' "$SELF_REPO/vars.nix" | head -n 1; }
SRC="$WORK/src"          # git clone of GitHub main (kept between runs)
BUILD_SRC="$WORK/build"  # clean copy without .git, with flake.lock: what goes on the ISO
SRC_REV=""

# Fetches GitHub main into $SRC and makes $BUILD_SRC from it. Exit code != 0 when that fails.
sync_source() {
  local url
  mkdir -p "$WORK"
  if [[ -n "$SOURCE" ]]; then
    rm -rf "$BUILD_SRC"; mkdir -p "$BUILD_SRC"
    cp -a "$SOURCE/." "$BUILD_SRC/"; rm -rf "$BUILD_SRC/.git"
    SRC_REV="local directory $SOURCE"
  else
    url="$(repo_url)"; [[ -n "$url" ]] || { echo "${R}repoUrl in vars.nix is empty.${N}"; return 1; }
    if [[ -d "$SRC/.git" ]]; then
      git -C "$SRC" fetch -q --depth 1 origin main && git -C "$SRC" reset -q --hard origin/main && git -C "$SRC" clean -qfdx \
        || { echo "${R}Fetching $url failed.${N}"; return 1; }
    else
      rm -rf "$SRC"
      git clone -q --depth 1 "$url" "$SRC" || { echo "${R}Downloading $url failed.${N}"; return 1; }
    fi
    rm -rf "$BUILD_SRC"; mkdir -p "$BUILD_SRC"
    git -C "$SRC" archive HEAD | tar -x -C "$BUILD_SRC"
    SRC_REV="$(git -C "$SRC" log -1 --format='%h %s' | cut -c1-60)"
  fi
  # Pin the versions: GitHub's flake.lock if there is one, otherwise the newest of the release (now)
  if ! [[ -f "$BUILD_SRC/flake.lock" ]]; then
    find_nix && (cd "$BUILD_SRC" && "${NIX[@]}" flake lock >/dev/null 2>&1) || true
  fi
  return 0
}

configs() { bash "$SELF_REPO/scripts/hosts-overview.sh" --list --dir "$BUILD_SRC" 2>/dev/null || true; }
release_of() { sed -n 's/.*inputs\.nixpkgs\.url.*nixos-\([^"]*\)".*/\1/p' "$BUILD_SRC/flake.nix" 2>/dev/null | head -n 1; }

# Local repo behind GitHub? Then offer to update it (git pull) and restart this script, so you always use the
# newest build-iso.sh. (The ISO itself is always built from GitHub.)
offer_local_update() {
  [[ -z "$SOURCE" && -z "${BUILD_ISO_UPDATED:-}" ]] || return 0
  git -C "$SELF_REPO" rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 0
  git -C "$SELF_REPO" fetch -q origin main 2>/dev/null || return 0
  local behind
  behind="$(git -C "$SELF_REPO" rev-list --count HEAD..origin/main 2>/dev/null || echo 0)"
  (( behind > 0 )) || return 0
  echo
  echo "${Y}Your local repo is $behind commit(s) behind GitHub.${N}"
  ask_yes "Update it now (git pull)?" y || { echo "Not updated."; return 0; }
  if (( DRY_RUN )); then echo "+ git -C $SELF_REPO pull --ff-only"; return 0; fi
  if git -C "$SELF_REPO" pull -q --ff-only; then
    echo "Updated. Starting the newest build-iso.sh ..."
    BUILD_ISO_UPDATED=1 exec bash "$SELF_REPO/build-iso.sh" "${ORIG_ARGS[@]}"
  else
    echo "${R}Updating failed${N} (local changes that conflict?). Update by hand: cd $SELF_REPO && git pull"
  fi
}

# Local repo: changes that are not on GitHub yet (they will not be on the ISO)
local_state() {
  [[ -z "$SOURCE" ]] || { echo "building from $SOURCE"; return 0; }
  git -C "$SELF_REPO" rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "not a git repo"; return 0; }
  local dirty ahead
  dirty="$(git -C "$SELF_REPO" status --porcelain 2>/dev/null | grep -vc '^??' || true)"
  ahead="$(git -C "$SELF_REPO" rev-list --count '@{u}..HEAD' 2>/dev/null || echo 0)"
  if (( dirty + ahead == 0 )); then echo "${G}everything is on GitHub${N}"
  else echo "${Y}$dirty changed file(s), $ahead commit(s) not pushed – not on the ISO!${N}"; fi
}

##### Building #####

iso_expr() {  # iso_expr <label> <variant...>
  local label="$1" v list=""; shift
  for v in "$@"; do list+=" \"$v\""; done
  echo "((builtins.getFlake \"path:$BUILD_SRC\").lib.mkIso { variants = [$list ]; label = \"$label\"; }).config.system.build.isoImage"
}

license_warning() {  # license_warning <variant...>
  (( $# )) || return 0
  if grep -q 'google-chrome' "$BUILD_SRC/modules/apps.nix" 2>/dev/null; then
    echo "${Y}Note:${N} this ISO contains Google Chrome (unfree). Chrome's license does not allow sharing it:"
    echo "      keep this ISO for your own use (do not put it on GitHub or a public website)."
  fi
}

build_iso() {  # build_iso <label> <variant...>
  local label="$1" expr est link iso name rel; shift
  find_nix || { offer_nix || return 1; }
  rel="$(release_of)"
  echo
  echo "Building an ISO \"$label\" from GitHub (${SRC_REV:-?}), NixOS ${rel:-?}"
  if (( $# )); then echo "Configs on it (installable offline): $*"; else echo "Generic: only the installer and the config (installing needs internet)."; fi
  license_warning "$@"
  if (( $# )) && grep -q 'username = "changeme"' "$BUILD_SRC/vars.nix" 2>/dev/null; then
    echo "${Y}Note:${N} the username in vars.nix on GitHub is still 'changeme'. The software on the ISO is made for"
    echo "      that name, so an offline installation only works with username 'changeme'. Save your first"
    echo "      installation to GitHub first (README 2.5), or set username in vars.nix and push it."
  fi
  expr="$(iso_expr "$label" "$@")"

  echo
  echo "Estimating the size ..."
  est="$("${NIX[@]}" build --impure --dry-run --expr "$expr" 2>&1 | grep -E 'will be (fetched|built)' || true)"
  if [[ -n "$est" ]]; then sed 's/^/  /' <<<"$est"; else echo "  (everything is already there)"; fi
  echo "  The ISO itself is roughly half of the unpacked size; you need about twice that free space."
  echo "  Free space: $(df -h --output=avail "$HOME" | tail -1 | tr -d ' ') in your home folder."
  ask_yes "Build it now? (this can take 20 to 40 minutes)" y || return 2

  mkdir -p "$OUT"
  link="$WORK/result-$label"
  if (( DRY_RUN )); then echo "+ nix build --impure --expr '$expr' -o $link"; return 0; fi
  "${NIX[@]}" build --impure --expr "$expr" -o "$link" || { echo "${R}Building the ISO failed.${N} Read the messages above."; return 1; }
  iso="$(find -L "$link/iso" -name '*.iso' | head -n 1)"
  [[ -n "$iso" ]] || { echo "${R}No ISO file found in the build result.${N}"; return 1; }
  name="nixos-config-$label-${rel:-x}-$(date +%Y%m%d).iso"
  cp -f "$iso" "$OUT/$name"
  chmod 644 "$OUT/$name"
  (cd "$OUT" && sha256sum "$name" > "$name.sha256")
  rm -f "$link"   # the copy in ~/ISOs is what counts; nix-collect-garbage frees the build
  echo
  echo "${G}Done:${N} $OUT/$name ($(du -h "$OUT/$name" | cut -f1))"
  echo "Checksum: $OUT/$name.sha256"
  echo "Next: test it in a VM (menu 4) or write it to a USB stick (menu 5)."
}

# Menu 2: list the configs grouped by machine type; choose one or more, or all variants of one type
choose_config() {
  local -a lines; mapfile -t lines < <(configs)
  (( ${#lines[@]} )) || { echo "There are no configs on GitHub yet. Install a machine and save it to GitHub first (README 2.5)."; return 2; }
  local -a types=() chosen=() i t prev="" v ven mod kind desk apps enc tok a b n
  echo
  for i in "${!lines[@]}"; do
    IFS='|' read -r v ven mod kind desk apps enc <<<"${lines[$i]}"
    t="$ven $mod"
    if [[ "$t" != "$prev" ]]; then echo "  ${B}$t${N} ${D}($kind)${N}"; prev="$t"; types+=("$t"); fi
    printf '    %d) %-46s %s\n' "$((i + 1))" "$v" "$(desk_name "$desk") ($apps)$([[ "$enc" == true ]] && echo ", encrypted")"
  done
  echo
  echo "  One or more numbers, e.g. 2  or  1 3  or  1-3 (each config on the ISO installs offline)"
  echo "  a = all configs of one machine type"
  prompt "Choose (Enter = back): "
  [[ -n "$REPLY" ]] || return 2
  if [[ "$REPLY" == a || "$REPLY" == A ]]; then
    for i in "${!types[@]}"; do printf '  %d) %s\n' "$((i + 1))" "${types[$i]}"; done
    prompt "Which machine type? "
    [[ "$REPLY" =~ ^[0-9]+$ ]] && (( REPLY >= 1 && REPLY <= ${#types[@]} )) || { echo "Invalid choice."; return 2; }
    t="${types[$((REPLY - 1))]}"
    for i in "${!lines[@]}"; do
      IFS='|' read -r v ven mod _ <<<"${lines[$i]}"
      [[ "$ven $mod" == "$t" ]] && chosen+=("$v")
    done
    build_iso "$(tr '[:upper:] ' '[:lower:]-' <<<"$t" | tr -cd 'a-z0-9-')" "${chosen[@]}"
    return
  fi
  # Numbers, separated by spaces or commas, and ranges like 1-3
  for tok in ${REPLY//,/ }; do
    if [[ "$tok" =~ ^([0-9]+)-([0-9]+)$ ]]; then a="${BASH_REMATCH[1]}"; b="${BASH_REMATCH[2]}"
    elif [[ "$tok" =~ ^[0-9]+$ ]]; then a="$tok"; b="$tok"
    else echo "Invalid choice: $tok"; return 2; fi
    for (( n = a; n <= b; n++ )); do
      (( n >= 1 && n <= ${#lines[@]} )) || { echo "There is no config $n."; return 2; }
      v="$(cut -d'|' -f1 <<<"${lines[$((n - 1))]}")"
      [[ " ${chosen[*]} " == *" $v "* ]] || chosen+=("$v")
    done
  done
  (( ${#chosen[@]} )) || { echo "Nothing chosen."; return 2; }
  if (( ${#chosen[@]} == 1 )); then build_iso "${chosen[0]}" "${chosen[0]}"
  else build_iso "${#chosen[@]}-configs" "${chosen[@]}"; fi
}

build_generic() { build_iso generic; }

build_all() {
  local -a vs; mapfile -t vs < <(configs | cut -d'|' -f1)
  (( ${#vs[@]} )) || { echo "There are no configs on GitHub yet. Install a machine and save it to GitHub first (README 2.5)."; return 2; }
  build_iso all "${vs[@]}"
}

##### Choosing an existing ISO #####

ISOS=()
list_isos() { ISOS=(); [[ -d "$OUT" ]] && mapfile -t ISOS < <(ls -1t "$OUT"/*.iso 2>/dev/null); return 0; }
choose_iso() {  # sets CHOSEN_ISO
  local i
  CHOSEN_ISO=""
  list_isos
  (( ${#ISOS[@]} )) || { echo "There are no ISOs in $OUT yet. Build one first (menu 1, 2 or 3)."; return 2; }
  for i in "${!ISOS[@]}"; do printf '  %d) %-60s %s\n' "$((i + 1))" "$(basename "${ISOS[$i]}")" "$(du -h "${ISOS[$i]}" | cut -f1)"; done
  prompt "Which ISO? [1]: "
  REPLY="${REPLY:-1}"
  [[ "$REPLY" =~ ^[0-9]+$ ]] && (( REPLY >= 1 && REPLY <= ${#ISOS[@]} )) || { echo "Invalid choice."; return 2; }
  CHOSEN_ISO="${ISOS[$((REPLY - 1))]}"
}

##### Menu 4: test in a VM without network #####

test_in_vm() {
  command -v virsh >/dev/null 2>&1 || { echo "virt-manager is not installed (sudo apt install virt-manager)."; return 1; }
  choose_iso || return $?
  local vmdir="$WORK/vm" c="qemu:///session"
  echo
  echo "The VM \"$VM_NAME\" gets an empty 40 GB disk, the ISO as a USB stick and NO network,"
  echo "so you see whether the installation really works offline. An existing \"$VM_NAME\" is replaced."
  ask_yes "Start it?" y || return 2
  if (( DRY_RUN )); then echo "+ virsh define + start $VM_NAME with $CHOSEN_ISO (no network)"; return 0; fi
  mkdir -p "$vmdir"
  virsh -c "$c" destroy "$VM_NAME" >/dev/null 2>&1 || true
  virsh -c "$c" undefine "$VM_NAME" --nvram >/dev/null 2>&1 || true
  [[ -e "$vmdir/disk.qcow2" ]] && { gio trash "$vmdir/disk.qcow2" 2>/dev/null || rm -f "$vmdir/disk.qcow2"; }
  qemu-img create -q -f qcow2 "$vmdir/disk.qcow2" 40G
  virsh -c "$c" define /dev/stdin >/dev/null <<XML
<domain type='kvm'>
  <name>$VM_NAME</name>
  <title>NixOS ISO test (offline)</title>
  <memory unit='GiB'>8</memory>
  <vcpu>4</vcpu>
  <os>
    <type arch='x86_64' machine='q35'>hvm</type>
    <loader readonly='yes' type='pflash' format='raw'>/usr/share/OVMF/OVMF_CODE_4M.fd</loader>
    <nvram template='/usr/share/OVMF/OVMF_VARS_4M.fd' format='raw'>$vmdir/VARS.fd</nvram>
  </os>
  <features><acpi/><apic/></features>
  <cpu mode='host-passthrough'/>
  <devices>
    <disk type='file' device='disk'>
      <driver name='qemu' type='qcow2'/><source file='$vmdir/disk.qcow2'/>
      <target dev='vda' bus='virtio'/><boot order='1'/>
    </disk>
    <disk type='file' device='disk'>
      <driver name='qemu' type='raw'/><source file='$CHOSEN_ISO'/>
      <target dev='sda' bus='usb' removable='on'/><readonly/><boot order='2'/>
    </disk>
    <controller type='usb' model='qemu-xhci'/>
    <graphics type='spice' autoport='yes'/>
    <channel type='spicevmc'><target type='virtio' name='com.redhat.spice.0'/></channel>
    <video><model type='virtio'/></video>
    <input type='tablet' bus='usb'/>
  </devices>
</domain>
XML
  virsh -c "$c" start "$VM_NAME" >/dev/null
  (setsid nohup virt-manager --connect "$c" --show-domain-console "$VM_NAME" >/dev/null 2>&1 &)
  echo "${G}The VM is running${N} (window \"$VM_NAME\" in virt-manager). The installer starts by itself."
}

##### Menu 5: write to a USB stick #####

write_usb() {
  choose_iso || return $?
  local -a sticks=() i dev
  mapfile -t sticks < <(lsblk -dnpo NAME,TRAN,HOTPLUG,SIZE,MODEL 2>/dev/null | awk '$2=="usb" || $3=="1"')
  (( ${#sticks[@]} )) || { echo "No USB stick found. Plug one in and choose this again."; return 2; }
  echo
  echo "USB sticks (internal disks are never shown):"
  for i in "${!sticks[@]}"; do
    printf '  %d) %s\n' "$((i + 1))" "$(awk '{d=$1; s=$4; $1=$2=$3=$4=""; sub(/^ +/,""); printf "%-12s %-8s %s", d, s, $0}' <<<"${sticks[$i]}")"
  done
  prompt "Which stick? (Enter = back): "
  [[ -n "$REPLY" ]] || return 2
  [[ "$REPLY" =~ ^[0-9]+$ ]] && (( REPLY >= 1 && REPLY <= ${#sticks[@]} )) || { echo "Invalid choice."; return 2; }
  dev="$(awk '{print $1}' <<<"${sticks[$((REPLY - 1))]}")"
  echo
  echo "${R}EVERYTHING on $dev will be erased${N} and replaced by $(basename "$CHOSEN_ISO")."
  prompt "Type '$dev' to confirm: "
  [[ "$REPLY" == "$dev" ]] || { echo "Not confirmed, nothing was written."; return 2; }
  while read -r part; do
    [[ -n "$part" ]] && run udisksctl unmount -b "$part" >/dev/null 2>&1 || true
  done < <(lsblk -nlpo NAME "$dev" | tail -n +2)
  echo "Writing (this asks for your sudo password and takes a few minutes) ..."
  run sudo dd if="$CHOSEN_ISO" of="$dev" bs=4M status=progress conv=fsync oflag=direct || { echo "${R}Writing failed.${N}"; return 1; }
  run sync
  echo "${G}Done.${N} Eject the stick, then start the computer from it (see README 2.1 for the boot menu keys)."
}

##### Info #####

show_info() {
  clear_screen
  echo "${C}${B}── Info ──${N}"
  echo
  echo "  Nix:          $(nix_version || true)${D}$(find_nix || echo " (not installed)")${N}"
  echo "  ISOs in:      $OUT"
  echo "  Work files:   $WORK"
  echo "  Free space:   $(df -h --output=avail "$HOME" | tail -1 | tr -d ' ')"
  echo
  list_isos
  if (( ${#ISOS[@]} )); then
    echo "  ISOs you built (newest first):"
    local i; for i in "${!ISOS[@]}"; do printf '    %d) %-60s %6s  %s\n' "$((i + 1))" "$(basename "${ISOS[$i]}")" "$(du -h "${ISOS[$i]}" | cut -f1)" "$(date -r "${ISOS[$i]}" +%Y-%m-%d)"; done
    echo
    prompt "Type a number to move that ISO to the trash, or Enter to go back: "
    if [[ "$REPLY" =~ ^[0-9]+$ ]] && (( REPLY >= 1 && REPLY <= ${#ISOS[@]} )); then
      local f="${ISOS[$((REPLY - 1))]}"
      run gio trash "$f" "$f.sha256" 2>/dev/null || run rm -f "$f" "$f.sha256"
      echo "Moved to the trash: $(basename "$f")"
    fi
  else
    echo "  No ISOs built yet."
  fi
  return 0
}

##### Menu #####

STATE_SRC=""
refresh() {
  if sync_source >/dev/null 2>&1; then STATE_SRC="ok"; else STATE_SRC="failed"; fi
  return 0
}

draw() {
  local n
  n="$(configs | grep -c . || true)"
  clear_screen
  echo "${C}╭────────────────────────────────────────────────────────────╮${N}"
  echo "${C}│${N}${B}               Build an ISO  ·  nixos-config                ${N}${C}│${N}"
  echo "${C}╰────────────────────────────────────────────────────────────╯${N}"
  printf '  %-11s %s\n' "Nix" "$(if find_nix; then echo "$(nix_version)"; else echo "${Y}not installed${N} ${D}(asked when building)${N}"; fi)"
  if [[ "$STATE_SRC" == ok ]]; then
    printf '  %-11s %s\n' "GitHub" "main @ $SRC_REV ${D}($n configs, NixOS $(release_of))${N}"
  else
    printf '  %-11s %s\n' "GitHub" "${R}could not be downloaded${N} ${D}(internet? repoUrl in vars.nix?)${N}"
  fi
  printf '  %-11s %s\n' "Local repo" "$(local_state)"
  printf '  %-11s %s\n' "Free space" "$(df -h --output=avail "$HOME" | tail -1 | tr -d ' ') ${D}(ISOs go to $OUT)${N}"
  (( DRY_RUN )) && printf '  %-11s %s\n' "Mode" "${Y}DRY RUN${N} – nothing will be built or written"
  echo
  echo "     ${B}1${N}  ISO with all configs ($n)        every config, installable offline"
  echo "     ${B}2${N}  ISO for chosen configs           one or more configs, or a machine type"
  echo "     ${B}3${N}  Generic ISO                      installer + config, for new machine types"
  echo "     ${B}4${N}  Test an ISO in a VM              without network: is it really offline?"
  echo "     ${B}5${N}  Write an ISO to a USB stick"
  echo
  echo "  ${B}1-5${N} = choose   ${B}i${N} = info   ${B}d${N} = dry run $( (( DRY_RUN )) && echo off || echo on)   ${B}r${N} = refresh   ${B}q${N} = quit"
  echo
}

do_step() {  # do_step <function> <title>
  clear_screen
  echo "${C}${B}── $2 ──${N}"
  [[ "$STATE_SRC" == ok || "$1" == test_in_vm || "$1" == write_usb ]] \
    || { echo "${R}The config could not be downloaded from GitHub.${N} Check the internet connection and press r."; return 1; }
  "$1" || true
  return 0
}

offer_local_update
echo "Downloading the config from GitHub ..."
refresh
while true; do
  draw
  prompt "Choice: "
  case "$REPLY" in
    1) do_step build_all "ISO with all configs"; pause ;;
    2) do_step choose_config "ISO for chosen configs"; pause ;;
    3) do_step build_generic "Generic ISO"; pause ;;
    4) do_step test_in_vm "Test an ISO in a VM"; pause ;;
    5) do_step write_usb "Write an ISO to a USB stick"; pause ;;
    i|I) show_info; pause ;;
    d|D) DRY_RUN=$(( ! DRY_RUN )) ;;
    r|R) echo "Downloading the config from GitHub ..."; refresh ;;
    q|Q) exit 0 ;;
    *) ;;
  esac
done
