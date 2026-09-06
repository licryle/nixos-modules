{
  description = "Licryle's collection of reusable NixOS modules";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
  };

  outputs = inputs@{ nixpkgs, flake-parts, ... }:
    let
      lib = nixpkgs.lib;
      modulesDir = ./modules;

      # 1. Collect all .nix files directly via builtins.readDir / filesystem traversal
      findNixFiles = dir:
        lib.flatten (
          lib.mapAttrsToList (name: type:
            let
              path = dir + "/${name}";
            in
              if type == "directory" then
                if  name == ".direnv" then [ ]
                else findNixFiles path
              else if type == "regular" && lib.hasSuffix ".nix" name && name != "flake.nix" then [ path ]
              else [ ]
          ) (builtins.readDir dir)
        );

      nixFiles = findNixFiles modulesDir;
    in
    flake-parts.lib.mkFlake { inherit inputs; } {
      imports = nixFiles;
    };
}