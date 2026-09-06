{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system: let
      pkgs = nixpkgs.legacyPackages.${system};

      cleanScript = name: text: pkgs.writeScriptBin name (builtins.replaceStrings ["\r"] [""] text);      

      act_dryrun = cleanScript "act_dryrun" ''
        #!/usr/bin/env bash
        set -euo pipefail

        # Locate repo root dynamically regardless of current working directory
        REPO_ROOT="$(git rev-parse --show-toplevel)"
        WORKFLOW="$REPO_ROOT/.github/workflows/docker-images-publish.yml"

        if [ ! -f "$WORKFLOW" ]; then
          echo "❌ Error: Workflow file not found at $WORKFLOW"
          exit 1
        fi

        echo "📝 Dry-run of GitHub Actions workflow using act..."
        act push \
          -W "$WORKFLOW" \
          -j build-and-push \
          --container-daemon-socket "unix://$XDG_RUNTIME_DIR/podman/podman.sock" \
          --dryrun
      '';
    in {
      devShells.default = pkgs.mkShell {
        packages = [
          pkgs.act
          act_dryrun
        ];
      };
    });
}
