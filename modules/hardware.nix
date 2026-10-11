# Hardware extras that scripts/new-host.sh turns on per config when it finds the hardware.
# Most are plain NixOS settings written into hosts/<config>/default.nix (Thunderbolt, thermald, sensors,
# smartcard); the fingerprint reader needs a choice of driver, so it has its own option here.
#
# Fingerprint: after installing, add your finger in Settings (GNOME: Users → Fingerprint Login;
# KDE Plasma: Users → Configure Fingerprint Authentication) or with:  fprintd-enroll
# Then you can log in, unlock the screen and use sudo with a finger. (The first login after a start still asks
# for the password, so the keyring with your saved passwords is unlocked.)
{ config, lib, pkgs, ... }:

let
  cfg = config.my.fingerprint;
  todDrivers = {
    broadcom = pkgs.libfprint-2-tod1-broadcom;               # Dell ControlVault 3 (e.g. Precision, Latitude)
    broadcom-cv3plus = pkgs.libfprint-2-tod1-broadcom-cv3plus; # Dell ControlVault 3+
  };
in
{
  options.my.fingerprint = {
    enable = lib.mkEnableOption "the fingerprint reader (fprintd)";
    driver = lib.mkOption {
      type = lib.types.enum [ "libfprint" "broadcom" "broadcom-cv3plus" ];
      default = "libfprint";
      description = ''
        Driver for the reader: "libfprint" (the open driver, most readers) or one of Dell's own drivers for
        ControlVault readers ("broadcom", "broadcom-cv3plus"; unfree). scripts/fingerprint-ids.txt lists which.
      '';
    };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    { services.fprintd.enable = true; }
    (lib.mkIf (cfg.driver != "libfprint") {
      services.fprintd.tod = {
        enable = true;
        driver = todDrivers.${cfg.driver};
      };
      my.allowedUnfree = [ "libfprint-2-tod1-${cfg.driver}" ];
    })
  ]);
}
