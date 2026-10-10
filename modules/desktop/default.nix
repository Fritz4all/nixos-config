# Chooses which desktop environment is active, and how many apps come with it.
# Switching: set `desktop` in vars.nix to "gnome" or "plasma" (for all machines),
# or set `my.desktop = "plasma";` in hosts/<name>/default.nix (for that machine only).
# Then: `rebuild-boot` and reboot.
{ lib, vars, ... }:

{
  imports = [
    ./gnome.nix
    ./plasma.nix
  ];

  options.my.desktop = lib.mkOption {
    type = lib.types.enum [ "gnome" "plasma" ];
    default = vars.desktop;
    description = "Which desktop environment this machine uses.";
  };

  options.my.desktopApps = lib.mkOption {
    type = lib.types.enum [ "full" "minimal" ];
    default = vars.desktopApps or "full";
    description = ''
      Which apps come with the desktop. "full": the desktop's usual set of apps.
      "minimal": only what is needed to work (files, terminal, text editor, system tools, viewers).
    '';
  };
}
