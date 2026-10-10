# NixOS config for all my machines

Flake configuration for NixOS 26.05 ("Yarara"), meant to be installed on several machines.

## Language
- **Everything in the project is English**: scripts (messages, prompts, comments), README files, Nix comments,
  this file.
- The user talks to you in Dutch or English; answer in the language they use.
- Yes/no prompts in scripts show `[Y/n]` but also accept `j` (Dutch "ja").

## Goal
- One repo for all machines; per machine only a directory in `hosts/`.
- Software: Firefox, Google Chrome, Brave, Bitwarden, VLC (plus `gh` for pushing to GitHub).
- Desktop: GNOME, easy to switch to KDE Plasma (`desktop` in `vars.nix`, or `my.desktop` per machine).
- Installation fully via scripts in the NixOS installer, driven by `scripts/menu.sh`; README describes the steps.
- The repo is not on GitHub yet (2026-10-10). `repoUrl` in `vars.nix` stays empty until the user uploads it.

## Layout
- Needed for installing (on GitHub and the USB stick): `flake.nix`, `flake.lock` (after first install),
  `vars.nix`, `hosts/`, `modules/`, `scripts/`, `README.md`.
- Not needed for installing: `dev/` (test tools), `CLAUDE.md`, `.gitignore`.
- `flake.nix`: pins nixpkgs `nixos-26.05`, turns every directory in `hosts/` (except `_…`) into a system.
- `vars.nix`: username (placeholder `changeme`), full name, `repoUrl`, desktop, language, time zone, keyboard.
  Scripts read/write its simple `name = "value";` lines with sed, so keep that format.
- `modules/`: `common.nix` (base), `apps.nix` (programs), `desktop/` (gnome.nix, plasma.nix).
- `hosts/_template/` is the template; `hosts/<name>/` is created by `scripts/new-host.sh`.
- `scripts/`, in installation order:
  1. `prepare-disk.sh`: choose disk, partition, LUKS, format, mount on /mnt (`--dry-run`)
  2. `fetch-config.sh`: config to /mnt/etc/nixos; "Download config" (git clone) when the repo can be downloaded,
     else "Local config" (copy). URL order: `--url`/`NIXOS_CONFIG_URL`, `origin` of the running copy, `repoUrl`.
     Reachability: http(s) via `curl <url>/info/refs?service=git-upload-pack` (works without git), else
     `git ls-remote`. A local copy gets `origin` = the URL when one is known.
  3. `setup-user.sh`: asks username and full name, writes `vars.nix`, continues with install.sh
  4. `install.sh`: asks machine name, `new-host.sh`, `nixos-install --flake`, password, then `versions.sh`
  - `menu.sh`: installation menu calling the steps above (plus internet/Wi-Fi + repo status, versions, reboot).
    Status per step is derived from /mnt (mounted, config, vars.nix, profile link). Enter = next step,
    `a` = everything. Calls scripts with `INSTALL_MENU=1` (no "next step" text), setup-user with
    `--no-continue`, install with `--no-reboot`. Step exit codes: 0 done, 1 failed, 2 skipped.
  - `new-host.sh` (create hosts/<name>) and `versions.sh` (show versions, also as the command `versions`)
- `dev/`: `test-scripts.sh` (8 stub scenarios), `demo-menu.sh`, `check-config.sh` (flake check/eval,
  `--build`, `--vm`), `testvm/` (fake host), `stubs/` (fake installer commands).

## Conventions
- Never change the `stateVersion` of an existing machine when upgrading.
- Scripts: `set -euo pipefail`, English messages, `--dry-run` where possible. Watch out for `set -e` with
  `var="$(function)"`: a function returning 1 stops the script (an earlier bug in versions.sh).
- After changing scripts: `bash -n scripts/*.sh` and `bash dev/test-scripts.sh`.
  After changing Nix files: `bash dev/check-config.sh` (needs Nix or `NIX_PORTABLE=<path>`).
- `/mnt/nix/var/nix/profiles/system` links to `/nix/store/…`, which does not exist from the installer's point of
  view: test it with `-L`, not `-e`.

## What has and has not been tested
- **Really built on 2026-10-10** (Ubuntu with nix-portable, nixpkgs nixos-26.05 rev 7c8764b of 2026-10-08) with the
  test machine: `nix flake check` passes; GNOME and Plasma evaluate without errors or warnings; the complete
  system builds for both. Versions then: GNOME 50.5, Plasma 6.6.6, kernel 6.18.55, systemd 260.5,
  Firefox 157.0.1, Chrome 155.0.8059.39, Brave 1.96.61, Bitwarden 2026.8.0, VLC 3.0.24, Nix 2.34.8.
  A GNOME VM was started (`system.build.vm`; GNOME autologin needs getty@tty1/autovt@tty1 disabled).
- `versions.sh` tested against the really built system (`nix-instantiate --raw` was replaced: older Nix lacks it).
- All scripts and the menu tested with stubs (`dev/test-scripts.sh`, all 8 pass), including the repo check
  against real GitHub URLs (existing repo → 0, missing repo → curl exit 22).
- The "attach a local copy to GitHub" flow in README 3.5 (`git fetch` + `git reset --soft origin/main` on an
  unborn branch) was tested with real git.
- **Not tested:** real partitioning and installation on hardware (prepare-disk.sh, nixos-install), and the
  upload to GitHub itself.

## Possible next steps
- Home Manager for user settings (GNOME settings, dotfiles).
- Secure Boot (lanzaboote) and/or declarative disk layout with disko.
- Hibernate (now zram swap, so no suspend-to-disk).
