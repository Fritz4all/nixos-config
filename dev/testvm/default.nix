# Test machine for dev/check-config.sh. Uses the shared modules like a real machine.
{ vars, ... }:
{
  imports = [ ./hardware-configuration.nix ];
  system.stateVersion = "26.05";

  # Only for the test VM (nixos-rebuild build-vm / system.build.vm), never for a real machine:
  virtualisation.vmVariant = {
    virtualisation.memorySize = 4096;
    virtualisation.cores = 4;
    virtualisation.resolution = { x = 1600; y = 900; };
    users.users.${vars.username}.initialPassword = "test"; # throwaway test VM password, allow-secret
    services.displayManager.autoLogin = { enable = true; user = vars.username; };
    # Needed for automatic login with GNOME
    systemd.services."getty@tty1".enable = false;
    systemd.services."autovt@tty1".enable = false;
  };
}
