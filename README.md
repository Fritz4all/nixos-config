# NixOS configuration (flake) for all my machines

One repo for all machines: GNOME or KDE Plasma as the desktop, each in a Full or a Minimal version (chosen
during installation, switching later is one line), with Firefox, Google Chrome, Brave, Bitwarden and VLC. The NixOS release is chosen during installation
from the releases that are available at that moment, and can be changed later with one command (`nixos-release`).

Installing a machine comes down to: boot the NixOS installer, get this folder, run
`bash scripts/menu.sh` and follow the menu.

---

## What is in this folder

```
nixos-config/
├── README.md        this guide
├── flake.nix        ┐
├── flake.lock       │  THE CONFIGURATION AND THE INSTALLER
├── vars.nix         │  Needed on GitHub and on the USB stick.
├── hosts/           │  (flake.lock appears after the first installation)
├── modules/         │
├── scripts/         ┘
│
├── docs/            extra manuals (e.g. how the repo was put on GitHub); not needed for installing
├── .githooks/       blocks commits that contain passwords, keys or tokens (see "Keeping secrets out")
└── .gitignore       tells Git which files to leave out (build results, test files, secret files)
```

Everything you need is on GitHub; Part 1 explains how to put it on a USB stick.

| Part | What it is |
|---|---|
| `vars.nix` | your choices: username, desktop and its apps (Full/Minimal), language, time zone, keyboard, GitHub address (`repoUrl`) |
| `modules/common.nix` | basics for every machine: boot, network, sound, printing, Bluetooth, user, basic programs |
| `modules/apps.nix` | Firefox, Chrome, Brave, Bitwarden, VLC |
| `modules/desktop/` | `gnome.nix` and `plasma.nix`, each in a Full and a Minimal version; chosen in `vars.nix` |
| `hosts/_template/` | template for a new machine |
| `hosts/<name>/` | one directory per machine (created by the installer): its hardware and `stateVersion` |
| `flake.nix` | sets the NixOS release and turns every directory in `hosts/` into a machine automatically |
| `flake.lock` | records the exact versions, so all machines get the same software |
| `scripts/menu.sh` | the installation menu; runs the scripts below in the right order |
| `scripts/prepare-disk.sh` | choose, partition, encrypt and mount the disk |
| `scripts/fetch-config.sh` | put the config on the new disk: download from GitHub, or copy locally |
| `scripts/setup-user.sh` | ask for your username, full name, desktop, Full/Minimal apps and NixOS release |
| `scripts/release.sh` | show the available NixOS releases and choose one (later also as the command `nixos-release`) |
| `scripts/install.sh` | ask for the machine name, run `nixos-install`, set your password, show the versions |
| `scripts/new-host.sh` | create `hosts/<name>/` (used by `install.sh`) |
| `scripts/versions.sh` | show the versions of the system and your programs (later also as the command `versions`) |

Shared = everything in `vars.nix` and `modules/`. Different per machine = only its directory in `hosts/`.

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
bash /run/media/nixos/*/nixos-config*/scripts/menu.sh
```
Leave the stick in until step 3 of the menu is done (the config is then copied to the new disk). The stick
cannot be chosen as the installation disk by accident: the menu shows it as "in use".

**B. From GitHub** (needs internet, no Git needed):
```bash
curl -L https://github.com/Fritz4all/nixos-config/archive/refs/heads/main.tar.gz | tar xz -C /tmp
bash /tmp/nixos-config-main/scripts/menu.sh
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
  d = dry run on   r = refresh   q = quit
```

- **Enter** runs the next step, **a** runs all remaining steps one after another, a **number** runs that step
  (for example to redo one).
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
| 4. Settings | Asks for your username, full name, **desktop** (1 = GNOME, 2 = KDE Plasma), the **apps** that come with it (1 = Full, 2 = Minimal; see below) and the **NixOS release**. The releases are looked up online, so new releases appear by themselves; the newest stable one is marked as recommended, and `unstable` is offered for the newest software. Enter keeps the current value each time. |
| 5. Install | Asks for the machine name (e.g. `laptop`), detects the hardware, runs `nixos-install` (10 to 30 minutes), then asks for a root password and your user password (each typed twice; a typo means you simply try again), and shows the versions. |
| 6. Reboot | Remove the USB sticks. With encryption you first type the passphrase, then the login screen appears. |

Your Wi-Fi password is not copied from the live environment; enter it again after the first start.

If the installation fails halfway (e.g. a network error), choose step 5 again and choose **1 (Reuse)** for the
name. If you repartitioned the disk, choose **2 (Recreate)**; the script stops by itself when the hardware
configuration does not match the mounted disk.

### 2.5 After the first start: save the new machine to GitHub
The installation created `hosts/<name>/` and `flake.lock`. Save them, so other machines get the same versions.
In a terminal, logged in as yourself:

```bash
sudo chown -R $USER:users /etc/nixos
cd /etc/nixos
git config --global user.name "Your Name"
git config --global user.email "you@example.com"
gh auth login
```

Then, **if step 3 used Download config**:
```bash
git add -A
git commit -m "Add machine laptop"
git push
```

**If step 3 used Local config** (the USB stick) and the repo is on GitHub, first attach your copy to it:
```bash
git fetch origin
git reset --soft origin/main
git add -A
git commit -m "Add machine laptop"
git push -u origin main
```
(No `origin` yet? Add it first: `git remote add origin https://github.com/Fritz4all/nixos-config.git`.)

From now on you change the config in `/etc/nixos` and apply it with `rebuild`.

---

## Adding another machine

Same recipe as Part 2, with a **new, unique name** in step 5 (e.g. `workpc`). Then save it (2.5).
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

1. For all machines: set `desktop = "plasma";` (or `"gnome"`) and/or `desktopApps = "minimal";` (or `"full"`)
   in `vars.nix`. For one machine: add `my.desktop = "plasma";` and/or `my.desktopApps = "minimal";` to
   `hosts/<name>/default.nix`.
2. Apply and reboot (`boot` is safer than `switch` when the login manager changes):
   ```bash
   rebuild-boot
   reboot
   ```
Your own apps (Firefox, Chrome, …) stay the same. The settings of each desktop are stored separately in your home folder.

---

## Daily use

| Command | What it does |
|---|---|
| `rebuild` | apply changes in `/etc/nixos` right away |
| `rebuild-boot` | apply at the next reboot (safe for big changes) |
| `nixup` | update all packages (`nix flake update`) and apply |
| `versions` | show the versions of NixOS, kernel, desktop and your programs |
| `sudo nixos-rebuild switch --rollback` | go back to the previous version |

Something broken after an update? Choose an older version in the boot menu.

**Adding software:** look up the package at <https://search.nixos.org/packages> and add its name to
`modules/apps.nix` (all machines) or to `environment.systemPackages` in `hosts/<name>/default.nix` (one machine).
Then `rebuild`, `git commit` and `git push`.

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

Never change `system.stateVersion` in `hosts/<name>/`: it stays the release the machine was first installed
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
bash /mnt/etc/nixos/scripts/setup-user.sh        # continues with install.sh by itself
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
