# Putting this config on GitHub

This is how the config was uploaded to GitHub (<https://github.com/Fritz4all/nixos-config>). You only need these
steps again if you want to set up the repo from scratch, for example under another account. Installing a machine
is described in the [README](../README.md).

You do this on your current computer (Ubuntu). After this, any machine can download the config.
There are no secrets in this folder (passwords live in Bitwarden), so a **public** repo is fine and the
installer can download it without logging in.

1. **Install Git and the GitHub tool.** Open a terminal and type:
   ```bash
   sudo apt install git gh
   ```
2. **Log in to GitHub.** Choose *GitHub.com*, *HTTPS*, *Yes* (authenticate Git) and *Login with a web browser*,
   then follow the instructions in the browser:
   ```bash
   gh auth login
   ```
3. **Tell Git who you are** (once per computer). Use your own name; the e-mail address may be the private
   address GitHub gives you (Settings → Emails):
   ```bash
   git config --global user.name "Your Name"
   git config --global user.email "you@example.com"
   ```
4. **Fill in the GitHub address.** Open `vars.nix` in a text editor and change the line `repoUrl = "";` into
   (with your GitHub username):
   ```nix
   repoUrl = "https://github.com/YOURNAME/nixos-config.git";
   ```
5. **Create the repo and upload.** In the terminal, go to the folder and run:
   ```bash
   cd ~/Documents/Claude/nixos-config
   git init -b main
   git add -A
   git commit -m "First version"
   gh repo create nixos-config --public --source=. --push
   ```
6. **Turn on the secret check** (see "Keeping secrets out" in the README):
   ```bash
   git config core.hooksPath .githooks
   ```
7. **Check.** Open `https://github.com/YOURNAME/nixos-config` in your browser; you should see the files.

Later changes are uploaded with:
```bash
git add -A
git commit -m "Describe what you changed"
git push
```
