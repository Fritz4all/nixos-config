#!/usr/bin/env bash
# Tests the installation scripts without touching any disk: all installer commands
# (lsblk, parted, nixos-install, ...) are replaced by the fake versions in dev/stubs/.
# Works on any Linux machine; NixOS is not needed.
#
# Usage: bash dev/test-scripts.sh [-v]
#   -v   also print the full output of every scenario
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STUBS="$REPO/dev/stubs"
VERBOSE=0
[[ "${1:-}" == -v ]] && VERBOSE=1

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
PASS=0
FAIL=0

# Fresh copy of the repo and an empty "disk" for every scenario
setup() {
  rm -rf "$WORK/repo" "$WORK/mnt"
  cp -a "$REPO" "$WORK/repo"
  rm -rf "$WORK/repo/.git"
  mkdir -p "$WORK/mnt/boot"
}
mounted() { touch "$WORK/mnt/.mounted" "$WORK/mnt/boot/.mounted"; }
set_repo_url() { sed -i "s|repoUrl = \"[^\"]*\"|repoUrl = \"$1\"|" "$WORK/repo/vars.nix"; }

# run_menu <input lines...>  (environment variables are passed through)
run_menu() {
  local as_root=()
  [[ -n "${AS_ROOT:-}" ]] && as_root=(unshare -r)
  printf '%s\n' "$@" | PATH="$STUBS:$PATH" STUB_CLONE_SRC="$WORK/repo" \
    "${as_root[@]}" bash "$WORK/repo/scripts/menu.sh" ${DRY:+--dry-run} --root "$WORK/mnt" 2>&1 || true
}

expect() {  # expect <description> <output> <text that must appear>...
  local name="$1" out="$2" t ok=1
  shift 2
  for t in "$@"; do
    grep -qF -- "$t" <<<"$out" || { ok=0; echo "    missing: $t"; }
  done
  if (( ok )); then echo "PASS  $name"; PASS=$((PASS + 1)); else echo "FAIL  $name"; FAIL=$((FAIL + 1)); fi
  (( VERBOSE )) && sed 's/^/    | /' <<<"$out"
  return 0
}

if ! unshare -r true 2>/dev/null; then
  echo "Note: 'unshare -r' is not available; scenarios that need a fake root are skipped."
  NO_ROOT=1
fi

##### 1. Full installation with 'a' (config copied locally, repo not online) #####
if [[ -z "${NO_ROOT:-}" ]]; then
  setup; mounted
  out="$(AS_ROOT=1 run_menu a y "" "" roy "Roy Test" laptop "" n "" q)"
  expect "full installation (local config)" "$out" \
    "Chosen:     Local config" "Saved in" "nixos-install --flake" "Installation of 'laptop' is finished." \
    "installed (machine: laptop)" "▶  · 7  Reboot"
fi

##### 2. Full installation with the repo online (Download config) #####
if [[ -z "${NO_ROOT:-}" ]]; then
  setup; mounted; set_repo_url "https://github.com/example/nixos-config.git"
  out="$(AS_ROOT=1 STUB_REPO=0 run_menu a y "" roy "Roy Test" laptop "" n "" q)"
  expect "full installation (download config)" "$out" \
    "can be downloaded" "Chosen:     Download config" "Source: Download config" "installed (machine: laptop)"
fi

##### 3. Repo status in the menu #####
setup
out="$(DRY=1 run_menu q)"
expect "repo status: repoUrl empty" "$out" "not set (repoUrl in vars.nix)"
set_repo_url "https://github.com/example/nixos-config.git"
out="$(DRY=1 STUB_REPO=1 run_menu q)"
expect "repo status: not online yet" "$out" "cannot be downloaded"
out="$(DRY=1 STUB_REPO=0 run_menu q)"
expect "repo status: online" "$out" "can be downloaded"
out="$(DRY=1 STUB_OFFLINE=1 run_menu q)"
expect "repo status: no internet" "$out" "not checked (no internet)"

##### 4. Dry run without internet: Wi-Fi help, disk selection, warnings, skipping #####
setup
out="$(DRY=1 STUB_OFFLINE=1 run_menu a y "" "" 2 2 /dev/vda "" "" 4 "" 6 "" q)"
expect "dry run without internet" "$out" \
  "No internet connection." "+ nmtui connect" "in use (probably the USB stick)" \
  "Dry run finished: nothing was changed." "the config has not been fetched yet" "Step 6 was skipped."

##### 5. Real mode without root and without a mounted disk: scripts refuse #####
if [[ -z "${NO_ROOT:-}" ]]; then
  setup
  out="$(AS_ROOT=1 run_menu 5 y "" q)"
  expect "install refuses without config" "$out" "the user has not been set up yet" "Step 5 failed or was aborted."
fi

echo
echo "$PASS passed, $FAIL failed"
(( FAIL == 0 ))
