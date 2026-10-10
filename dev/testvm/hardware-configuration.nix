# Fake hardware for the test machine: an encrypted ext4 disk with an EFI partition,
# like the one scripts/prepare-disk.sh creates. Only used by dev/check-config.sh.
{ lib, modulesPath, ... }:
{
  imports = [ (modulesPath + "/profiles/qemu-guest.nix") ];
  boot.initrd.availableKernelModules = [ "ahci" "xhci_pci" "virtio_pci" "sr_mod" "virtio_blk" ];
  boot.initrd.luks.devices."cryptroot".device = "/dev/disk/by-uuid/11111111-2222-3333-4444-555555555555";
  fileSystems."/" = { device = "/dev/disk/by-uuid/aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"; fsType = "ext4"; };
  fileSystems."/boot" = { device = "/dev/disk/by-uuid/ABCD-1234"; fsType = "vfat"; options = [ "fmask=0077" "dmask=0077" ]; };
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
