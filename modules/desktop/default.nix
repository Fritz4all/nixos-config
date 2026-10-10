# Chooses which desktop environment is active.
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
}
