# NixOS configuration (flake) for all my machines

One repo for all machines: GNOME or KDE Plasma as the desktop, each in a Full or a Minimal version (chosen
during installation, switching later is one line), with Firefox, Google Chrome, Brave, Bitwarden and VLC. The NixOS release is chosen during installation
from the releases that are available at that moment, and can be changed later with one command (`nixos-release`).

Installing a machine comes down to: boot the NixOS installer, get this folder, run
`bash install.sh` and follow the menu.

---

## Contents

- [What is in this folder](#what-is-in-this-folder)
- [Daily use](#daily-use)
- [Part 1: Put the config on a USB stick](#part-1-put-the-config-on-a-usb-stick)
- [Part 2: Install a machine](#part-2-install-a-machine)
  - [2.1 Make the installer USB stick and start from it](#21-make-the-installer-usb-stick-and-start-from-it)
  - [2.2 Internet and terminal](#22-internet-and-terminal)
  - [2.3 Start the installation menu](#23-start-the-installation-menu)
  - [2.4 The installation menu](#24-the-installation-menu)
  - [2.5 Optional: save the new machine to GitHub](#25-optional-save-the-new-machine-to-github)
- [Adding another machine](#adding-another-machine)
- [Desktop: GNOME or KDE Plasma, Full or Minimal](#desktop-gnome-or-kde-plasma-full-or-minimal)
- [Building your own ISO](#building-your-own-iso)
- [Keeping secrets out](#keeping-secrets-out)
- [New NixOS releases](#new-nixos-releases)
- [Troubleshooting](#troubleshooting)
- [Details](#details)
  - [Using the scripts without the menu](#using-the-scripts-without-the-menu)
  - [Partitioning by hand](#partitioning-by-hand)

---

## What is in this folder

```
nixos-config/
├── README.md        this guide
├── install.sh       THE INSTALLER: start this in the NixOS live system
├── build-iso.sh     builds your own installer ISO (run it on your own computer, see "Building your own ISO")
├── flake.nix        ┐
├── flake.lock       │  THE CONFIGURATION AND THE INSTALLER
├── vars.nix         │  Needed on GitHub and on the USB stick.
├── hosts/           │  (flake.lock appears after the first installation)
├── modules/         │
├── scripts/         │
├── iso/             ┘
│
├── docs/            extra manuals (saving a machine to GitHub, how the repo was put on GitHub)
├── .githooks/       blocks commits that contain passwords, keys or tokens (see "Keeping secrets out")
└── .gitignore       tells Git which files to leave out (build results, test files, secret files)
```

Everything you need is on GitHub; Part 1 explains how to put it on a USB stick.

| Part | What it is |
|---|---|
| `vars.nix` | shared choices: username, language, time zone, keyboard, GitHub address (`repoUrl`), and the default desktop for new configs |
| `modules/common.nix` | basics for every machine: boot, network, sound, printing, Bluetooth, user, basic programs |
| `modules/apps.nix` | Firefox, Chrome, Brave, Bitwarden, VLC |
| `modules/commands.nix` | the daily commands `rebuild`, `rebuild-boot`, `nixup`, `versions`, `nixos-release` |
| `modules/auto-update.nix` | the weekly automatic update (active at the next start) |
| `modules/logitech.nix` | Solaar for Logitech mice, with the button rules in `modules/logitech/rules.yaml` |
| `modules/desktop/` | `gnome.nix` and `plasma.nix`, each in a Full and a Minimal version; chosen per config |
| `modules/disk.nix` | finds the disks by name (not by disk ID), so one config works on every machine of a type |
| `hosts/<config>/` | **one config per machine type and variant**, e.g. `lenovo-thinkpad-t14-gen-3-gnome`: hardware of that type, vendor/model (`machine.nix`), desktop, apps, disk encryption. Shared by every machine of that type; made by the installer |
| `hosts/README.md` | table of all configs (vendor, model, desktop, …), shown by GitHub when you open the `hosts` folder |
| `hosts/_template/` | template for a new config |
| `flake.nix` | sets the NixOS release and turns every directory in `hosts/` into a config automatically |
| `flake.lock` | records the exact versions, so all machines get the same software |
| `install.sh` | **the installer**: a menu that runs the steps below in the right order |
| `scripts/prepare-disk.sh` | choose, partition, encrypt and mount the disk |
| `scripts/fetch-config.sh` | put the config on the new disk: download from GitHub, or copy locally |
| `scripts/settings.sh` | step 4: username, the config for this machine (recognised by vendor and model), machine name, NixOS release |
| `scripts/release.sh` | show the available NixOS releases and choose one (later also as the command `nixos-release`) |
| `scripts/install-system.sh` | step 5: make a new config if needed, run `nixos-install`, write the machine name, set the passwords, show the versions |
| `scripts/new-host.sh` | create a config `hosts/<config>/` (used by `install-system.sh`) |
| `scripts/machine-info.sh` | reads vendor, model, kind and serial number from the firmware |
| `scripts/hosts-overview.sh` | writes `hosts/README.md` and lists the configs for the installer and `build-iso.sh` |
| `build-iso.sh` + `iso/installer.nix` | build your own installer ISO with the config (and optionally all software) on it |
| `scripts/versions.sh` | show the versions of the system and your programs (later also as the command `versions`) |

Shared = everything in `vars.nix` and `modules/`. Per machine **type** = its config in `hosts/`. Per **machine** =
only its name, which stays on the machine itself (in `/etc/hostname`, never in Git): ten laptops of the same model
share one config, and nothing about them has to be added to GitHub.

---

## Daily use

| Command | What it does |
|---|---|
| `rebuild` | apply changes in `/etc/nixos` right away |
| `rebuild-boot` | apply at the next reboot (safe for big changes) |
| `nixup` | update all packages (`nix flake update`) and apply |
| `versions` | show the versions of NixOS, kernel, desktop and your programs |
| `nixos-release` | show or change the NixOS release (see "New NixOS releases") |
| `sudo nixos-rebuild switch --rollback` | go back to the previous version |
| `sudo hostnamectl set-hostname <name>` | change the name of this machine (it is only stored on the machine) |
| `nixos-rebuild list-generations` | list all versions (generations) of the system, with their date; the current one is marked |
| `nix run nixpkgs#gimp` | start a program once (here GIMP) without installing it |
| `nix shell nixpkgs#cowsay` | make a program available only in this terminal session (then e.g. `cowsay hello`) |
| `nix-shell -p gimp` | the same, older style: use a program temporarily in this terminal; gone after `exit` or closing the terminal |
| `flatpak install flathub org.gimp.GIMP` | install an app from Flathub (Flatpak); `flatpak list` shows them, `flatpak update` updates them, `flatpak uninstall <app>` removes one |
| `nix-collect-garbage` | remove downloads that nothing uses any more (e.g. from `nix-shell`); your system and its generations stay |

These are real commands (in `modules/commands/`): they work with and without `sudo` and ask for your password
when needed. They build as the owner of `/etc/nixos` and only use administrator rights to activate.

Something broken after an update? Choose an older version in the boot menu.

**Automatic updates:** once a week every machine fetches and builds the newest versions within its NixOS release
by itself (at a random moment within an hour; if the computer was off, it catches up at the next start). The
update becomes active **at the next start**, so nothing changes while you work, and there is never an automatic
reboot. The previous version stays in the boot menu. `flake.lock` in `/etc/nixos` is updated as well; save it
with `git commit -am "Update software" && git push` if you want your other machines on the same versions.

| Command | What it does |
|---|---|
| `systemctl list-timers nixos-auto-update` | when the next automatic update runs |
| `journalctl -u nixos-auto-update` | what the last automatic update did |
| `sudo systemctl start nixos-auto-update` | run the automatic update now |

Turn it off for one config with `my.autoUpdate = false;` in `hosts/<config>/default.nix` (then `rebuild`).

**Adding software:** look up the package at <https://search.nixos.org/packages> and add its name to
`modules/apps.nix` (all machines) or to `environment.systemPackages` in `hosts/<config>/default.nix` (all machines with that config).
Then `rebuild`, `git commit` and `git push`.

**Flatpak** is on, with Flathub as the source (<https://flathub.org>). Flatpak apps are installed per machine
and are not part of the config; they are updated with `flatpak update`. In KDE Plasma (Full) you can also use
Discover.

**Logitech mice and keyboards:** when the installer finds a Logitech receiver or mouse (Unifying, Bolt,
Lightspeed), it turns on **Solaar** in that config (`my.logitech.enable = true;` in `hosts/<config>/default.nix`).
Solaar starts hidden at login and gets button rules in `~/.config/solaar/rules.yaml`: the **thumb wheel changes
the volume**. The rules come from `modules/logitech/rules.yaml` and are only copied when the file does not exist
yet, so changes you make in Solaar's rule editor are kept. A mouse connected only through Bluetooth is not seen
during installation; add `my.logitech.enable = true;` yourself and run `rebuild`. Log out and in once afterwards.

**Unfree software** (e.g. Google Chrome, Spotify, Steam) is refused unless it is listed in `my.allowedUnfree`, so
nothing unfree gets in unnoticed. To add one, put its name in that list in `modules/apps.nix` (all machines) or
add `my.allowedUnfree = [ "spotify" ];` to `hosts/<config>/default.nix` (one config). Firmware and CPU microcode
are always allowed.

**Trying software temporarily** (nothing is installed, no new generation): `nix run nixpkgs#gimp` starts it once,
`nix shell nixpkgs#gimp` makes it available in that terminal until you close it. For unfree software:
`NIXPKGS_ALLOW_UNFREE=1 nix shell --impure nixpkgs#spotify`. The downloads are removed by the weekly cleanup
(or right away with `nix-collect-garbage`).

---

## Part 1: Put the config on a USB stick

Only needed when the computer you install on has no internet. With internet, the menu downloads the config
from GitHub by itself (see 2.3 B).

You need **two USB sticks**: one for the NixOS installer (writing the installer erases that stick and makes it
read-only), and one for the config. Any stick will do for the config; it only needs a few hundred kilobytes.

1. On any computer, open <https://github.com/Fritz4all/nixos-config>, click the green **Code** button and choose
   **Download ZIP** (or download <https://github.com/Fritz4all/nixos-config/archive/refs/heads/main.zip> directly).
2. Plug in the config stick and extract the ZIP onto it. You get a folder `nixos-config-main` on the stick;
   leave the name as it is.
3. Eject the stick safely (the eject icon in the file manager).

---

## Part 2: Install a machine

### 2.1 Make the installer USB stick and start from it
Download the **Graphical ISO** of the newest NixOS release from <https://nixos.org/download> and write it to a
USB stick (e.g. with balenaEtcher). This config uses systemd-boot without Secure Boot, so turn **Secure Boot off**
in the BIOS/UEFI settings first.

Then plug in the stick, switch the computer on and **tap the boot menu key** right away (several times) until a
menu appears, and choose the USB stick (the entry that says **UEFI**). Usual keys:

| Brand | Boot menu | BIOS/UEFI settings (Secure Boot) |
|---|---|---|
| Acer | F12 (first enable "F12 Boot Menu" in the BIOS) | F2 or Del |
| ASUS | Esc (laptops), F8 (desktops) | F2 or Del |
| Dell | F12 | F2 |
| Gigabyte / AORUS | F12 | Del |
| HP | Esc, then F9 | Esc, then F10 |
| Lenovo ThinkPad | F12 (or Enter, then F12) | F1 (or Enter, then F1) |
| Lenovo IdeaPad / Yoga | F12, or the small Novo button | F2 (or Fn+F2), or the Novo button |
| MSI | F11 | Del |
| Microsoft Surface | hold Volume Down while pressing Power | hold Volume Up while pressing Power |
| Other / unknown | Esc, F12, F11, F10, F9 or F8 | F2 or Del |

Keys differ per model; the startup screen often shows the right one. Nothing happens? On laptops you may need to
hold **Fn** with the key; use a wired keyboard; or from Windows: hold **Shift** while clicking **Restart**, then
Troubleshoot → Advanced options → UEFI Firmware Settings.

### 2.2 Internet and terminal
In the live environment, pick your Wi-Fi network at the top right (or plug in a network cable).
Installing downloads packages, so it needs internet. Then open a terminal (Console).

### 2.3 Start the installation menu
Choose **one** of the two ways. The menu asks for administrator rights by itself.

**A. Straight from the config USB stick** (Part 1). Plug in the stick and click it once in the file manager
(Files), so it is mounted. Then, in the terminal:
```bash
bash /run/media/nixos/*/nixos-config*/install.sh
```
Leave the stick in until step 3 of the menu is done (the config is then copied to the new disk). The stick
cannot be chosen as the installation disk by accident: the menu shows it as "in use".

**B. From GitHub** (needs internet, no Git needed):
```bash
curl -L https://github.com/Fritz4all/nixos-config/archive/refs/heads/main.tar.gz | tar xz -C /tmp
bash /tmp/nixos-config-main/install.sh
```

### 2.4 The installation menu
The menu shows all steps. Steps that are done get a ✔, and ▶ points to the next step.

```
╭────────────────────────────────────────────────────────────╮
│               Install NixOS  ·  nixos-config               │
╰────────────────────────────────────────────────────────────╯
  UEFI        yes
  Memory      16 GB
  Internet    yes
  Repo        can be downloaded (https://github.com/Fritz4all/nixos-config.git)
  Desktop     (no config yet)

     ✔ 1  Internet connection    connected
  ▶  · 2  Prepare disk
     · 3  Fetch config
     · 4  Settings
     · 5  Install
     · 6  Reboot

  Enter = run step 2   1-6 = choose a step   a = run everything
  d = dry run on   i = info (versions)   r = refresh   q = quit
```

- **Enter** runs the next step, **a** runs all remaining steps one after another, a **number** runs that step
  (for example to redo one).
- **i** (info) shows the versions of the installed system (NixOS, kernel, desktop, Firefox, Chrome, Brave,
  Bitwarden, VLC); before installing it shows what is going to be installed.
- **d** (or `--dry-run`) is a dry run: everything is shown, nothing is changed. Handy to look around first.
- You can quit (**q**) and start the menu again at any time; it sees by itself which steps are done.
- At the start the menu checks that every tool it needs is there (git, curl, disk tools, `nixos-install`).
  If something is missing it **asks** whether it may install it. It is then installed only for this session
  (with `nix-shell`; nothing is added permanently). Said no? Press **t** in the menu to install later.

What each step does:

| Step | What happens |
|---|---|
| 1. Internet connection | Checks internet and whether your repo can be downloaded (the **Repo** line). No internet? It offers to set up Wi-Fi with `nmtui`. |
| 2. Prepare disk | Lists the disks (number, size, SSD/HDD, connection, model). The USB stick you booted from cannot be chosen. You type the disk's name to confirm, choose encryption (recommended, default yes) and type a passphrase twice (a typo? you simply get to try again). Creates an EFI partition of 1 GiB and a system partition with the rest, and mounts them on `/mnt`. **Everything on that disk is erased.** |
| 3. Fetch config | Puts the config in `/mnt/etc/nixos`. **Download config** (git clone from GitHub) when the repo can be downloaded, otherwise **Local config** (a copy of the folder from 2.3). It always says which one and why, and you can override it (`1` or `2`). |
| 4. Settings | Asks for your username and full name. Then it **recognises the machine type** (vendor and model, e.g. Lenovo ThinkPad T14 Gen 3) and shows **every config of that type** (e.g. a GNOME and a KDE Plasma variant); choose one, or make a **new variant** (then you choose the **desktop**, 1 = GNOME / 2 = KDE Plasma, and its **apps**, 1 = Full / 2 = Minimal, see below). Configs that do not fit the disk (encrypted or not) are shown but cannot be chosen. Then the **machine name**: the suggestion is `nix-<serial number>`, Enter takes it, or type another; it stays on this machine only. Last the **NixOS release** (looked up online; the newest stable one is recommended, `unstable` gives the newest software). Enter keeps the current value each time. |
| 5. Install | For a new variant it detects the hardware of this type and creates the config (in a virtual machine it also turns on the guest tools: shared clipboard and a screen that follows the window size); an existing config is used as it is. It runs `nixos-install` (10 to 30 minutes; a few minutes from your own ISO), writes the machine name to `/etc/hostname`, then asks for a root password and your user password (each typed twice; a typo means you simply try again), and shows the versions. |
| 6. Reboot | Remove the USB sticks. With encryption you first type the passphrase, then the login screen appears. |

Your Wi-Fi password is not copied from the live environment; enter it again after the first start.

If the installation fails halfway (e.g. a network error), choose step 5 again and choose **1 (Reuse)** for the
name. If you repartitioned the disk, choose **2 (Recreate)**; the script stops by itself when the hardware
configuration does not match the mounted disk.

### 2.5 Optional: save the new machine to GitHub
**Not needed for the machine to work.** Your new NixOS runs fine without this step. When you made a **new config**
in step 4 (a new machine type or variant), save it, so your next machines of that type can use it. The machine
name is never saved. Do it when you want one of these:

- **The same versions on your next machines:** the installation created `flake.lock` with the exact versions;
  without it, each new machine simply gets the newest versions at that moment.
- **A backup of this machine type's config** in `hosts/<config>/` (e.g. an extra program or another desktop);
  without it, a reinstallation just creates that directory again.
- **Changes you make on this machine** (in `/etc/nixos`) **shared with your other machines** via `git pull`.

If you only change the config elsewhere and push it to GitHub, you can skip this. Note: if you do change files in
`/etc/nixos` without pushing them, a later `git pull` may ask you to choose between your version and GitHub's.

**Step-by-step guide for beginners, with examples of what you will see and what to do when something goes
wrong: [docs/save-machine-to-github.md](docs/save-machine-to-github.md).** The short version:

The installer has made you the owner of `/etc/nixos`, so you can edit it without `sudo`.
In a terminal, logged in as yourself:

```bash
cd /etc/nixos
git config --global user.name "Your Name"
git config --global user.email "you@example.com"
gh auth login
```

Then, **if step 3 used Download config**:
```bash
git add -A
git commit -m "Add config for Lenovo ThinkPad T14"
git push
```

**If step 3 used Local config** (the USB stick) and the repo is on GitHub, first attach your copy to it:
```bash
git fetch origin
git reset --soft origin/main
git add -A
git commit -m "Add config for Lenovo ThinkPad T14"
git push -u origin main
```
(No `origin` yet? Add it first: `git remote add origin https://github.com/Fritz4all/nixos-config.git`.)

From now on you change the config in `/etc/nixos` and apply it with `rebuild`.

---

## Adding another machine

Same recipe as Part 2. In step 4:

- **Same type as a machine you installed before** (and saved, 2.5): the installer shows its configs; choose one.
  Nothing new is added to GitHub; only the machine name (e.g. `nix-<serial number>`) is new, and that stays on
  the machine.
- **A new machine type, or another desktop for a type:** choose "New variant"; save it afterwards (2.5).
- **Many machines of one type at once:** build an ISO for that type (see "Building your own ISO"): then each
  installation takes minutes and needs no internet.

Tip: first update the versions on an existing machine, so the new machine gets fresh packages
(see "Google Chrome cannot be downloaded" below):
```bash
nixup && cd /etc/nixos && git commit -am "Update versions" && git push
```
On the other machines: `cd /etc/nixos && git pull && rebuild`.

---

## Desktop: GNOME or KDE Plasma, Full or Minimal

Firefox, Google Chrome, Brave, Bitwarden and VLC are always installed. On top of that, each desktop comes in
two versions (chosen in step 4 of the menu):

| | Full (the desktop's usual set of apps) | Minimal (only what you need to work) |
|---|---|---|
| **GNOME** | Files, Terminal, Text Editor, System Monitor, Disks, Calculator, Image Viewer, Document Viewer, plus Calendar, Contacts, Maps, Weather, Clocks, Music, Video Player, Camera, Document Scanner, Characters, Fonts, Logs, Disk Usage, Help and more | Files, Terminal, Text Editor, System Monitor, Disks, Calculator, Image Viewer, Document Viewer (PDF) |
| **KDE Plasma** | Dolphin, Konsole, Kate, Gwenview, Okular, Ark, Spectacle, System Settings, System Monitor, plus Elisa (music), Discover (app store), Help, remote desktop, QR scanner, browser add-on | Dolphin (files), Konsole (terminal), Kate (text editor), Gwenview (images), Okular (PDF), Ark (archives), Spectacle (screenshots), System Settings, System Monitor |

To switch later:

1. In the config of the machine (`hosts/<config>/default.nix`), change `my.desktop = "plasma";` (or `"gnome"`)
   and/or `my.desktopApps = "minimal";` (or `"full"`). This changes it for every machine with that config;
   for one machine only, make a new variant instead. (`desktop` in `vars.nix` is only the default for new configs.)
2. Apply and reboot (`boot` is safer than `switch` when the login manager changes):
   ```bash
   rebuild-boot
   reboot
   ```
Your own apps (Firefox, Chrome, …) stay the same. The settings of each desktop are stored separately in your home folder.

---

## Building your own ISO

`build-iso.sh` builds your own installer ISO from what is on GitHub. Booting it, the installer starts by
itself; on a machine whose type is on the ISO, step 4 offers those configs and the installation needs **no
internet** and takes minutes. Run it on your own computer (e.g. Ubuntu), as yourself:

```bash
bash build-iso.sh
```

```
╭────────────────────────────────────────────────────────────╮
│               Build an ISO  ·  nixos-config                │
╰────────────────────────────────────────────────────────────╯
  Nix         2.34.8
  GitHub      main @ 1a2b3c4 … (3 configs, NixOS 26.05)
  Local repo  everything is on GitHub
  Free space  390G (ISOs go to ~/ISOs)

     1  ISO with all configs (3)        every config, installable offline
     2  ISO for one config               choose a machine type and variant
     3  Generic ISO                      installer + config, for new machine types
     4  Test an ISO in a VM              without network: is it really offline?
     5  Write an ISO to a USB stick
```

| Choice | What it does |
|---|---|
| 1. All configs | one ISO with every config in `hosts/`; all of them install offline |
| 2. One config | the configs are listed per machine type; choose one, or **a** = all variants of one type (e.g. GNOME and Plasma of the T14) |
| 3. Generic | only the installer and the config: small, for machine types that are not on GitHub yet (installing needs internet) |
| 4. Test in a VM | starts an ISO in virt-manager **without network**, so you see whether the offline installation really works |
| 5. USB stick | only USB sticks are offered (never your internal disk); you confirm by typing the stick's name |
| i | Nix version, free space, the ISOs you built, and moving old ones to the trash |

Good to know:

- **Always what is on GitHub:** the repo is downloaded fresh before each build. Changes you did not push are not
  on the ISO; the menu warns about them ("Local repo").
- **Nix is needed.** If it is not installed, the script asks whether it may install it (the official installer
  from nixos.org; it asks for your sudo password).
- **Size and time:** before building it shows how much is downloaded; an ISO with all software is roughly 5 to 8 GB
  and takes 20 to 40 minutes the first time. ISOs go to `~/ISOs`, with a `.sha256` checksum next to them.
- **Same versions:** the ISO contains the versions of the moment you built it (GitHub's `flake.lock` if there is
  one). After installing, the weekly automatic update brings them up to date. Rebuild the ISO now and then.
- **Offline needs the same username** as in `vars.nix` on GitHub; with another username the installation
  downloads the parts that differ.
- **Google Chrome:** its license does not allow sharing it, so an ISO with Chrome is for **your own use** only.
  Do not put it on GitHub or a public website.

---

## Keeping secrets out

This repo is **public**: everyone can read it, and anything that was ever committed stays in the history, even
after you delete it. So passwords, keys and tokens never go in here. Passwords belong in Bitwarden; your user
password is set during installation and is not stored in the repo. Three safeguards help:

1. **`.gitignore`** keeps typical secret files out of Git (`.env`, `secrets/`, `*.key`, `*.pem`, `id_ed25519`,
   files with "password" in the name, …).
2. **`.githooks/pre-commit`** checks every commit and **blocks** it when something looks like a password
   (`password = "…"`), a password hash, a private key or a token. It is turned on automatically on new machines
   (by step 3 of the menu). On a computer where you cloned the repo yourself, turn it on once with:
   ```bash
   git config core.hooksPath .githooks
   ```
   Check the whole repo at any time with `bash .githooks/pre-commit --all`.
3. **GitHub push protection** is turned on for the repo: GitHub itself refuses a push that contains a
   recognisable token or key.

Is something blocked that is really not a secret? Add the comment `allow-secret` on that line.
Need a real secret in the config one day (e.g. a Wi-Fi password)? Ask for a secrets tool such as sops-nix or
agenix: those store secrets encrypted, so only your machines can read them.

---

## New NixOS releases

NixOS releases a new version twice a year (at the end of May and of November). Nothing changes by itself:
your machines stay on the release in `flake.nix`, and `nixup` only installs updates within that release.
An older release keeps getting security updates for about a month after the next one comes out, so upgrade
within that month:

1. Show and choose the release (the newest stable one is marked as recommended):
   ```bash
   nixos-release
   ```
2. Apply it and reboot:
   ```bash
   rebuild-boot
   reboot
   ```
3. Save it, so your other machines follow (they run `git pull && rebuild-boot`):
   ```bash
   cd /etc/nixos && git commit -am "Upgrade NixOS" && git push
   ```

Never change `system.stateVersion` in `hosts/<config>/`: it stays the release the config was first installed
with. If something does not work after an upgrade, choose the previous version in the boot menu.

---

## Troubleshooting

- **Repo line says "cannot be downloaded":** the repo is not on GitHub yet, it is private, or `repoUrl` in
  `vars.nix` is wrong. The menu then copies the config locally, which works fine. Check the address in a browser.
- **"No internet connection" in step 5:** `nixos-install` has to download packages. Connect (step 1) and choose
  step 5 again (name: 1, Reuse).
- **`path '.../hardware-configuration.nix' does not exist` or "not tracked by Git":** flakes only see files Git
  knows about. Run `git add -A` in `/etc/nixos` (or `/mnt/etc/nixos` in the installer).
- **Google Chrome cannot be downloaded (404 or hash mismatch):** Google only keeps the newest version. Run
  `nix flake update` (in the installer: `nix --extra-experimental-features 'nix-command flakes' flake update --flake /mnt/etc/nixos`)
  and try again.
- **`attribute '...' missing` for a package or option:** the name changed in a newer release. Look up the new
  name at <https://search.nixos.org>, fix the file and try again. This happens before anything is installed.
- **Wrong keyboard at the passphrase prompt or after login:** change `keyboard` in `vars.nix`.
- **The computer does not start from the USB stick:** check that UEFI boot is on and Secure Boot is off.
- **Hibernate does not work:** this setup uses zram as swap, so only normal suspend (closing the lid) works.

---

## Details

### Using the scripts without the menu
The menu only calls these scripts; you can also run them yourself, in this order:
```bash
bash scripts/prepare-disk.sh                     # --dry-run available
bash scripts/fetch-config.sh                     # options below
bash /mnt/etc/nixos/scripts/settings.sh          # continues with install-system.sh by itself
```

`fetch-config.sh` options:

| Option | Effect |
|---|---|
| `--download` | always Download config |
| `--local` | always Local config |
| `--url URL` | another Git URL for Download config (default: `origin`, else `repoUrl` in `vars.nix`) |
| `--source DIR` | use a specific directory for Local config |
| `--yes` | ask nothing, use the automatic choice |
| `--dry-run` | only show what would happen |

If `/mnt/etc/nixos` already contains something, it is renamed to `nixos.bak-…` (after confirmation); nothing is deleted.

### Partitioning by hand
```bash
lsblk                                  # find your disk, e.g. nvme0n1 or sda
DISK=/dev/nvme0n1                      # CHANGE to your disk
PART1="${DISK}p1"; PART2="${DISK}p2"   # for sda/vda: PART1="${DISK}1"; PART2="${DISK}2"

parted -s "$DISK" -- mklabel gpt
parted -s "$DISK" -- mkpart ESP fat32 1MiB 1GiB
parted -s "$DISK" -- set 1 esp on
parted -s "$DISK" -- mkpart nixos 1GiB 100%

mkfs.fat -F 32 -n BOOT "$PART1"
cryptsetup luksFormat "$PART2"         # type YES (capitals) and choose a strong passphrase
cryptsetup open "$PART2" cryptroot
mkfs.ext4 -L nixos /dev/mapper/cryptroot

mount /dev/mapper/cryptroot /mnt
mkdir -p /mnt/boot
mount -o umask=077 "$PART1" /mnt/boot
```
