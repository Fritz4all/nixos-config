# Programs installed on every machine.
# Look up packages at https://search.nixos.org/packages and add them below.
{ pkgs, ... }:

{
  # Unfree packages must be listed here (or in hosts/<name>/default.nix for one machine), otherwise they are refused.
  my.allowedUnfree = [ "google-chrome" ];

  programs.firefox.enable = true;

  # Flatpak, with Flathub as the source for apps (e.g. `flatpak install flathub org.gimp.GIMP`)
  services.flatpak.enable = true;
  systemd.services.flatpak-flathub = {
    description = "Add Flathub as a Flatpak source";
    wantedBy = [ "multi-user.target" ];
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
    path = [ pkgs.flatpak ];
    serviceConfig = {
      Type = "oneshot";
      Restart = "on-failure";   # e.g. no internet yet at startup
      RestartSec = "5min";
    };
    script = "flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo";
  };

  environment.systemPackages = with pkgs; [
    google-chrome   # unfree, therefore listed in my.allowedUnfree above
    brave
    bitwarden-desktop
    vlc
  ];
}
