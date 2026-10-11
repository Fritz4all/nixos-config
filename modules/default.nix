# Everything in this directory is used by every machine.
{
  imports = [
    ./common.nix
    ./disk.nix
    ./apps.nix
    ./commands.nix
    ./auto-update.nix
    ./logitech.nix
    ./graphics.nix
    ./hardware.nix
    ./desktop
  ];
}
