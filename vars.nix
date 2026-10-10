# Central settings that apply to ALL machines.
# The username and full name are set during installation with scripts/setup-user.sh.
# Change the rest (language, time zone, keyboard, desktop) here.
{
  # Your user account (the same on every machine)
  username = "changeme";
  fullName = "Change Me";

  # Where this config lives online (used by scripts/fetch-config.sh for "Download config").
  # Leave empty until you have uploaded it to GitHub, e.g.
  #   repoUrl = "https://github.com/YOURNAME/nixos-config.git";
  repoUrl = "https://github.com/Fritz4all/nixos-config.git";

  # Desktop environment: "gnome" or "plasma" (KDE Plasma).
  # Switching = change it here (all machines) or per machine in hosts/<name>/default.nix
  # with `my.desktop = "plasma";`. Then rebuild and reboot.
  desktop = "gnome";

  # Time, language and region
  timeZone = "Europe/Amsterdam";
  locale = "en_US.UTF-8";          # interface language; set to "nl_NL.UTF-8" for Dutch
  regionalLocale = "nl_NL.UTF-8";  # date, time, currency, A4 paper, etc.

  # Keyboard. "us" + "intl" = US International (dead keys for é, ë, ç).
  # For a plain US keyboard: variant = "". For Dutch: layout = "nl", variant = "".
  keyboard = {
    layout = "us";
    variant = "intl";
  };
}
