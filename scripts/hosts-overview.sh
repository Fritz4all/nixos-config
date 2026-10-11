#!/usr/bin/env bash
# Writes hosts/README.md: a table of all configs (machine types and variants) in hosts/, which GitHub shows
# when you open the hosts folder. Run by new-host.sh; can also be run by hand. Contains no machine names
# or serial numbers. With --list it prints one line per config instead (used by the installer and build-iso.sh):
#   <variant>|<vendor>|<model>|<kind>|<desktop>|<apps>|<encrypted>
#
# Usage: bash scripts/hosts-overview.sh [--list] [--dir REPO]
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIST=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --list) LIST=1; shift ;;
    --dir)  REPO="${2:?--dir needs a path}"; shift 2 ;;
    -h|--help) sed -n '2,/^set -/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

str_of()  { sed -n "s/.*\b$1[[:space:]]*=[[:space:]]*\"\([^\"]*\)\".*/\1/p" "$2" 2>/dev/null | head -n 1; }
bool_of() { sed -n "s/.*\b$1[[:space:]]*=[[:space:]]*\(true\|false\).*/\1/p" "$2" 2>/dev/null | head -n 1; }

lines=()
for d in "$REPO"/hosts/*/; do
  [[ -d "$d" ]] || continue
  v="$(basename "$d")"
  [[ "$v" == _* ]] && continue
  m="$d/machine.nix"; c="$d/default.nix"
  desk="$(str_of my.desktop "$c")"; apps="$(str_of my.desktopApps "$c")"; enc="$(bool_of my.disk.encrypted "$c")"
  lines+=("$v|$(str_of vendor "$m")|$(str_of model "$m")|$(str_of kind "$m")|${desk:-gnome}|${apps:-full}|${enc:-true}")
done

if (( LIST )); then
  (( ${#lines[@]} )) && printf '%s\n' "${lines[@]}"
  exit 0
fi

desk_name() { case "$1" in gnome) echo "GNOME" ;; plasma) echo "KDE Plasma" ;; *) echo "$1" ;; esac; }
{
  echo "# Machine types and variants"
  echo
  echo "Every directory here is a config for one machine type and variant, shared by all machines of that type."
  echo "The installer recognises the type by vendor and model. Machine names stay on the machines themselves."
  echo "This file is updated by \`scripts/new-host.sh\`."
  echo
  if (( ${#lines[@]} )); then
    echo "| Config | Vendor | Model | Kind | Desktop | Apps | Encrypted |"
    echo "|---|---|---|---|---|---|---|"
    for l in "${lines[@]}"; do
      IFS='|' read -r v ven mod kind desk apps enc <<<"$l"
      echo "| \`$v\` | $ven | $mod | $kind | $(desk_name "$desk") | $apps | $([[ "$enc" == true ]] && echo yes || echo no) |"
    done
  else
    echo "There are no configs yet; the first installation creates one."
  fi
} > "$REPO/hosts/README.md"
echo "Updated $REPO/hosts/README.md"
