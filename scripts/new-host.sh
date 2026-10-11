#!/usr/bin/env bash
# Creates a new config for a machine type and variant: hosts/<variant>/ with
#   default.nix                  desktop, apps, disk encryption, stateVersion (from hosts/_template)
#   machine.nix                  vendor, model and kind of this machine type (the installer recognises it by this)
#   hardware-configuration.nix   hardware detection without disks (modules/disk.nix finds them by name)
# In a virtual machine it also turns on the guest tools for that kind of VM (QEMU/KVM, VMware); NixOS's own
# hardware detection already handles VirtualBox, Hyper-V and Parallels.
# With a Logitech receiver or mouse attached it turns on Solaar with the button rules (my.logitech.enable).
# Video cards (nixos-generate-config does not look at them): Intel → video acceleration (my.intelGpu); NVIDIA → the
# NVIDIA driver (my.nvidia), with PRIME offload when there is also an Intel or AMD GPU (hybrid laptops).
# Also: fingerprint reader (my.fingerprint, ids in scripts/fingerprint-ids.txt), smartcard reader (pcscd), Thunderbolt
# (bolt), Intel laptops (thermald), sensors for rotation/brightness (iio), and the nixos-hardware profile of the model.
# For tests the hardware can be faked: DMI_DIR, USB_SYSFS, PCI_SYSFS, TB_SYSFS, IIO_SYSFS, CPUINFO, NIXOS_HARDWARE_LIST.
# Afterwards it updates the overview in hosts/README.md.
#
# With --update it refreshes an existing config instead: hardware-configuration.nix and machine.nix are made
# again, and in default.nix only the blocks marked "added by new-host.sh" are replaced by what is detected now;
# everything else (desktop, apps, encryption, stateVersion, your own settings) stays as it is.
#
# Usage: bash scripts/new-host.sh <variant> [options]
#   --root DIR          where the new system is mounted (default /mnt, as in the installer)
#   --desktop NAME      gnome or plasma (default: desktop in vars.nix)
#   --apps SET          full or minimal (default: desktopApps in vars.nix)
#   --encrypted yes|no  disk encryption (default: detected from the disk mounted on --root)
#   --update            refresh the existing config <variant> with the hardware of this machine
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT="/mnt"
NAME=""
DESKTOP=""
APPS=""
ENCRYPTED=""
UPDATE=0

die() { echo "ERROR: $*" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --root)      ROOT="${2:?--root needs a path}"; shift 2 ;;
    --desktop)   DESKTOP="${2:?--desktop needs gnome or plasma}"; shift 2 ;;
    --apps)      APPS="${2:?--apps needs full or minimal}"; shift 2 ;;
    --encrypted) ENCRYPTED="${2:?--encrypted needs yes or no}"; shift 2 ;;
    --update)    UPDATE=1; shift ;;
    -h|--help)   sed -n '2,/^set -/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*)          die "Unknown option: $1" ;;
    *)           NAME="$1"; shift ;;
  esac
done

[[ -n "$NAME" ]] || die "Usage: bash scripts/new-host.sh <variant> [--root /mnt] [--desktop gnome|plasma] [--apps full|minimal]"
[[ "$NAME" =~ ^[a-z][a-z0-9-]{0,62}$ ]] || die "Invalid name '$NAME': use lowercase letters, digits and hyphens, starting with a letter."
DEST="$REPO/hosts/$NAME"
if (( UPDATE )); then
  [[ -f "$DEST/default.nix" ]] || die "hosts/$NAME does not exist, so it cannot be updated."
else
  [[ -e "$DEST" ]] && die "hosts/$NAME already exists. Choose another name or remove that directory first."
fi

# shellcheck source=machine-info.sh
source "$REPO/scripts/machine-info.sh"

var_of() { sed -n "s/^[[:space:]]*$1[[:space:]]*=[[:space:]]*\"\([^\"]*\)\".*/\1/p" "$REPO/vars.nix" | head -n 1; }
nix_value() { sed -n "s/^[[:space:]]*$1[[:space:]]*=[[:space:]]*\"\{0,1\}\([^\";]*\)\"\{0,1\};.*/\1/p" "$DEST/default.nix" | head -n 1; }

# Removes from a default.nix what new-host.sh added earlier: the blocks whose comment says "added by new-host.sh"
# (up to the next empty line) and the nixos-hardware import line; then tidies the empty lines before the final }.
strip_detected() {
  awk '
    skip && (/^[[:space:]]*$/ || /^}/) { skip = 0 }
    skip { next }
    /^[[:space:]]*#.*added by new-host\.sh/ { skip = 1; next }
    /nixosModules\..*added by new-host\.sh/ { next }
    { print }
  ' "$1" | cat -s | awk '{ l[NR] = $0 } END { for (i = 1; i <= NR; i++) if (!(l[i] ~ /^[[:space:]]*$/ && l[i + 1] ~ /^}/)) print l[i] }'
}

if (( UPDATE )); then
  # Keep the choices of the existing config (only used for the messages below)
  DESKTOP="$(nix_value my.desktop)"; APPS="$(nix_value my.desktopApps)"
  ENCRYPTED="$([[ "$(nix_value my.disk.encrypted)" == true ]] && echo yes || echo no)"
  STATE_VERSION="$(nix_value system.stateVersion)"
  BACKUP="$(mktemp -d)"
  cp -a "$DEST/." "$BACKUP/"
  trap 'echo "Failed; hosts/'"$NAME"' is put back as it was." >&2; rm -rf "$DEST"; mkdir -p "$DEST"; cp -a "$BACKUP/." "$DEST/"; rm -rf "$BACKUP"' ERR
  strip_detected "$BACKUP/default.nix" > "$DEST/default.nix"
else
  [[ -n "$DESKTOP" ]] || DESKTOP="$(var_of desktop)"
  [[ -n "$APPS" ]] || APPS="$(var_of desktopApps)"
  [[ "$DESKTOP" == gnome || "$DESKTOP" == plasma ]] || die "--desktop must be gnome or plasma."
  [[ "$APPS" == full || "$APPS" == minimal ]] || die "--apps must be full or minimal."
  if [[ -z "$ENCRYPTED" ]]; then
    ENCRYPTED=no
    [[ "$(findmnt -no SOURCE "$ROOT" 2>/dev/null || true)" == /dev/mapper/cryptroot ]] && ENCRYPTED=yes
  fi
  case "$ENCRYPTED" in yes) NIX_ENC=true ;; no) NIX_ENC=false ;; *) die "--encrypted must be yes or no." ;; esac

  # stateVersion = the NixOS release this variant is first installed with (format YY.MM).
  # Taken from flake.nix; for nixos-unstable from the installer that is running now.
  STATE_VERSION="$(sed -n 's/.*inputs\.nixpkgs\.url.*nixos-\([0-9][0-9]\.[0-9][0-9]\)".*/\1/p' "$REPO/flake.nix" | head -n 1)"
  if [[ ! "$STATE_VERSION" =~ ^[0-9]{2}\.[0-9]{2}$ ]]; then
    STATE_VERSION="$(nixos-version 2>/dev/null | cut -d. -f1,2 || true)"
  fi
  [[ "$STATE_VERSION" =~ ^[0-9]{2}\.[0-9]{2}$ ]] \
    || die "Cannot determine the NixOS release for system.stateVersion (no release in flake.nix, no nixos-version)."

  mkdir -p "$DEST"
  trap 'echo "Failed; hosts/'"$NAME"' is removed again." >&2; rm -rf "$DEST"' ERR

  sed -e "s/@STATE_VERSION@/$STATE_VERSION/" -e "s/@DESKTOP@/$DESKTOP/" -e "s/@APPS@/$APPS/" -e "s/@ENCRYPTED@/$NIX_ENC/" \
    "$REPO/hosts/_template/default.nix" > "$DEST/default.nix"
fi

# Vendor, model and kind (no machine name or serial number: those stay on the machine itself)
nix_str() { local v="$1"; v="${v//\\/\\\\}"; v="${v//\"/\\\"}"; v="${v//\$/\\\$}"; printf '"%s"' "$v"; }
VENDOR="$(machine_vendor)"; MODEL="$(machine_model)"; KIND="$(machine_kind)"
cat > "$DEST/machine.nix" <<EOF
# Machine type of this config, detected by scripts/new-host.sh. The installer recognises the type by vendor
# and model and then offers this config. (No machine names or serial numbers here: they stay on the machine.)
{
  my.machine = {
    vendor = $(nix_str "$VENDOR");
    model = $(nix_str "$MODEL");
    kind = $(nix_str "$KIND");
  };
}
EOF

echo "Detecting hardware of this machine type (system mounted on $ROOT) ..."
# (nixos-generate-config refuses an explicit "--root /", so it is only passed for another root such as /mnt)
GEN_ARGS=(--no-filesystems --show-hardware-config)
[[ "$ROOT" != / ]] && GEN_ARGS=(--root "$ROOT" "${GEN_ARGS[@]}")
nixos-generate-config "${GEN_ARGS[@]}" > "$DEST/hardware-configuration.nix"

# Adds a block of settings to this variant's default.nix (before its final closing brace).
add_to_host() {  # add_to_host <comment> <settings>
  { sed '$d' "$DEST/default.nix"
    printf '\n  # %s\n%s\n}\n' "$1" "$2"
  } > "$DEST/default.nix.new"
  mv "$DEST/default.nix.new" "$DEST/default.nix"
}

# Virtual machine? Then add the guest tools for that kind of VM.
VIRT="$(machine_virt)"
case "$VIRT" in
  kvm|qemu|bochs)
    add_to_host "Virtual machine ($VIRT): guest tools, added by new-host.sh during installation." \
"  services.qemuGuest.enable = true;       # lets the VM host shut this machine down cleanly
  services.spice-vdagentd.enable = true;  # shared clipboard; the screen size follows the window"
    echo "Virtual machine detected ($VIRT): guest tools are turned on for this variant." ;;
  vmware)
    add_to_host "Virtual machine ($VIRT): guest tools, added by new-host.sh during installation." \
"  virtualisation.vmware.guest.enable = true;  # open-vm-tools: clipboard, screen size, drag and drop"
    echo "Virtual machine detected ($VIRT): guest tools are turned on for this variant." ;;
  ""|none) ;;
  *) echo "Virtual machine detected ($VIRT): NixOS's hardware detection takes care of the guest tools." ;;
esac

# Logitech receiver or mouse attached (USB vendor 046d)? Then turn on Solaar with the button rules.
# (A mouse that is only connected through Bluetooth is not seen here; set my.logitech.enable = true by hand.)
LOGI=""
for d in "${USB_SYSFS:-/sys/bus/usb/devices}"/*; do
  [[ -f "$d/idVendor" && "$(cat "$d/idVendor")" == 046d ]] || continue
  product="$(cat "$d/product" 2>/dev/null || true)"
  if [[ "$product" =~ [Rr]eceiver|[Mm]ouse|Unifying|Bolt|Lightspeed|MX ]]; then LOGI="$product"; break; fi
done
if [[ -n "$LOGI" ]]; then
  add_to_host "Logitech device found ($LOGI): Solaar with button rules, added by new-host.sh." \
"  my.logitech.enable = true;"
  echo "Logitech device detected ($LOGI): Solaar with the button rules is turned on for this variant."
fi

# Video cards: PCI class 0x03xxxx (display controllers), read from /sys (no lspci needed)
pci_bus_id() {  # 0000:01:00.0 -> PCI:1:0:0 (decimal, as NixOS expects)
  local a="${1#*:}" bus dev fn
  bus="${a%%:*}"; a="${a#*:}"; dev="${a%%.*}"; fn="${a#*.}"
  printf 'PCI:%d:%d:%d' "$((16#$bus))" "$((16#$dev))" "$((16#$fn))"
}
INTEL_GPU=""; AMD_GPU=""; NVIDIA_GPU=""; NVIDIA_DEV=""
for d in "${PCI_SYSFS:-/sys/bus/pci/devices}"/*; do
  [[ -f "$d/class" && "$(cat "$d/class")" == 0x03* ]] || continue
  case "$(cat "$d/vendor" 2>/dev/null)" in
    0x8086) [[ -n "$INTEL_GPU" ]] || INTEL_GPU="$(basename "$d")" ;;
    0x1002) [[ -n "$AMD_GPU" ]] || AMD_GPU="$(basename "$d")" ;;
    0x10de) [[ -n "$NVIDIA_GPU" ]] || { NVIDIA_GPU="$(basename "$d")"; NVIDIA_DEV="$(cat "$d/device" 2>/dev/null)"; } ;;
  esac
done
gpu_name() {  # readable name via lspci when available
  command -v lspci >/dev/null 2>&1 && lspci -s "$1" 2>/dev/null | sed 's/^[^:]*: *//; s/^[^:]*: *//' | head -n 1
  return 0
}
if [[ -n "$INTEL_GPU" ]]; then
  add_to_host "Intel GPU found ($(gpu_name "$INTEL_GPU")): video acceleration, added by new-host.sh." \
"  my.intelGpu = true;"
fi
if [[ -n "$NVIDIA_GPU" ]]; then
  # Turing and newer (device id 0x1e00 and up: GTX 16xx, RTX, Quadro T/RTX) use NVIDIA's open kernel modules
  NV_OPEN=false; (( 16#${NVIDIA_DEV#0x} >= 16#1e00 )) && NV_OPEN=true
  block="  my.nvidia.enable = true;
  my.nvidia.open = $NV_OPEN;  # true: Turing or newer; false: an older card"
  note="NVIDIA driver"
  if [[ -n "$INTEL_GPU" || -n "$AMD_GPU" ]]; then
    note="NVIDIA driver with PRIME offload (hybrid graphics; start programs on the NVIDIA card with nvidia-offload)"
    [[ -n "$INTEL_GPU" ]] && block+="
  my.nvidia.prime.intelBusId = \"$(pci_bus_id "$INTEL_GPU")\";"
    [[ -n "$AMD_GPU" && -z "$INTEL_GPU" ]] && block+="
  my.nvidia.prime.amdgpuBusId = \"$(pci_bus_id "$AMD_GPU")\";"
    block+="
  my.nvidia.prime.nvidiaBusId = \"$(pci_bus_id "$NVIDIA_GPU")\";"
  fi
  add_to_host "NVIDIA GPU found ($(gpu_name "$NVIDIA_GPU")): $note, added by new-host.sh." "$block"
  echo "NVIDIA GPU detected ($(gpu_name "$NVIDIA_GPU")): $note."
fi

# Fingerprint reader: USB ids of readers that work on NixOS are in scripts/fingerprint-ids.txt (with their driver)
FP=""; FP_DRIVER=""
for d in "${USB_SYSFS:-/sys/bus/usb/devices}"/*; do
  [[ -f "$d/idVendor" && -f "$d/idProduct" ]] || continue
  id="$(cat "$d/idVendor"):$(cat "$d/idProduct")"
  drv="$(awk -v id="$id" '$1 == id { print $2; exit }' "$REPO/scripts/fingerprint-ids.txt")"
  if [[ -n "$drv" ]]; then FP="$id $(cat "$d/product" 2>/dev/null || true)"; FP_DRIVER="$drv"; break; fi
done
if [[ -n "$FP" ]]; then
  block="  my.fingerprint.enable = true;"
  [[ "$FP_DRIVER" != libfprint ]] && block+="
  my.fingerprint.driver = \"$FP_DRIVER\";  # Dell's own driver for this reader"
  add_to_host "Fingerprint reader found ($FP): log in with a finger (add it with fprintd-enroll), added by new-host.sh." "$block"
  echo "Fingerprint reader detected ($FP): fingerprint login is turned on (driver: $FP_DRIVER)."
fi

# Smartcard reader (USB interface class 0b), e.g. for an eID or company card
SC=""
for d in "${USB_SYSFS:-/sys/bus/usb/devices}"/*:*; do
  [[ "$(cat "$d/bInterfaceClass" 2>/dev/null)" == 0b ]] && { SC="$(cat "${d%:*}/product" 2>/dev/null || basename "${d%:*}")"; break; }
done
if [[ -n "$SC" ]]; then
  add_to_host "Smartcard reader found ($SC), added by new-host.sh." \
"  services.pcscd.enable = true;"
  echo "Smartcard reader detected ($SC): the smartcard service is turned on."
fi

# Thunderbolt / USB4: bolt lets you approve docks and other Thunderbolt devices (in Settings)
if compgen -G "${TB_SYSFS:-/sys/bus/thunderbolt/devices}/domain*" >/dev/null; then
  add_to_host "Thunderbolt found: approve docks and devices in Settings, added by new-host.sh." \
"  services.hardware.bolt.enable = true;"
  echo "Thunderbolt detected: Thunderbolt device management (bolt) is turned on."
fi

# Laptop with an Intel processor: thermald keeps it cool without slowing it down more than needed
CPU_VENDOR="$(awk -F': ' '/^vendor_id/ { print $2; exit }' "${CPUINFO:-/proc/cpuinfo}" 2>/dev/null || true)"
if [[ "$CPU_VENDOR" == GenuineIntel && ( "$KIND" == Laptop || "$KIND" == Tablet ) ]]; then
  add_to_host "Laptop with an Intel processor: temperature management, added by new-host.sh." \
"  services.thermald.enable = true;"
  echo "Intel laptop detected: temperature management (thermald) is turned on."
fi

# Sensors (screen rotation on 2-in-1 laptops and tablets, automatic screen brightness)
CHASSIS="$(cat "${DMI_DIR:-/sys/class/dmi/id}/chassis_type" 2>/dev/null || true)"
if compgen -G "${IIO_SYSFS:-/sys/bus/iio/devices}/iio:device*" >/dev/null || [[ "$CHASSIS" =~ ^(30|31|32)$ ]]; then
  add_to_host "Sensors found (rotation / light), added by new-host.sh." \
"  hardware.sensor.iio.enable = true;"
  echo "Sensors detected: screen rotation and automatic brightness are turned on."
fi

# nixos-hardware: community fixes for this model, when there is a profile for it (needs Nix and internet;
# the list of profiles can also be given in a file, NIXOS_HARDWARE_LIST)
hw_profiles() {
  if [[ -n "${NIXOS_HARDWARE_LIST:-}" ]]; then cat "$NIXOS_HARDWARE_LIST" 2>/dev/null; return 0; fi
  local nix=""
  if command -v nix >/dev/null 2>&1; then nix=nix
  elif [[ -x "${NIX_DEFAULT_BIN:-/nix/var/nix/profiles/default/bin/nix}" ]]; then nix="${NIX_DEFAULT_BIN:-/nix/var/nix/profiles/default/bin/nix}"; fi
  [[ -n "$nix" ]] || return 0
  timeout 120 "$nix" --extra-experimental-features 'nix-command flakes' eval --json \
    github:NixOS/nixos-hardware#nixosModules --apply builtins.attrNames 2>/dev/null | tr -d '[]"' | tr ',' '\n'
  return 0
}
if [[ "$VIRT" == "" || "$VIRT" == none ]]; then
  PROFILES="$(hw_profiles)"
  if [[ -z "$PROFILES" ]]; then
    echo "Note: the list of nixos-hardware profiles could not be fetched (no internet or no Nix); see docs/create-config.md."
  else
    # e.g. lenovo-thinkpad-t14-gen-3 → lenovo-thinkpad-t14-intel-gen3-nvidia, lenovo-thinkpad-t14-intel-gen3, lenovo-thinkpad-t14-gen3
    t="$(machine_type | sed -E 's/-gen-([0-9]+)$/-gen\1/')"
    cpu=""; [[ "$CPU_VENDOR" == GenuineIntel ]] && cpu=intel; [[ "$CPU_VENDOR" == AuthenticAMD ]] && cpu=amd
    with_cpu="$t"
    if [[ -n "$cpu" ]]; then
      if [[ "$t" =~ -gen[0-9]+$ ]]; then with_cpu="$(sed -E "s/-(gen[0-9]+)$/-$cpu-\1/" <<<"$t")"; else with_cpu="$t-$cpu"; fi
    fi
    candidates=()
    [[ -n "$NVIDIA_GPU" ]] && candidates+=("$with_cpu-nvidia" "$t-nvidia")
    candidates+=("$with_cpu" "$t")
    HW=""
    for c in "${candidates[@]}"; do grep -qx "$c" <<<"$PROFILES" && { HW="$c"; break; }; done
    if [[ -n "$HW" ]]; then
      grep -q 'nixos-hardware, \.\.\. }:' "$DEST/default.nix" \
        || sed -i '1,/^{.*}:$/ s/^{ \(.*\), \.\.\. }:$/{ \1, nixos-hardware, ... }:/' "$DEST/default.nix"
      sed -i "/\.\/machine\.nix/a\\    nixos-hardware.nixosModules.$HW  # fixes for this model (github.com/NixOS/nixos-hardware), added by new-host.sh" "$DEST/default.nix"
      echo "nixos-hardware has a profile for this model: $HW (added to the config)."
    else
      echo "nixos-hardware has no profile for $t (that is fine; see docs/create-config.md to add one by hand)."
    fi
  fi
fi

trap - ERR
(( UPDATE )) && rm -rf "$BACKUP"

bash "$REPO/scripts/hosts-overview.sh" >/dev/null || echo "Note: hosts/README.md could not be updated." >&2

# Flakes only see files that Git knows about, so add them right away.
if git -C "$REPO" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git -C "$REPO" add -A "hosts/$NAME" hosts/README.md
else
  echo "Note: $REPO is not a Git repo. Run 'git init -b main && git add -A' first (flakes need Git)." >&2
fi

echo
(( UPDATE )) && echo "Done: hosts/$NAME has been updated with the hardware of this machine ($VENDOR $MODEL, $DESKTOP $APPS, encrypted: $ENCRYPTED, stateVersion $STATE_VERSION)." && exit 0
echo "Done: hosts/$NAME has been created ($VENDOR $MODEL, $DESKTOP $APPS, encrypted: $ENCRYPTED, stateVersion $STATE_VERSION)."
