# Programs installed on every machine.
# Look up packages at https://search.nixos.org/packages and add them below.
{ pkgs, ... }:

{
  programs.firefox.enable = true;

  environment.systemPackages = with pkgs; [
    google-chrome   # unfree, which is why allowUnfree is on in common.nix
    brave
    bitwarden-desktop
    vlc
  ];
}
