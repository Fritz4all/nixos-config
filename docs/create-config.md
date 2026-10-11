# create-config.sh – making a config from a machine's hardware

`create-config.sh` (in the main folder, next to `install.sh` and `build-iso.sh`) makes a config for the
**type** of the machine it runs on, from that machine's hardware. It puts the config next to the script, in
`hosts/<config>/`, so you can push it to GitHub. From then on every machine of that type can be installed with
it, also **offline** from an ISO made by `build-iso.sh`. Nothing is installed or changed on the machine itself.

Use it when you have a machine of a new type and want its config on GitHub before installing, for example to
build an ISO for ten laptops of that type. (The installer can also make a config during an installation, in
step 4, "New variant"; this script does the same without installing.) Back to the [README](../README.md).

---

## Where to run it

On the machine whose hardware you want (the hardware detection looks at the machine it runs on):

| Where | What you need |
|---|---|
| The NixOS installer (live USB) | nothing extra: everything is there. Copy the folder to a writable place first (see below). |
| An installed NixOS | nothing extra; run it in `/etc/nixos` or in a copy of the repo |
| Another Linux, e.g. Ubuntu | Nix (see [Building your own ISO](../README.md#building-your-own-iso) for installing it); the script runs the NixOS hardware detection through Nix |

The folder must be **writable** and preferably a **git clone** of the repo (then the script can push for you).
A USB stick or ISO is read-only; copy the folder first:

```bash
git clone https://github.com/Fritz4all/nixos-config.git ~/nixos-config
cd ~/nixos-config
```

## Running it

```bash
bash create-config.sh
```

It runs as your normal user; root is not needed.

## What it does, step by step

1. **Shows this machine**, for example:
   ```
   This machine: Dell Precision 7540 (Laptop)
   Machine type: dell-precision-7540
     existing config: dell-precision-7540-gnome-minimal    GNOME (minimal), encrypted
   ```
   Vendor, model and kind come from the firmware, the same way the installer reads them, so the installer
   will recognise this type later. Existing configs of this type are listed, so you do not make a double one.

2. **Asks four questions** (Enter takes the value between brackets):

   | Question | Choices | Default |
   |---|---|---|
   | Desktop | 1 = GNOME, 2 = KDE Plasma | `desktop` in `vars.nix` (GNOME) |
   | Apps | 1 = Full (the desktop's usual set), 2 = Minimal (only what you need to work) | Minimal |
   | Disk encryption | will the machines of this type be installed with an encrypted disk? | yes |
   | Name of the config | e.g. `dell-precision-7540-gnome-minimal` | `<type>-<desktop>[-minimal][-unencrypted]` |

   Encryption is part of the config: in step 2 of the installer you must later make the same choice, otherwise
   the installer shows the config as "does not fit this disk".

3. **Detects the hardware** (`nixos-generate-config --no-filesystems`: drivers, CPU, firmware, but no disks;
   disks are found by name, so the config fits every machine of the type) and **creates the config** with
   `scripts/new-host.sh`:

   | File | Contents |
   |---|---|
   | `hosts/<config>/default.nix` | desktop, apps, disk encryption, NixOS release (`stateVersion`), detected extras (GPU, Logitech, VM) |
   | `hosts/<config>/machine.nix` | vendor, model and kind; the installer recognises the type by it |
   | `hosts/<config>/hardware-configuration.nix` | the detected hardware |
   | `hosts/README.md` | the overview of all configs, updated |

   On top of that, automatically: in a **virtual machine** the guest tools (shared clipboard, screen size), and
   with a **Logitech receiver or mouse** attached Solaar with the button rules, and the **video cards** (the standard
   NixOS hardware detection leaves them out): Intel → video acceleration, NVIDIA → the NVIDIA driver, and on a
   laptop with two GPUs PRIME offload (start a program on the NVIDIA card with `nvidia-offload <program>`).
   Also: a **fingerprint reader** (only readers that work on NixOS, listed in `scripts/fingerprint-ids.txt`; Dell's
   ControlVault readers get Dell's driver), a **smartcard reader**, **Thunderbolt**, **thermald** on laptops with an
   Intel processor, **rotation/light sensors**, and the **[nixos-hardware](https://github.com/NixOS/nixos-hardware)
   profile** of the model when there is one (this needs internet; without it the script says so and continues).
   Each found item is added as a short block with a comment to `default.nix`, so you can see and change it.
   No machine name or serial number is stored.

4. **Checks the config with Nix**: "OK: the config is valid."

5. **Offers to save it to GitHub** (`git commit` + `git push`). Answer **Y** and the config is online: the
   installer and `build-iso.sh` can use it right away. Pushing needs you to be logged in to GitHub once
   (`gh auth login`, see [save-machine-to-github.md](save-machine-to-github.md), step 4).

## Options

All questions can also be answered on the command line, e.g. for a script:

| Option | Meaning |
|---|---|
| `--desktop gnome` / `--desktop plasma` | desktop, without asking |
| `--apps minimal` / `--apps full` | apps, without asking |
| `--encrypted yes` / `--encrypted no` | disk encryption, without asking |
| `--name NAME` | name of the config, without asking |
| `--no-push` | do not offer to save it to GitHub |
| `--dry-run` | only show what would happen; nothing is created |
| `-h` | short help |

Example: a KDE Plasma config with all apps, without questions and without pushing:
```bash
bash create-config.sh --desktop plasma --apps full --encrypted yes --name lenovo-thinkpad-t14-gen-3-plasma --no-push
```

## After creating it

- **Install a machine of this type:** in step 4 of the installer the config is offered for this type.
- **Install many machines offline:** `bash build-iso.sh` → 2 → choose the config → write the ISO to a USB stick.
- **Change the config:** edit `hosts/<config>/default.nix` (e.g. extra programs), commit and push. All machines
  with this config get the change at their next `git pull && rebuild`.
- **Remove a config you made by mistake** (before pushing): delete its folder `hosts/<config>/` and run
  `bash scripts/hosts-overview.sh` to update `hosts/README.md`.

## Adding a nixos-hardware profile by hand

The script looks for a profile with the same name as the machine type (with `intel`/`amd` and `nvidia` where
they apply). Model names do not always match, so check the list at <https://github.com/NixOS/nixos-hardware>
(the table in its README). When you find your model, e.g. `dell-latitude-7490`, put it in the `imports` of
`hosts/<config>/default.nix`, and make sure `nixos-hardware` is in the first line:

```nix
{ config, lib, pkgs, nixos-hardware, ... }:
{
  imports = [
    ./hardware-configuration.nix
    ./machine.nix
    nixos-hardware.nixosModules.dell-latitude-7490
  ];
```

The profile wins over the video card settings that the script detected. Check it with
`nix eval --no-write-lock-file path:.#nixosConfigurations.<config>.config.system.build.toplevel.drvPath`.

## When something goes wrong

| Message | What to do |
|---|---|
| `Cannot write to …/hosts (read-only USB stick or ISO?)` | Copy or clone the folder to your home folder first (see "Where to run it"). |
| `nixos-generate-config and Nix are both missing` | Run it in the NixOS installer, or install Nix first. |
| `That config exists already` | Choose another name, or use the existing config. |
| `Warning: Nix could not evaluate the new config` | Run the command it shows to see the details. |
| `Pushing failed (not logged in?)` | Run `gh auth login`, then `git push` in the folder. |
