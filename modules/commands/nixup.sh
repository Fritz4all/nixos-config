# nixup: update all software to the newest versions within the NixOS release, and apply them.
echo "Updating flake.lock ..."
as_owner nix --extra-experimental-features 'nix-command flakes' flake update --flake "$CFG"
rebuild_with switch "$@"
echo "Done. Save the new versions for your other machines: cd $CFG && git commit -am \"Update software\" && git push"
