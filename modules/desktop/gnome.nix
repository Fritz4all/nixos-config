# GNOME (Wayland) with GDM as the login screen.
{ config, lib, pkgs, ... }:

{
  config = lib.mkIf (config.my.desktop == "gnome") {
    services.displayManager.gdm.enable = true;
    services.desktopManager.gnome.enable = true;

    # You already have three browsers, so GNOME Web and the welcome tour are not needed.
    environment.gnome.excludePackages = with pkgs; [
      gnome-tour
      epiphany
    ];

    environment.systemPackages = with pkgs; [
      gnome-tweaks
    ];
  };
}
