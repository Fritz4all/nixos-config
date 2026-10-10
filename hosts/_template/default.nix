# Settings for ONE machine. Shared settings live in ../../modules and ../../vars.nix.
# scripts/new-host.sh copies this file to hosts/<hostname>/default.nix.
{ config, lib, pkgs, ... }:

{
  imports = [ ./hardware-configuration.nix ]; # generated for this machine by new-host.sh

  # The NixOS version THIS machine was first installed with.
  # Never change it after installation, not even when upgrading (it is about stored data, not updates).
  system.stateVersion = "@STATE_VERSION@";

  # Overrides for this machine only, for example:
  # my.desktop = "plasma";
  # environment.systemPackages = with pkgs; [ gimp ];
}
