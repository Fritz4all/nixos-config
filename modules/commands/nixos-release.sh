# nixos-release: show or change the NixOS release (then: rebuild-boot and reboot).
as_owner bash "$CFG/scripts/release.sh" --dir "$CFG" "$@"
