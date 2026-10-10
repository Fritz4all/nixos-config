# Commands for daily use: rebuild, rebuild-boot, nixup, versions, nixos-release.
# They are real commands (not shell aliases), so they also work with sudo, in every shell and in scripts.
# The scripts are in ./commands/; lib.sh is the shared part that is put in front of each of them.
{ pkgs, ... }:

let
  command = name: pkgs.writeShellScriptBin name
    (builtins.readFile ./commands/lib.sh + "\n" + builtins.readFile ./commands/${name}.sh);
in
{
  environment.systemPackages = map command [ "rebuild" "rebuild-boot" "nixup" "versions" "nixos-release" ];
}
