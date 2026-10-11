#!/usr/bin/env bash
# Creates a new config for a machine type and variant: hosts/<variant>/ with
#   default.nix                  desktop, apps, disk encryption, stateVersion (from hosts/_template)
#   machine.nix                  vendor, model and kind of this machine type (the installer recognises it by this)
#   hardware-configuration.nix   hardware detection without disks (modules/disk.nix finds them by name)
# In a virtual machine it also turns on the guest tools for that kind of VM (QEMU/KVM, VMware); NixOS's own
# hardware detection already handles VirtualBox, Hyper-V and Parallels.
# With a Logitech receiver or mouse attached it turns on Solaar with the button rules (my.logitech.enable).
# Afterwards it updates the overview in hosts/README.md.
#
# Usage: bash scripts/new-host.sh <variant> [options]
#   --root DIR          where the new system is mounted (default /mnt, as in the installer)
#   --desktop NAME      gnome or plasma (default: desktop in vars.nix)
#   --apps SET          full or minimal (default: desktopApps in vars.nix)
#   --encrypted yes|no  disk encryption (default: detected from the disk mounted on --root)
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT="/mnt"
NAME=""
DESKTOP=""
APPS=""
ENCRYPTED=""

die() { echo "ERROR: $*" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --root)      ROOT="${2:?--root needs a path}"; shift 2 ;;
    --desktop)   DESKTOP="${2:?--desktop needs gnome or plasma}"; shift 2 ;;
    --apps)      APPS="${2:?--apps needs full or minimal}"; shift 2 ;;
    --encrypted) ENCRYPTED="${2:?--encrypted needs yes or no}"; shift 2 ;;
    -h|--help)   sed -n '2,/^set -/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*)          die "Unknown option: $1" ;;
    *)           NAME="$1"; shift ;;
  esac
done

[[ -n "$NAME" ]] || die "Usage: bash scripts/new-host.sh <variant> [--root /mnt] [--desktop gnome|plasma] [--apps full|minimal]"
[[ "$NAME" =~ ^[a-z][a-z0-9-]{0,62}$ ]] || die "Invalid name '$NAME': use lowercase letters, digits and hyphens, starting with a letter."
DEST="$REPO/hosts/$NAME"
[[ -e "$DEST" ]] && die "hosts/$NAME already exists. Choose another name or remove that directory first."

# shellcheck source=machine-info.sh
source "$REPO/scripts/machine-info.sh"

var_of() { sed -n "s/^[[:space:]]*$1[[:space:]]*=[[:space:]]*\"\([^\"]*\)\".*/\1/p" "$REPO/vars.nix" | head -n 1; }
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
nixos-generate-config --root "$ROOT" --no-filesystems --show-hardware-config > "$DEST/hardware-configuration.nix"

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

trap - ERR

bash "$REPO/scripts/hosts-overview.sh" >/dev/null || echo "Note: hosts/README.md could not be updated." >&2

# Flakes only see files that Git knows about, so add them right away.
if git -C "$REPO" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git -C "$REPO" add -A "hosts/$NAME" hosts/README.md
else
  echo "Note: $REPO is not a Git repo. Run 'git init -b main && git add -A' first (flakes need Git)." >&2
fi

echo
echo "Done: hosts/$NAME has been created ($VENDOR $MODEL, $DESKTOP $APPS, encrypted: $ENCRYPTED, stateVersion $STATE_VERSION)."
