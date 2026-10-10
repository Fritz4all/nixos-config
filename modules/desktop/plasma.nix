# KDE Plasma 6 (Wayland) with SDDM as the login screen.
{ config, lib, ... }:

{
  config = lib.mkIf (config.my.desktop == "plasma") {
    services.desktopManager.plasma6.enable = true;
    services.displayManager.sddm = {
      enable = true;
      wayland.enable = true;
    };
  };
}
