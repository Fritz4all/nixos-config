# Installer ISO made by build-iso.sh (through lib.mkIso in flake.nix). It is the normal graphical NixOS
# installer (GNOME live session) plus:
#   - this repo, at /iso/nixos-config on the running ISO
#   - the installation menu (install.sh), which starts by itself after the live session has started
#   - /etc/nixos-config-iso: the configs whose complete system is on the ISO (one per line); the installer
#     uses it to install those without internet, and to mark them "on this ISO" in step 4
#   - the complete systems of those configs and the nixpkgs source of flake.lock, so nixos-install finds
#     everything on the stick
# Arguments (specialArgs): self = this flake, variants = list of configs in hosts/, label = name for the file.
{ config, lib, pkgs, modulesPath, self, variants, label, ... }:

let
  systems = map (v: self.nixosConfigurations.${v}.config.system.build.toplevel) variants;
in
{
  imports = [ "${modulesPath}/installer/cd-dvd/installation-cd-graphical-gnome.nix" ];

  nixpkgs.hostPlatform = "x86_64-linux";

  # The repo on the stick, and the list of configs that can be installed offline
  isoImage.contents = [ { source = self.outPath; target = "/nixos-config"; } ];
  environment.etc."nixos-config-iso".text = lib.concatMapStrings (v: v + "\n") variants;

  # Everything needed to install those configs without internet
  isoImage.storeContents = systems ++ [ self.inputs.nixpkgs.outPath ];

  # Tools used by the installation menu
  environment.systemPackages = with pkgs; [ git gnome-console ];

  # Start the installation menu in a terminal as soon as the live session is up
  environment.etc."xdg/autostart/nixos-config-installer.desktop".text = ''
    [Desktop Entry]
    Type=Application
    Name=NixOS installer (nixos-config)
    Exec=kgx --title "Install NixOS" -- bash /iso/nixos-config/install.sh
    X-GNOME-Autostart-enabled=true
  '';

  image.baseName = lib.mkForce "nixos-config-${label}";
  isoImage.edition = lib.mkForce "config";
  isoImage.appendToMenuLabel = " (nixos-config: ${label})";
}
