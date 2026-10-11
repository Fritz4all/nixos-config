# The disk layout made by scripts/prepare-disk.sh: an EFI partition named "ESP" and a system partition named
# "nixos" (optionally encrypted with LUKS, opened as "cryptroot"). The disks are found by these names, not by
# disk IDs, so one config works on every machine of the same type. (The hardware detection therefore runs with
# --no-filesystems.)
{ config, lib, ... }:

{
  options.my.disk.encrypted = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = "Whether the system partition is encrypted with LUKS (chosen in step 2 of the installer).";
  };

  config = {
    boot.initrd.luks.devices = lib.mkIf config.my.disk.encrypted {
      cryptroot.device = "/dev/disk/by-partlabel/nixos";
    };

    fileSystems."/" = {
      # With LUKS the root must be /dev/mapper/<name>, so systemd does not time out at the passphrase prompt
      device = if config.my.disk.encrypted then "/dev/mapper/cryptroot" else "/dev/disk/by-partlabel/nixos";
      fsType = "ext4";
    };

    fileSystems."/boot" = {
      device = "/dev/disk/by-partlabel/ESP";
      fsType = "vfat";
      options = [ "fmask=0077" "dmask=0077" ];
    };
  };
}
