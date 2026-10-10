{
  description = "My NixOS configuration for all my machines";

  # Stable release 26.05 "Yarara". Upgrading to a new release = change this line
  # (e.g. nixos-26.11) and then run `nix flake update`.
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
