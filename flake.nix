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

      # Every directory in hosts/ is a config for a machine type and variant (e.g.
      # lenovo-thinkpad-t14-gen-3-gnome), shared by all machines of that type. Directories starting with _
      # are templates. The machine names themselves are not in the config (see modules/common.nix).
      variants = builtins.attrNames (
        lib.filterAttrs
          (name: type: type == "directory" && !(lib.hasPrefix "_" name))
          (builtins.readDir ./hosts)
      );

      mkVariant = variant: lib.nixosSystem {
        specialArgs = { inherit vars; };
        modules = [
          ./modules
          ./hosts/${variant}
          { my.variant = variant; }
        ];
      };
    in
    {
      nixosConfigurations = lib.genAttrs variants mkVariant;

      # Installer ISO with this repo and, for offline installation, the complete systems of the given
      # variants. Used by build-iso.sh:  (lib.mkIso { variants = [ "..." ]; }).config.system.build.isoImage
      lib.mkIso = { variants ? [ ], label ? "generic" }: lib.nixosSystem {
        specialArgs = { inherit self vars variants label; };
        modules = [ ./iso/installer.nix ];
      };
    };
}
