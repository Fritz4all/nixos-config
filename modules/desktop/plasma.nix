# KDE Plasma (Wayland) with SDDM as the login screen.
{ config, lib, pkgs, ... }:

let
  minimal = config.my.desktopApps == "minimal";
in
{
  config = lib.mkIf (config.my.desktop == "plasma") {
    services.desktopManager.plasma6.enable = true;
    services.displayManager.sddm = {
      enable = true;
      wayland.enable = true;
    };

    # Full: Plasma's usual apps. Minimal: leaves out the extras below and keeps what is needed to work
    # (Dolphin, Konsole, Kate, Gwenview, Okular, Ark, Spectacle, System Settings, System Monitor).
    environment.plasma6.excludePackages = lib.optionals minimal (with pkgs.kdePackages; [
      elisa                       # music player
      khelpcenter                 # help
      krdp                        # remote desktop server
      qrca                        # QR code scanner
      discover                    # app store
      plasma-browser-integration  # browser add-on helper
    ]);
  };
}
