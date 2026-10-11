# Automatic updates: once a week the newest versions within the NixOS release are fetched and built.
# They become active at the next start, so nothing changes while you work; the previous version stays in the
# boot menu. There is never an automatic reboot. Turn it off for one machine with `my.autoUpdate = false;`.
#   Next run:        systemctl list-timers nixos-auto-update
#   Last result:     journalctl -u nixos-auto-update
#   Run it now:      sudo systemctl start nixos-auto-update
{ config, lib, pkgs, ... }:

{
  options.my.autoUpdate = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = "Fetch and build updates automatically once a week (active at the next start).";
  };

  config = lib.mkIf config.my.autoUpdate {
    systemd.services.nixos-auto-update = {
      description = "Weekly NixOS update (active at the next start)";
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];
      restartIfChanged = false;   # never interrupt a running update when the system is rebuilt
      environment = config.nix.envVars // {
        AUTO_UPDATE_HOST = config.networking.hostName;
      };
      path = [
        config.nix.package
        config.system.build.nixos-rebuild
        pkgs.git
        pkgs.coreutils
        pkgs.util-linux   # runuser
        pkgs.getent
      ];
      serviceConfig.Type = "oneshot";
      script = builtins.readFile ./auto-update.sh;
    };

    systemd.timers.nixos-auto-update = {
      description = "Weekly NixOS update";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "weekly";
        RandomizedDelaySec = "1h";   # not every machine at the same moment
        Persistent = true;           # catch up after the laptop was off at the planned time
      };
    };
  };
}
