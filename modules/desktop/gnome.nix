# GNOME (Wayland) with GDM as the login screen.
{ config, lib, pkgs, ... }:

let
  minimal = config.my.desktopApps == "minimal";
in
{
  config = lib.mkIf (config.my.desktop == "gnome") {
    services.displayManager.gdm.enable = true;
    services.desktopManager.gnome.enable = true;

    # Full: GNOME's usual apps (calendar, contacts, maps, weather, music, clocks, ...).
    # Minimal: those are left out; the apps needed to work are added back below.
    services.gnome.core-apps.enable = !minimal;

    # You already have three browsers, so GNOME Web and the welcome tour are not needed.
    environment.gnome.excludePackages = with pkgs; [
      gnome-tour
      epiphany
    ];

    environment.systemPackages = with pkgs; [
      gnome-tweaks
    ] ++ lib.optionals minimal [
      nautilus             # Files
      gnome-console        # Terminal
      gnome-text-editor    # Text Editor
      gnome-system-monitor # System Monitor
      gnome-disk-utility   # Disks
      gnome-calculator     # Calculator
      loupe                # Image Viewer
      papers               # Document Viewer (PDF)
    ];
  };
}
