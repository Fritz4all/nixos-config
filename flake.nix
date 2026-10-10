{
  description = "My NixOS configuration for all my machines";

  # The NixOS release this config uses (nixos-YY.MM, or nixos-unstable).
  # Choose or change it with scripts/release.sh (on an installed machine: the command nixos-release);
  # that script edits this line, so keep its format.
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

  outputs = { self, nixpkgs }:
    let
      inherit (nixpkgs) lib;
      vars = import ./vars.nix;

      # Every directory in hosts/ is a machine, except directories starting with _ (the template).
      # Adding a new machine = creating a new directory (see scripts/new-host.sh).
      hostNames = builtins.attrNames (
        lib.filterAttrs
          (name: type: type == "directory" && !(lib.hasPrefix "_" name))
          (builtins.readDir ./hosts)
      );

      mkHost = hostname: lib.nixosSystem {
        specialArgs = { inherit vars; };
        modules = [
          ./modules
          ./hosts/${hostname}
          { networking.hostName = hostname; }
        ];
      };
    in
    {
      nixosConfigurations = lib.genAttrs hostNames mkHost;
    };
}
