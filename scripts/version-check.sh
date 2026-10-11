# Compares the version of a copy of this config with the newest version on GitHub. Sourced by install.sh and
# build-iso.sh; defines functions only. A version is "<commit hash> <commit date>".
#
#   local_version DIR    version of the copy in DIR: from git when DIR is a git working copy, otherwise from the
#                        file VERSION (GitHub fills it in when the repo is downloaded as ZIP or tarball, and so
#                        does `git archive`, e.g. on an ISO); nothing when unknown
#   online_version URL   version of main on GitHub for repo URL (https://github.com/<owner>/<repo>[.git]);
#                        nothing when offline or unknown
#   is_newer A B         exit code 0 when version A is newer than version B (different commit, later date)
#   short_version V      "2026-10-11 (1a2b3c4)"
#   gh_repo URL          "<owner>/<repo>"

gh_repo() { sed -E 's#^https?://github\.com/##; s#\.git$##; s#/+$##' <<<"$1"; }

local_version() {
  local v
  if [[ -e "$1/.git" ]] && git -C "$1" rev-parse HEAD >/dev/null 2>&1; then
    git -C "$1" log -1 --format='%H %cI' 2>/dev/null || true
    return 0
  fi
  v="$(head -n 1 "$1/VERSION" 2>/dev/null || true)"
  [[ "$v" =~ ^[0-9a-f]{40}\ [0-9] ]] && echo "$v"
  return 0
}

online_version() {
  local repo json sha date
  repo="$(gh_repo "$1")"
  [[ "$1" == https://github.com/* && "$repo" =~ ^[^/]+/[^/]+$ ]] || return 0
  json="$(curl -fsS --max-time 8 "https://api.github.com/repos/$repo/commits/main" 2>/dev/null)" || return 0
  sha="$(grep -m1 -o '"sha": *"[0-9a-f]\{40\}"' <<<"$json" | grep -o '[0-9a-f]\{40\}' || true)"
  date="$(grep -o '"date": *"[^"]*"' <<<"$json" | sed -n '2p' | sed 's/.*"\([^"]*\)"$/\1/' || true)"   # committer date
  [[ -n "$sha" && -n "$date" ]] && echo "$sha $date"
  return 0
}

is_newer() {
  local a_sha="${1%% *}" a_date="${1#* }" b_sha="${2%% *}" b_date="${2#* }"
  [[ -n "$1" && -n "$2" && "$a_sha" != "$b_sha" ]] || return 1
  (( $(date -d "$a_date" +%s 2>/dev/null || echo 0) > $(date -d "$b_date" +%s 2>/dev/null || echo 0) ))
}

short_version() {
  [[ -n "$1" ]] || { echo "unknown"; return 0; }
  echo "$(date -d "${1#* }" +%Y-%m-%d 2>/dev/null || echo "${1#* }") (${1:0:7})"
}
