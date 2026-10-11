# Machine information from the firmware (DMI), shared by settings.sh, new-host.sh and build-iso.sh.
# Source this file; it defines functions only. Reading the serial number needs root (the installer runs as root).
#
#   machine_vendor        e.g. "Lenovo", "Dell", "HP" (cleaned up)
#   machine_model         e.g. "ThinkPad T14 Gen 3" (Lenovo keeps the readable model in product_version)
#   machine_kind          Laptop, Desktop, Server, Tablet, Virtual machine or Computer
#   machine_serial        the serial number, or nothing when the firmware has no usable one
#   machine_type          type name for hosts/, e.g. "lenovo-thinkpad-t14-gen-3" (VMs: "vm-kvm")
#   suggest_machine_name  suggestion for the machine name: "nix-<serial>" (lowercase), or "nix-<id>" without one
#   slugify TEXT          lowercase, letters/digits/hyphens only
#
# For tests: DMI_DIR (default /sys/class/dmi/id) and MACHINE_ID_FILE (default /etc/machine-id).

DMI_DIR="${DMI_DIR:-/sys/class/dmi/id}"

dmi() { { tr -d '\0' < "$DMI_DIR/$1"; } 2>/dev/null | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' || true; }

# Values that firmware vendors fill in when there is no real value
dmi_placeholder() {
  local v
  v="$(tr '[:upper:]' '[:lower:]' <<<"$1")"
  case "$v" in
    ""|none|"not specified"|"not applicable"|"to be filled by o.e.m."|"to be filled by oem"|"default string"| \
    "system serial number"|"system product name"|"system version"|"system manufacturer"|"o.e.m."|"oem"| \
    "invalid"|"unknown"|"chassis serial number"|"0"|"00000000"|"0123456789"|"1234567890"|"123456789") return 0 ;;
  esac
  [[ "$v" =~ ^[0x\ ]+$ ]]   # only zeros or x's
}

slugify() {
  tr '[:upper:]' '[:lower:]' <<<"$1" | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//' | cut -c1-63 | sed 's/-$//'
}

machine_virt() { systemd-detect-virt --vm 2>/dev/null || true; }
machine_is_vm() { local v; v="$(machine_virt)"; [[ -n "$v" && "$v" != none ]]; }

machine_vendor() {
  if machine_is_vm; then echo "Virtual machine"; return 0; fi
  local v
  v="$(dmi sys_vendor)"
  dmi_placeholder "$v" && v="$(dmi board_vendor)"
  case "$(tr '[:upper:]' '[:lower:]' <<<"$v")" in
    lenovo*) echo "Lenovo" ;;
    "dell"*) echo "Dell" ;;
    hp|hewlett*|"hp inc"*) echo "HP" ;;
    asustek*|asus*) echo "ASUS" ;;
    acer*) echo "Acer" ;;
    "micro-star"*|msi*) echo "MSI" ;;
    "microsoft"*) echo "Microsoft" ;;
    framework*) echo "Framework" ;;
    "gigabyte"*) echo "Gigabyte" ;;
    "samsung"*) echo "Samsung" ;;
    "apple"*) echo "Apple" ;;
    "toshiba"*|dynabook*) echo "Dynabook" ;;
    "fujitsu"*) echo "Fujitsu" ;;
    *) dmi_placeholder "$v" && echo "Unknown" || sed -E 's/,? *(inc\.?|corporation|corp\.?|co\., ?ltd\.?|ltd\.?|gmbh|limited)$//I' <<<"$v" ;;
  esac
}

machine_model() {
  if machine_is_vm; then echo "$(machine_virt | tr '[:lower:]' '[:upper:]') virtual machine"; return 0; fi
  local name version
  name="$(dmi product_name)"
  version="$(dmi product_version)"
  # Lenovo: product_name is a type code such as 21AH00ABMH; the readable model is in product_version
  if [[ "$(machine_vendor)" == Lenovo ]] && ! dmi_placeholder "$version"; then
    echo "$version"
  elif ! dmi_placeholder "$name"; then
    echo "$name"
  else
    local board
    board="$(dmi board_name)"
    dmi_placeholder "$board" && echo "Unknown model" || echo "$board"
  fi
}

machine_kind() {
  if machine_is_vm; then echo "Virtual machine"; return 0; fi
  case "$(dmi chassis_type)" in
    8|9|10|14|31|32) echo "Laptop" ;;
    3|4|5|6|7|13|15|16|24|35|36) echo "Desktop" ;;
    17|23|28) echo "Server" ;;
    30) echo "Tablet" ;;
    *) echo "Computer" ;;
  esac
}

machine_serial() {
  local s
  s="$(dmi product_serial)"
  dmi_placeholder "$s" && s="$(dmi board_serial)"
  dmi_placeholder "$s" && s=""
  echo "$s"
  return 0
}

machine_type() {
  if machine_is_vm; then echo "vm-$(slugify "$(machine_virt)")"; return 0; fi
  local t
  t="$(slugify "$(machine_vendor) $(machine_model)")"
  echo "${t:-unknown-machine}"
}

suggest_machine_name() {
  local s id
  s="$(slugify "$(machine_serial)")"
  if [[ -n "$s" ]]; then
    echo "nix-$s" | cut -c1-63 | sed 's/-$//'
  else
    id="$(tr -dc 'a-f0-9' < "${MACHINE_ID_FILE:-/etc/machine-id}" 2>/dev/null | cut -c1-6)"
    echo "nix-${id:-$(date +%s | tail -c 7)}"
  fi
}
