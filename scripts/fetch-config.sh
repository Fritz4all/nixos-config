#!/usr/bin/env bash
# Fetches the config and puts it in <root>/etc/nixos (default /mnt/etc/nixos).
#
#   Download config   git clone of your repo. Chosen when there is internet.
#   Local config      copy of a local directory or USB stick. Chosen when there is no internet.
#
# The script always tells you which of the two was chosen. You can override that choice
# (while the script runs, or up front with --download or --local).
#
# Usage: bash scripts/fetch-config.sh [options]
#   --download     force Download config
#   --local        force Local config
#   --url URL      Git URL for Download config
#                  (default: the 'origin' of this repo, else repoUrl in vars.nix; else the script asks)
#   --source DIR   directory with the config for Local config
#                  (default: this repo; otherwise the script searches USB sticks)
#   --root DIR     where the new system is mounted (default /mnt)
#   --yes          ask no questions, use the automatic choice
#   --dry-run      only show what would happen
set -euo pipefail

ORIG_ARGS=("$@")
SELF_REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MNT="/mnt"
FORCE=""            # download or local, when chosen up front
URL="${NIXOS_CONFIG_URL:-}"
SRC=""
ASSUME_YES=0
DRY_RUN=0

die()   { echo "ERROR: $*" >&2; exit 1; }
warn()  { echo "Warning: $*" >&2; }
usage() { sed -n '2,/^set -/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'; }

run() {
  if (( DRY_RUN )); then
    printf '+ '; printf '%q ' "$@"; echo
  else
    "$@"
  fi
}

soft_fail() {
  if (( DRY_RUN )); then warn "$1 (dry run, continuing)"; else die "$1"; fi
}

prompt() { read -rp "$1" REPLY || { echo; die "No more input received."; }; }

# ask_yes "question" y|n  -> exit code 0 for yes. With --yes the default answer is used.
ask_yes() {
  local def="$2" hint
  if (( ASSUME_YES )); then [[ "$def" == y ]]; return; fi
  if [[ "$def" == y ]]; then hint="[Y/n]"; else hint="[y/N]"; fi
  prompt "$1 $hint: "
  case "$REPLY" in
    [yYjJ]*) return 0 ;;
    [nN]*)   return 1 ;;
    *)       [[ "$def" == y ]] ;;
  esac
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --download) FORCE="download"; shift ;;
    --local)    FORCE="local"; shift ;;
    --url)      URL="${2:?--url needs a value}"; shift 2 ;;
    --source)   SRC="${2:?--source needs a value}"; shift 2 ;;
    --root)     MNT="${2:?--root needs a value}"; shift 2 ;;
    --yes|-y)   ASSUME_YES=1; shift ;;
    --dry-run)  DRY_RUN=1; shift ;;
    -h|--help)  usage; exit 0 ;;
    *)          die "Unknown option: $1" ;;
  esac
done

DEST="$MNT/etc/nixos"

(( EUID == 0 )) || soft_fail "Run this as root (type: sudo -i first)."
mountpoint -q "$MNT" 2>/dev/null || soft_fail "Nothing is mounted on $MNT. Run this first: bash scripts/prepare-disk.sh"

##### Helper functions #####

check_internet() {
  command -v curl >/dev/null 2>&1 || return 1
  curl -fsS --max-time 6 -o /dev/null https://cache.nixos.org/nix-cache-info >/dev/null 2>&1
}

# Makes sure git is available. If not, it asks whether git may be installed; if yes, the script
# restarts itself inside 'nix-shell -p git' (only for this session, nothing is installed permanently).
ensure_git() {
  command -v git >/dev/null 2>&1 && return 0
  [[ -z "${FETCH_CONFIG_REEXEC:-}" ]] && command -v nix-shell >/dev/null 2>&1 || return 1
  echo "git is needed to download the config, but it is not installed."
  ask_yes "Install git now (only for this session)?" y || return 1
  if (( DRY_RUN )); then echo "+ nix-shell -p git   (dry run: not installed)"; return 1; fi
  echo "Installing git ..."
  FETCH_CONFIG_REEXEC=1 exec nix-shell -p git --run "$(printf '%q ' bash "$0" "${ORIG_ARGS[@]}")"
}

# Order: --url / NIXOS_CONFIG_URL, the 'origin' of this repo, repoUrl in vars.nix.
detect_url() {
  [[ -n "$URL" ]] && return 0
  if command -v git >/dev/null 2>&1 && [[ -e "$SELF_REPO/.git" ]]; then
    URL="$(git -c safe.directory='*' -C "$SELF_REPO" remote get-url origin 2>/dev/null || true)"
  fi
  if [[ -z "$URL" && -f "$SELF_REPO/vars.nix" ]]; then
    URL="$(sed -n 's/^[[:space:]]*repoUrl[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' "$SELF_REPO/vars.nix" | head -n 1)"
  fi
  return 0
}

# Can the repo really be cloned? For http(s) URLs a quick check with curl is enough
# (works without git, e.g. for a public GitHub repo); otherwise git ls-remote.
repo_reachable() {
  case "$URL" in
    http://*|https://*)
      curl -fsS --max-time 10 -o /dev/null "${URL%/}/info/refs?service=git-upload-pack" >/dev/null 2>&1 && return 0 ;;
  esac
  command -v git >/dev/null 2>&1 || return 1
  GIT_TERMINAL_PROMPT=0 timeout 20 git ls-remote --exit-code "$URL" HEAD >/dev/null 2>&1
}

is_config_dir() {
  [[ -f "$1/flake.nix" && -f "$1/vars.nix" && -d "$1/hosts" && -d "$1/modules" ]]
}

CANDS=()
add_cand() {
  local real c
  is_config_dir "$1" || return 0
  real="$(realpath "$1")"
  [[ "$real" == "$(realpath -m "$DEST")" ]] && return 0
  for c in "${CANDS[@]}"; do [[ "$c" == "$real" ]] && return 0; done
  CANDS+=("$real")
}

find_local_sources() {
  local base f
  CANDS=()
  add_cand "$SELF_REPO"
  for base in /run/media /media /root /home; do
    [[ -d "$base" ]] || continue
    while IFS= read -r f; do
      add_cand "$(dirname "$f")"
    done < <(find "$base" -maxdepth 4 -name flake.nix -not -path '*/.git/*' -not -path '*/nix/store/*' 2>/dev/null)
  done
}

select_source() {
  local i
  if [[ -n "$SRC" ]]; then
    is_config_dir "$SRC" || die "'$SRC' is not a valid config directory (flake.nix, vars.nix, hosts/ and modules/ are missing)."
    SRC="$(realpath "$SRC")"
    return 0
  fi
  find_local_sources
  case ${#CANDS[@]} in
    0)
      (( ASSUME_YES )) && die "No local config found. Specify the directory with --source."
      echo "No local config found."
      echo "Is the config on a USB stick? Mount it first (e.g. by opening it in the file manager;"
      echo "it then appears under /run/media)."
      while true; do
        prompt "Type the path to the config directory (empty = quit): "
        [[ -n "$REPLY" ]] || { echo "Stopped, nothing was changed."; exit 0; }
        if is_config_dir "$REPLY"; then SRC="$(realpath "$REPLY")"; return 0; fi
        echo "That is not a valid config directory."
      done
      ;;
    1)
      SRC="${CANDS[0]}"
      ;;
    *)
      if (( ASSUME_YES )); then SRC="${CANDS[0]}"; return 0; fi
      echo "Several local configs found:"
      for i in "${!CANDS[@]}"; do printf '  %d) %s\n' "$((i + 1))" "${CANDS[$i]}"; done
      while true; do
        prompt "Which one to use? Type the number (Enter = 1): "
        [[ -n "$REPLY" ]] || REPLY=1
        if [[ "$REPLY" =~ ^[0-9]+$ ]] && (( REPLY >= 1 && REPLY <= ${#CANDS[@]} )); then
          SRC="${CANDS[$((REPLY - 1))]}"; return 0
        fi
        echo "Invalid choice."
      done
      ;;
  esac
}

# If the destination already exists, it is moved aside (after confirmation). Nothing is deleted.
prepare_dest() {
  local bak
  if [[ -e "$DEST" && -n "$(ls -A "$DEST" 2>/dev/null || true)" ]]; then
    bak="$DEST.bak-$(date +%H%M%S)"
    echo "There is already something in $DEST."
    if ask_yes "Move it to $bak and fetch the config again?" y; then
      run mv "$DEST" "$bak"
    else
      echo "Stopped, nothing was changed."
      exit 0
    fi
  fi
  run mkdir -p "$MNT/etc"
}

RESULT_LABEL=""
RESULT_FROM=""

do_local() {
  select_source
  RESULT_LABEL="Local config"
  RESULT_FROM="$SRC"
  if [[ "$(realpath -m "$SRC")" == "$(realpath -m "$DEST")" ]]; then
    echo "The config is already in $DEST; nothing needs to be copied."
    return 0
  fi
  prepare_dest
  echo "Copying $SRC to $DEST ..."
  run mkdir -p "$DEST"
  run cp -a --no-preserve=ownership "$SRC/." "$DEST/"
  if command -v git >/dev/null 2>&1; then
    [[ -e "$DEST/.git" ]] || run git -C "$DEST" init -q -b main
    run git -C "$DEST" add -A
    # Remember where the config lives online, so you can push to it after the installation
    if [[ -n "$URL" ]] && ! git -C "$DEST" remote get-url origin >/dev/null 2>&1; then
      run git -C "$DEST" remote add origin "$URL"
    fi
  else
    warn "git not found; the config was copied but not added to Git."
  fi
}

do_download() {
  if [[ -z "$URL" ]]; then
    (( ASSUME_YES )) && die "No repo URL known. Specify it with --url."
    prompt "Git URL of your config repo (empty = Local config): "
    if [[ -z "$REPLY" ]]; then
      echo "No URL given; switched to Local config."
      do_local
      return 0
    fi
    URL="$REPLY"
  fi
  if ! ensure_git; then
    echo "Without git the config cannot be downloaded; using Local config instead."
    do_local
    return 0
  fi
  RESULT_LABEL="Download config"
  RESULT_FROM="$URL"
  prepare_dest
  echo "Downloading $URL ..."
  if ! run git clone "$URL" "$DEST"; then
    echo "The download failed." >&2
    [[ -e "$DEST" ]] && run rm -rf "$DEST"
    if (( ! ASSUME_YES )) && ask_yes "Use Local config instead?" y; then
      do_local
      return 0
    fi
    die "Fetching the config failed."
  fi
}

# Turn on the secret check before commits (.githooks/pre-commit) in the new config.
enable_hooks() {
  command -v git >/dev/null 2>&1 || return 0
  [[ -d "$DEST/.githooks" || $DRY_RUN -eq 1 ]] || return 0
  run git -C "$DEST" config core.hooksPath .githooks || warn "Could not turn on the secret check (.githooks)."
}

label_of() { if [[ "$1" == download ]]; then echo "Download config"; else echo "Local config"; fi; }

##### Determine the choice #####

ONLINE=0
check_internet && ONLINE=1

if (( ONLINE )) && [[ "$FORCE" != local ]]; then ensure_git || true; fi
detect_url
if (( ONLINE )) && [[ -z "$URL" && -z "$FORCE" ]] && (( ! ASSUME_YES )); then
  echo "Internet found, but the repo URL is not set (repoUrl in vars.nix is empty)."
  prompt "Paste the Git URL of your config, or press Enter to use Local config: "
  URL="$REPLY"
fi

AUTO="local"
REASON=""
if (( ! ONLINE )); then
  REASON="no internet connection"
elif [[ -z "$URL" ]]; then
  REASON="there is internet, but the repo URL is not set (repoUrl in vars.nix)"
elif ! repo_reachable; then
  REASON="there is internet, but $URL cannot be downloaded (not online yet, private repo or wrong URL?)"
elif ! command -v git >/dev/null 2>&1; then
  REASON="there is internet, but git is missing"
else
  AUTO="download"
fi
MODE="${FORCE:-$AUTO}"

echo
echo "Internet:   $( (( ONLINE )) && echo yes || echo no )"
if [[ "$MODE" == download ]]; then
  echo "Chosen:     Download config   (from ${URL:-a URL still to be entered})"
else
  find_local_sources
  if (( ${#CANDS[@]} > 0 )); then
    echo "Chosen:     Local config      (from ${SRC:-${CANDS[0]}})"
  else
    echo "Chosen:     Local config      (you will be asked for the source)"
  fi
fi
if [[ -n "$FORCE" ]]; then
  echo "            (chosen up front with --$FORCE)"
elif [[ "$MODE" == local ]]; then
  echo "Reason:     $REASON"
fi

if [[ -z "$FORCE" ]] && (( ! ASSUME_YES )); then
  echo
  while true; do
    prompt "Enter = continue | 1 = Download config | 2 = Local config | q = quit: "
    case "$REPLY" in
      "") break ;;
      1)  MODE="download"; echo "Overridden: you chose Download config."; break ;;
      2)  MODE="local";    echo "Overridden: you chose Local config.";    break ;;
      q|Q) echo "Stopped, nothing was changed."; exit 0 ;;
      *)  echo "Invalid choice." ;;
    esac
  done
fi

echo
echo "Continuing with: $(label_of "$MODE")"

##### Execute #####

if [[ "$MODE" == download ]]; then do_download; else do_local; fi
enable_hooks

ROOTPREFIX=""
[[ "$MNT" == /mnt ]] || ROOTPREFIX="MNT=$MNT "

echo
if (( DRY_RUN )); then
  echo "Dry run finished: nothing was changed."
else
  echo "Done: the config is in $DEST"
  echo "Source: $RESULT_LABEL ($RESULT_FROM)"
fi
[[ -n "${INSTALL_MENU:-}" ]] && exit 0  # menu.sh shows the next step itself
cat <<EOF

Next step, set up the username (after that it continues with the installation):
  ${ROOTPREFIX}bash $DEST/scripts/setup-user.sh
EOF
