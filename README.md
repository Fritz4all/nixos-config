# NixOS configuration (flake) for all my machines

One repo for all machines: GNOME as the desktop (switching to KDE Plasma is one line), with Firefox,
Google Chrome, Brave, Bitwarden and VLC. Based on NixOS 26.05 "Yarara".

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
├── CLAUDE.md        notes for the AI assistant (Claude Code); not needed for installing
├── .githooks/       blocks commits that contain passwords, keys or tokens (see "Keeping secrets out")
└── .gitignore       tells Git which files to leave out (build results, test files, secret files)
```

**Simple rule:** upload the whole folder to GitHub, and copy the whole folder to the USB stick.
`docs/` and `CLAUDE.md` are small and harmless; you may leave them off the USB stick if you like.

| Part | What it is |
|---|---|
| `vars.nix` | your choices: username, desktop, language, time zone, keyboard, GitHub address (`repoUrl`) |
| `modules/common.nix` | basics for every machine: boot, network, sound, printing, Bluetooth, user, basic programs |
| `modules/apps.nix` | Firefox, Chrome, Brave, Bitwarden, VLC |
| `modules/desktop/` | `gnome.nix` and `plasma.nix`; chosen in `vars.nix` |
| `hosts/_template/` | template for a new machine |
| `hosts/<name>/` | one directory per machine (created by the installer): its hardware and `stateVersion` |
| `flake.nix` | pins NixOS 26.05 and turns every directory in `hosts/` into a machine automatically |
| `flake.lock` | records the exact versions, so all machines get the same software |
| `scripts/menu.sh` | the installation menu; runs the scripts below in the right order |
| `scripts/prepare-disk.sh` | choose, partition, encrypt and mount the disk |
| `scripts/fetch-config.sh` | put the config on the new disk: download from GitHub, or copy locally |
| `scripts/setup-user.sh` | ask for your username and write it to `vars.nix` |
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

Only needed when the computer you install on has no internet. With internet, the config is downloaded
from GitHub (see 2.3 B). How the repo was put on GitHub: [docs/github-setup.md](docs/github-setup.md).

You need **two USB sticks**: one for the NixOS installer (writing the installer erases that stick and makes it
read-only), and one for the config. Any stick will do for the config; it only needs a few hundred kilobytes.

1. Plug in the config stick on your current computer.
2. Open the file manager (Files), go to `Documents/Claude` and drag the whole `nixos-config` folder onto the stick.
3. Eject the stick safely (the eject icon in the file manager).

---

## Part 2: Install a machine

### 2.1 Make the installer USB stick
Download the **Graphical ISO** of NixOS 26.05 from <https://nixos.org/download> and write it to a USB stick
(e.g. with balenaEtcher). Turn **Secure Boot off** in the BIOS: this config uses systemd-boot without Secure Boot.
Start the computer from the stick (usually F12, F2 or Esc during startup) and choose the stick under UEFI.

### 2.2 Internet and terminal
In the live environment, pick your Wi-Fi network at the top right (or plug in a network cable).
Installing downloads packages, so it needs internet. Then open a terminal (Console).

### 2.3 Get the config folder
Choose **one** of the two ways.

**A. From the USB stick.** Plug in the config stick and click it once in the file manager (Files), so it is
mounted. Then, in the terminal:
```bash
sudo -i
cp -r /run/media/nixos/*/nixos-config /root/
```

**B. From GitHub** (needs internet, no Git needed):
```bash
sudo -i
curl -L https://github.com/Fritz4all/nixos-config/archive/refs/heads/main.tar.gz | tar xz -C /root
mv /root/nixos-config-main /root/nixos-config
```

### 2.4 Run the installation menu
```bash
bash /root/nixos-config/scripts/menu.sh
```

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
     · 4  Set up user
     · 5  Install
     · 6  Show versions
     · 7  Reboot

  Enter = run step 2   1-7 = choose a step   a = run everything
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
| 2. Prepare disk | Lists the disks (number, size, SSD/HDD, connection, model). The USB stick you booted from cannot be chosen. You type the disk's name to confirm, choose encryption (recommended, default yes) and type a passphrase twice. Creates an EFI partition of 1 GiB and a system partition with the rest, and mounts them on `/mnt`. **Everything on that disk is erased.** |
| 3. Fetch config | Puts the config in `/mnt/etc/nixos`. **Download config** (git clone from GitHub) when the repo can be downloaded, otherwise **Local config** (a copy of the folder from 2.3). It always says which one and why, and you can override it (`1` or `2`). |
| 4. Set up user | Asks for your username and full name and writes them to `vars.nix`. Enter keeps the current value. |
| 5. Install | Asks for the machine name (e.g. `laptop`), detects the hardware, runs `nixos-install` (10 to 30 minutes), asks for a root password and your user password, and shows the versions. |
| 6. Show versions | Shows the versions again: NixOS, kernel, systemd, desktop, Firefox, Chrome, Brave, Bitwarden, VLC. |
| 7. Reboot | Remove the USB sticks. With encryption you first type the passphrase, then the login screen appears. |

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

## Switching the desktop: GNOME and KDE Plasma

1. For all machines: set `desktop = "plasma";` in `vars.nix`.
   For one machine: add `my.desktop = "plasma";` to `hosts/<name>/default.nix`.
2. Apply and reboot (`boot` is safer than `switch` when the login manager changes):
   ```bash
   rebuild-boot
   reboot
   ```
3. Back to GNOME: the same steps with `"gnome"`.

Your apps stay the same. The settings of each desktop are stored separately in your home folder.

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

**Next NixOS release:** 26.11 comes out at the end of November. To upgrade, change `nixos-26.05` into
`nixos-26.11` in `flake.nix`, run `nixup`, commit and push. Never change the `stateVersion` in `hosts/`.

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
