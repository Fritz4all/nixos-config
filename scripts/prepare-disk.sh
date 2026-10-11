#!/usr/bin/env bash
# Picks a disk from a list and prepares it for NixOS:
#   GPT partition table, EFI partition (1 GiB), the rest for the system (ext4),
#   optionally encrypted with LUKS, then mounted on /mnt.
#
# Usage (as root, in the NixOS installer, from a directory outside /mnt):
#   bash scripts/prepare-disk.sh [--dry-run]
#   --dry-run  only show what would happen, nothing is changed
set -euo pipefail

MNT="/mnt"
MAPPER="cryptroot"
DRY_RUN=0
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

die()  { echo "ERROR: $*" >&2; exit 1; }
warn() { echo "Warning: $*" >&2; }

# Runs a command, or only shows it with --dry-run.
run() {
  if (( DRY_RUN )); then
    printf '+ '; printf '%q ' "$@"; echo
  else
    "$@"
  fi
}

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    -h|--help) sed -n '2,/^set -/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) die "Unknown option: $arg" ;;
  esac
done

# Mounts with an explicit file system type, retrying a few times: right after formatting, udev may still be
# busy and `mount` without a type may not recognise the new file system yet (seen in a VM: it then tried FAT
# and ISO9660 on the new ext4 partition and failed with "wrong fs type"). With -t the kernel loads ext4 itself.
mount_retry() {  # mount_retry <type> <device> <dir> [options]
  local i
  for i in 1 2 3 4 5; do
    udevadm settle 2>/dev/null || true
    if mount -t "$1" ${4:+-o "$4"} "$2" "$3"; then return 0; fi
    echo "Mounting $2 did not work yet; trying again ($i/5) ..."
    sleep 2
  done
  return 1
}

# Asks "Try again?" after a failed attempt (e.g. a typo in a passphrase). Exit code 0 = try again.
try_again() {
  local again
  read -rp "Try again? [Y/n]: " again || return 1
  [[ ! "$again" =~ ^[nN] ]]
}

# Check that we run in the right environment (with --dry-run only warn).
check() {
  local msg="$1"
  if (( DRY_RUN )); then warn "$msg (dry run, continuing)"; else die "$msg"; fi
}

(( EUID == 0 )) || check "Run this as root (type: sudo -i first)."
[[ -d /sys/firmware/efi ]] || check "This computer was not booted in UEFI mode. Boot the USB stick in UEFI mode."
for cmd in lsblk parted partprobe wipefs udevadm mkfs.fat mkfs.ext4 cryptsetup mountpoint; do
  command -v "$cmd" >/dev/null 2>&1 || check "Program '$cmd' not found."
done
case "$REPO" in
  "$MNT"|"$MNT"/*) die "Run this script from a directory outside $MNT (e.g. /root/nixos-config); $MNT is about to be unmounted." ;;
esac

trap 'echo; echo "Something went wrong. You can run the script again; it cleans up earlier attempts itself." >&2' ERR

# Clean up an earlier attempt, so the disk is not seen as "in use".
if mountpoint -q "$MNT"; then
  echo "Something is already mounted on $MNT (probably an earlier attempt). Unmounting it."
  run umount -R "$MNT"
fi
if [[ -e "/dev/mapper/$MAPPER" ]]; then
  echo "Closing encrypted disk '$MAPPER' from an earlier attempt."
  run cryptsetup close "$MAPPER"
fi

##### Show disks #####

in_use() {
  local mp
  mp="$(lsblk -nr -o MOUNTPOINTS "$1" 2>/dev/null || lsblk -nr -o MOUNTPOINT "$1" 2>/dev/null || true)"
  [[ -n "${mp//[[:space:]]/}" ]]
}

trim() { sed 's/^[[:space:]]*//; s/[[:space:]]*$//'; }

DISKS=()
USABLE=()

while read -r dev; do
  [[ -n "$dev" ]] || continue
  [[ "$dev" == /dev/zram* ]] && continue
  DISKS+=("$dev")
done < <(lsblk -dnpo NAME,TYPE | awk '$2=="disk"{print $1}')

(( ${#DISKS[@]} > 0 )) || die "No disks found."

echo
echo "Available disks:"
echo
printf '  %-3s %-15s %-9s %-5s %-6s %s\n' "No" "Device" "Size" "Type" "Bus" "Model"
for i in "${!DISKS[@]}"; do
  dev="${DISKS[$i]}"
  size="$(lsblk -dnpo SIZE "$dev" | trim)"
  model="$(lsblk -dnpo MODEL "$dev" | trim)"
  tran="$(lsblk -dnpo TRAN "$dev" | trim)"
  rota="$(lsblk -dnpo ROTA "$dev" | trim)"
  kind="SSD"; [[ "$rota" == "1" ]] && kind="HDD"
  note=""
  if in_use "$dev"; then
    note="  <- in use (probably the USB stick), cannot be chosen"
  else
    USABLE+=("$i")
  fi
  printf '  %-3s %-15s %-9s %-5s %-6s %s%s\n' "$((i + 1))" "$dev" "$size" "$kind" "${tran:--}" "${model:--}" "$note"
done
echo

(( ${#USABLE[@]} > 0 )) || die "There is no disk available that is not in use."

##### Choose a disk #####

DISK=""
while [[ -z "$DISK" ]]; do
  read -rp "Which disk to install on? Type the number (q = quit): " choice
  if [[ "$choice" == "q" || "$choice" == "Q" ]]; then
    echo "Stopped, nothing was changed."
    exit 0
  fi
  if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#DISKS[@]} )); then
    idx=$((choice - 1))
    if in_use "${DISKS[$idx]}"; then
      echo "That disk is in use and cannot be chosen."
    else
      DISK="${DISKS[$idx]}"
    fi
  else
    echo "Invalid choice."
  fi
done

echo
echo "Current contents of $DISK:"
lsblk -o NAME,SIZE,FSTYPE,LABEL "$DISK"
echo
echo "WARNING: EVERYTHING on $DISK will be erased and cannot be recovered."
read -rp "Type '$DISK' to confirm: " confirm
[[ "$confirm" == "$DISK" ]] || { echo "Not confirmed, nothing was changed."; exit 0; }

ENCRYPT=1
read -rp "Encrypt the disk with LUKS? (recommended for a laptop) [Y/n]: " enc
[[ "$enc" =~ ^[nN] ]] && ENCRYPT=0

# Partition names: nvme0n1 -> nvme0n1p1, sda -> sda1
if [[ "$DISK" =~ [0-9]$ ]]; then
  P1="${DISK}p1"; P2="${DISK}p2"
else
  P1="${DISK}1"; P2="${DISK}2"
fi

##### Partitioning #####

echo
echo "Partitioning ..."
while read -r part; do
  [[ -n "$part" ]] && run wipefs --all --force "$part"
done < <(lsblk -nlpo NAME "$DISK" | tail -n +2)
run wipefs --all --force "$DISK"

run parted --script "$DISK" mklabel gpt
run parted --script "$DISK" mkpart ESP fat32 1MiB 1GiB
run parted --script "$DISK" set 1 esp on
run parted --script "$DISK" mkpart nixos 1GiB 100%
run partprobe "$DISK"
run udevadm settle

if (( ! DRY_RUN )); then
  for _ in $(seq 1 20); do
    [[ -b "$P1" && -b "$P2" ]] && break
    sleep 0.5
  done
  [[ -b "$P1" && -b "$P2" ]] || die "The new partitions $P1 and $P2 do not appear."
fi

##### Formatting (and encryption) #####

echo
echo "Formatting ..."
run mkfs.fat -F 32 -n BOOT "$P1"

if (( ENCRYPT )); then
  echo
  echo "Now choose a strong passphrase for the disk encryption."
  echo "You type it every time the laptop starts. If you lose it, your data is gone."
  echo "You type it twice; a typo just means you can try again."
  until run cryptsetup luksFormat --batch-mode --verify-passphrase "$P2"; do
    echo "That did not work (the two passphrases probably did not match)."
    try_again || die "Encryption was not set up. Run this step again to start over."
  done
  echo "Type the passphrase once more to open the disk:"
  until run cryptsetup open "$P2" "$MAPPER"; do
    echo "The disk could not be opened (wrong passphrase?)."
    try_again || die "The disk was not opened. Run this step again to start over."
  done
  ROOT_DEV="/dev/mapper/$MAPPER"
else
  ROOT_DEV="$P2"
fi

run mkfs.ext4 -F -L nixos "$ROOT_DEV"

##### Mounting #####

echo
echo "Mounting on $MNT ..."
run udevadm settle
run mount_retry ext4 "$ROOT_DEV" "$MNT" || die "Mounting $ROOT_DEV on $MNT failed. Run this step again."
run mkdir -p "$MNT/boot"
run mount_retry vfat "$P1" "$MNT/boot" umask=077 || die "Mounting $P1 on $MNT/boot failed. Run this step again."

trap - ERR

echo
if (( DRY_RUN )); then
  echo "Dry run finished: nothing was changed."
else
  echo "Done. Overview:"
  lsblk -o NAME,SIZE,FSTYPE,LABEL,MOUNTPOINTS "$DISK"
  [[ -n "${INSTALL_MENU:-}" ]] || cat <<EOF

Next step, fetch the config to $MNT/etc/nixos:
  bash $REPO/scripts/fetch-config.sh
EOF
fi
