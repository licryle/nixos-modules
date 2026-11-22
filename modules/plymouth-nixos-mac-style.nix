{ self, ... }:

{
  # The theme is a first-class package:
  #   inputs.nixos-modules.packages.${pkgs.system}.plymouth-theme-nixos-mac-style
  perSystem = { pkgs, ... }: {
    packages.plymouth-theme-nixos-mac-style =
      pkgs.callPackage ../packages/plymouth-theme-nixos-mac-style/default.nix { };
  };

  # Option-based NixOS module (thin wrapper around the same package).
  flake.nixosModules.nixosMacStylePlymouth =
    import ../packages/plymouth-theme-nixos-mac-style/nixos-module.nix;
}
