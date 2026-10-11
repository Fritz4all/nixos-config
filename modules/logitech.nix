# Logitech mice and keyboards (Unifying, Bolt and Lightspeed receivers): Solaar with button rules.
# On for one machine with `my.logitech.enable = true;`. The installer sets that by itself when it finds a
# Logitech receiver or mouse (scripts/new-host.sh). The rules are in ./logitech/rules.yaml
# (thumb wheel = volume up/down).
{ config, lib, pkgs, vars, ... }:

let
  user = vars.username;
  home = config.users.users.${user}.home;
in
{
  options.my.logitech.enable = lib.mkEnableOption "Solaar for Logitech mice and keyboards, with button rules";

  config = lib.mkIf config.my.logitech.enable {
    # Solaar and the udev rules that give the logged-in user access to the Logitech devices
    hardware.logitech.wireless = {
      enable = true;
      enableGraphical = true;
    };

    # Solaar sends key presses (volume up/down) through /dev/uinput; that is needed under Wayland
    hardware.uinput.enable = true;
    users.users.${user}.extraGroups = [ "uinput" ];

    # Start Solaar hidden at login: its rules only work while it runs
    environment.etc."xdg/autostart/solaar.desktop".text = ''
      [Desktop Entry]
      Type=Application
      Name=Solaar
      Comment=Logitech device manager (button rules)
      Exec=solaar --window=hide
      Icon=solaar
      X-GNOME-Autostart-enabled=true
    '';

    # Put the button rules in ~/.config/solaar/rules.yaml, but only when that file does not exist yet,
    # so changes you make later (in Solaar's rule editor) are kept.
    system.activationScripts.solaarRules = {
      deps = [ "users" ];
      text = ''
        f=${home}/.config/solaar/rules.yaml
        if [ -d ${home} ] && [ ! -e "$f" ]; then
          if [ ! -e ${home}/.config ]; then
            mkdir -p ${home}/.config
            chown ${user}:users ${home}/.config
          fi
          mkdir -p ${home}/.config/solaar
          install -m 644 ${./logitech/rules.yaml} "$f"
          chown -R ${user}:users ${home}/.config/solaar
        fi
      '';
    };
  };
}
