# Programs installed on every machine.
# Look up packages at https://search.nixos.org/packages and add them below.
{ pkgs, ... }:

{
  # Unfree packages must be listed here (or in hosts/<name>/default.nix for one machine), otherwise they are refused.
  my.allowedUnfree = [ "google-chrome" ];

  programs.firefox.enable = true;

  environment.systemPackages = with pkgs; [
    google-chrome   # unfree, therefore listed in my.allowedUnfree above
    brave
    bitwarden-desktop
    vlc
  ];
}
