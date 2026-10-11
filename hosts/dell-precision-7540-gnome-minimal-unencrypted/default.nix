# Config for ONE machine type and variant (e.g. a Lenovo ThinkPad T14 Gen 3 with GNOME), shared by every
# machine of that type that is installed with it. Shared settings live in ../../modules and ../../vars.nix.
# scripts/new-host.sh copies this file to hosts/<variant>/default.nix and fills in the @...@ values.
{ config, lib, pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix  # detected hardware of this type (without disks; see modules/disk.nix)
    ./machine.nix                 # vendor, model and kind; the installer recognises the type by it
  ];

  # The NixOS release this variant was first installed with.
  # Never change it, not even when upgrading (it is about stored data, not updates).
  system.stateVersion = "26.05";

  # Desktop of this variant: "gnome" or "plasma"; apps: "full" or "minimal"
  my.desktop = "gnome";
  my.desktopApps = "minimal";

  # Whether the system partition is encrypted (step 2 of the installer); machines installed with this
  # variant must make the same choice
  my.disk.encrypted = false;

  # Overrides for this variant only, for example:
  # environment.systemPackages = with pkgs; [ gimp ];

  # Logitech device found (USB Receiver): Solaar with button rules, added by new-host.sh.
  my.logitech.enable = true;

  # Intel GPU found (Intel Corporation CoffeeLake-H GT2 [UHD Graphics 630] (rev 02)): video acceleration, added by new-host.sh.
  my.intelGpu = true;

  # NVIDIA GPU found (NVIDIA Corporation TU117GLM [Quadro T1000 Mobile] (rev a1)): NVIDIA driver with PRIME offload (hybrid graphics; start programs on the NVIDIA card with nvidia-offload), added by new-host.sh.
  my.nvidia.enable = true;
  my.nvidia.open = true;  # true: Turing or newer; false: an older card
  my.nvidia.prime.intelBusId = "PCI:0:2:0";
  my.nvidia.prime.nvidiaBusId = "PCI:1:0:0";
}
