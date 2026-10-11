# Saving a machine's setup to GitHub – step by step

You installed a machine with the installer, and now you want its setup on GitHub: the config of its machine type
(`hosts/<config>/`, e.g. `hosts/lenovo-thinkpad-t14-gen-3-gnome/`, when step 4 made a new one), the exact versions
(`flake.lock`) and any changes you made. The machine name is never saved: it stays on the machine. This guide assumes nothing;
just follow the steps. Back to the [README](../README.md).

> **Is this needed?** No. The machine works fine without it. Do it when you want the same versions on your
> other machines, a backup of this machine's settings, or to share changes you made on this machine.
> See [README, 2.5](../README.md#25-optional-save-the-new-machine-to-github).

---

## Step 1: Open a terminal

On the installed machine (not in the installer):

- **GNOME:** press the Super key (Windows key), type `Console` and press Enter.
- **KDE Plasma:** open the menu at the bottom left, type `Konsole` and press Enter.

The line in the terminal starts with something like `[roy@nix-pf3abc12:~]$`. That is where you type the commands below.
Type each command, then press Enter, and wait until it is finished before typing the next one.

## Step 2: Go to the config folder

```bash
cd /etc/nixos
```

Nothing is printed; the line now ends with `/etc/nixos]$`.

## Step 3: Only the first time on this machine: tell Git who you are

Use your own name. For the e-mail address, use the private address GitHub gives you, so your real address is not
published: on github.com click your picture (top right) → **Settings** → **Emails**; it looks like
`12345678+Fritz4all@users.noreply.github.com`.

```bash
git config --global user.name "Your Name"
```
```bash
git config --global user.email "12345678+Fritz4all@users.noreply.github.com"
```

## Step 4: Only the first time on this machine: log in to GitHub

```bash
gh auth login
```

Answer the questions with the arrow keys and Enter:

| Question | Answer |
|---|---|
| Where do you use GitHub? | **GitHub.com** |
| What is your preferred protocol for Git operations? | **HTTPS** |
| Authenticate Git with your GitHub credentials? | **Yes** |
| How would you like to authenticate GitHub CLI? | **Login with a web browser** |

It shows a code of 8 characters (like `ABCD-1234`). Press Enter: a browser opens. Log in as Fritz4all, type the code
and click **Authorize**. Back in the terminal you see `Logged in as Fritz4all`.

No browser opens? Open <https://github.com/login/device> yourself and type the code there.

## Step 5: Look at what changed

```bash
git status
```

You see a list, for example:

```
Changes to be committed:
        new file:   flake.lock
        new file:   hosts/README.md
        new file:   hosts/lenovo-thinkpad-t14-gen-3-gnome/default.nix
        new file:   hosts/lenovo-thinkpad-t14-gen-3-gnome/hardware-configuration.nix
        new file:   hosts/lenovo-thinkpad-t14-gen-3-gnome/machine.nix
        modified:   vars.nix
```

- `hosts/lenovo-thinkpad-t14-gen-3-gnome/` – the new config for this machine type (only when step 4 made a new one)
- `hosts/README.md` – the overview of all configs that GitHub shows
- `flake.lock` – the exact versions installed on it
- `vars.nix` – your username, desktop and the other choices from step 4 of the installer

There are no passwords in these files. A safety check runs anyway in the next step.

## Step 6: Save the changes (commit)

```bash
git add -A
```
```bash
git commit -m "Add config for Lenovo ThinkPad T14"
```

Describe what you add; you see a short summary like `5 files changed`.

Only `flake.lock` changed (you used an existing config)? Then saving is optional: it only records the versions.

**"Commit blocked: the lines above look like passwords, keys or tokens"?** The safety check found something that
looks secret. Remove it from the file that is mentioned, then do this step again.

## Step 7: Upload (push)

Which command you need depends on how step 3 of the installer got the config. You can see it in the lines it
printed: **Download config** or **Local config**. Not sure? Try A first.

**A. Download config** (the normal case, with internet):
```bash
git push
```

**B. Local config** (installed from the USB stick). Your copy first has to be attached to GitHub, once:
```bash
git fetch origin
```
```bash
git reset --soft origin/main
```
```bash
git commit -m "Add config for Lenovo ThinkPad T14"
```
```bash
git push -u origin main
```
(Error `'origin' does not appear to be a git repository`? Run
`git remote add origin https://github.com/Fritz4all/nixos-config.git` first, then start B again.)

## Step 8: Check on GitHub

Open <https://github.com/Fritz4all/nixos-config> and click the folder **hosts**: the table shows your config.

---

## Later: saving new changes

After you change something on this machine (e.g. added a program and ran `rebuild`), and after updates
(`nixup` or the automatic weekly update change `flake.lock`):

```bash
cd /etc/nixos
```
```bash
git add -A && git commit -m "Describe what you changed" && git push
```

On your other machines you then get it with `cd /etc/nixos && git pull && rebuild`.

## When something goes wrong

| Message | What to do |
|---|---|
| `! [rejected] ... (fetch first)` | GitHub has newer changes. Run `git pull`, then `git push` again. |
| `CONFLICT (content): Merge conflict in <file>` | The same file was changed here and on GitHub. Open the file: keep the right lines between `<<<<<<<` and `>>>>>>>`, delete those marker lines, then `git add -A && git commit -m "Merge" && git push`. Or ask for help before doing anything else. |
| `Authentication failed` or `Permission denied` when pushing | Do step 4 again (`gh auth login`). |
| `repository path '/etc/nixos' is not owned by current user` | Run `sudo chown -R $USER:users /etc/nixos` once, then try again. |
| `Please tell me who you are` | Do step 3. |
| `nothing to commit, working tree clean` | Everything is already saved. Just run `git push` (or nothing at all). |
