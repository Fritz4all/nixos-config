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
  system.stateVersion = "@STATE_VERSION@";

  # Desktop of this variant: "gnome" or "plasma"; apps: "full" or "minimal"
  my.desktop = "@DESKTOP@";
  my.desktopApps = "@APPS@";

  # Whether the system partition is encrypted (step 2 of the installer); machines installed with this
  # variant must make the same choice
  my.disk.encrypted = @ENCRYPTED@;

  # Overrides for this variant only, for example:
  # environment.systemPackages = with pkgs; [ gimp ];
}
