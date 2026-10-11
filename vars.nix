# Central settings that apply to ALL machines.
# The username and full name are set during installation with the installer (step 4, scripts/settings.sh).
# Change the rest (language, time zone, keyboard, desktop) here.
{
  # Your user account (the same on every machine)
  username = "changeme";
  fullName = "Change Me";

  # Where this config lives online (used by scripts/fetch-config.sh for "Download config").
  # Leave empty until you have uploaded it to GitHub, e.g.
  #   repoUrl = "https://github.com/YOURNAME/nixos-config.git";
  repoUrl = "https://github.com/Fritz4all/nixos-config.git";

  # Default desktop for a NEW variant: "gnome" or "plasma" (KDE Plasma), and its apps: "minimal" (only what you
  # need to work; the default) or "full" (the desktop's usual set of apps). Each variant in hosts/<variant>/default.nix
  # sets its own my.desktop and my.desktopApps; the installer asks for them when it creates a variant.
  desktop = "gnome";
  desktopApps = "minimal";

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
