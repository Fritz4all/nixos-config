# Base settings for every machine: boot, Nix, network, language, sound, user.
{ config, lib, pkgs, vars, ... }:

{
  ##### Bootloader (UEFI) #####
  boot.loader.systemd-boot = {
    enable = true;
    configurationLimit = 10; # keeps /boot tidy: at most 10 older versions
    editor = false;          # safer: no editing kernel options in the boot menu
  };
  boot.loader.efi.canTouchEfiVariables = true;

  ##### Nix itself #####
  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    auto-optimise-store = true;
  };
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 30d";
  };
  nixpkgs.config.allowUnfree = true; # needed for Google Chrome, among others

  ##### Network #####
  networking.networkmanager.enable = true;
  # The firewall is on by default. The hostname comes from the directory name in hosts/.

  ##### Time, language and keyboard (settings are in vars.nix) #####
  time.timeZone = vars.timeZone;
  i18n.defaultLocale = vars.locale;
  i18n.extraLocaleSettings = lib.genAttrs [
    "LC_ADDRESS"
    "LC_IDENTIFICATION"
    "LC_MEASUREMENT"
    "LC_MONETARY"
    "LC_NAME"
    "LC_NUMERIC"
    "LC_PAPER"
    "LC_TELEPHONE"
    "LC_TIME"
  ] (_: vars.regionalLocale);

  services.xserver.xkb = {
    layout = vars.keyboard.layout;
    variant = vars.keyboard.variant;
  };
  console.useXkbConfig = true; # same keyboard in the console and at the disk passphrase prompt

  ##### Sound (PipeWire) #####
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    pulse.enable = true;
  };

  ##### Hardware and maintenance #####
  hardware.enableRedistributableFirmware = lib.mkDefault true;
  hardware.bluetooth.enable = true;
  services.fwupd.enable = true;   # firmware updates (command: fwupdmgr update)
  services.fstrim.enable = true;  # maintenance for SSDs
  zramSwap.enable = true;         # compressed swap in memory

  ##### Printing and finding printers on the network #####
  services.printing.enable = true;
  services.avahi = {
    enable = true;
    nssmdns4 = true;
    openFirewall = true;
  };

  ##### User #####
  # The password is set during installation (see README), not in this repo.
  users.users.${vars.username} = {
    isNormalUser = true;
    description = vars.fullName;
    extraGroups = [ "wheel" "networkmanager" ];
  };

  ##### Basic programs #####
  programs.git.enable = true;
  # gh = GitHub CLI: run `gh auth login` once, after that `git push` to GitHub works
  environment.systemPackages = with pkgs; [
    vim
    gh
    curl
    wget
    htop
    tree
    unzip
    ripgrep
    pciutils
    usbutils
  ];

  fonts.packages = with pkgs; [
    noto-fonts
    noto-fonts-color-emoji
    liberation_ttf
  ];

  # Chrome, Brave and other Electron apps then run natively on Wayland (sharper rendering)
  environment.sessionVariables.NIXOS_OZONE_WL = "1";

  # The commands rebuild, rebuild-boot, nixup, versions and nixos-release are in commands.nix.
}
