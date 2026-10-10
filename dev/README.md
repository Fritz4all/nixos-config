# dev/: testing tools

Nothing in this directory is needed to install a machine. It is for checking changes before you use them.
Everything here works on any Linux machine (for example Ubuntu); NixOS is not needed.

| File | What it does |
|---|---|
| `test-scripts.sh` | Tests the installation menu and scripts in 8 scenarios (full installation, download vs. local copy, repo status, no internet, warnings). No disk is touched: the installer commands are replaced by the fake versions in `stubs/`. Takes a few seconds. |
| `demo-menu.sh` | Opens the installation menu in dry-run mode with fake disks, to click through it safely. |
| `check-config.sh` | Checks that the NixOS configuration evaluates (GNOME and Plasma) and shows the package versions. `--build` builds the complete system (~11 GB download), `--vm` starts a VM with the desktop. Needs Nix or nix-portable (see the top of the script). |
| `testvm/` | The fake machine used by `check-config.sh`: test hardware, plus automatic login for the VM (user password in the VM: see `testvm/default.nix`). |
| `stubs/` | Fake versions of `lsblk`, `parted`, `nixos-install`, `curl`, `git`, … used by the two scripts above. |

Typical use after changing something:
```bash
bash dev/test-scripts.sh          # after changing a script
bash dev/check-config.sh          # after changing a .nix file
```

Useful environment variables for the stubs: `STUB_OFFLINE=1` (no internet), `STUB_REPO=0` (the repo can be
downloaded; default: it cannot).
