{
  description = "Licryle's collection of reusable NixOS modules";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
  };

  outputs = inputs@{ nixpkgs, flake-parts, ... }:
    let
      lib = nixpkgs.lib;

      # 1. Gather all files under ./modules
      # 2. Exclude the entire direnv directory
      # 3. Filter strictly for .nix files
      allModuleFiles = lib.fileset.toList (
        lib.fileset.difference ./modules (
          lib.fileset.maybeMissing ./modules/paseo-with-pi/direnv
        )
      );
      
      nixFiles = builtins.filter (p: lib.hasSuffix ".nix" (toString p)) allModuleFiles;
    in
    flake-parts.lib.mkFlake { inherit inputs; } {
      imports = nixFiles;
    };
}