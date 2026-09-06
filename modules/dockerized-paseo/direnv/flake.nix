{
  description = "Paseo dev environment";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux"; # Adjust if you are on a Mac (e.g., "aarch64-darwin")
      pkgs = nixpkgs.legacyPackages.${system};

      cleanScript = name: text: pkgs.writeScriptBin name (builtins.replaceStrings ["\r"] [""] text);

      build_image = cleanScript "build_image" ''
        #!/usr/bin/env bash
        ENGINE=$(command -v podman || command -v docker)
        echo "📦 Building image with $ENGINE..."
        $ENGINE build -t ghcr.io/licryle/nixos-modules/dockerized-paseo:test .
      '';

      test_image = cleanScript "test_image" ''
        #!/usr/bin/env bash
        ENGINE=$(command -v podman || command -v docker)
        IP=$([ -e /proc/sys/fs/binfmt_misc/WSLInterop ] \
          && hostname -I | awk '{print $1}' \
          || echo 127.0.0.1)

        build_image || exit 1

        # Ensure local directories exist on host prior to mount
        mkdir -p "$PWD/.test/workspace" "$PWD/.test/home"

        # Add user namespace flag if using podman rootless
        USERNS_FLAGS=""
        if [ "$ENGINE" = "$(command -v podman)" ]; then
          USERNS_FLAGS="--userns=keep-id:uid=1000,gid=1000"
        fi

        (sleep 10 && xdg-open "http://''${IP}:6767") &
        
        $ENGINE run --rm -it $USERNS_FLAGS \
          -p 6767:6767 \
          -e PASEO_LISTEN="0.0.0.0:6767" \
          -e PASEO_HOSTNAMES="true" \
          -e PASEO_RELAY_ENABLED="false" \
          -v "$PWD/.test/workspace:/workspace:Z" \
          -v "$PWD/.test/home:/home/paseo:Z" \
          ghcr.io/licryle/nixos-modules/dockerized-paseo:test
      '';
    in
    {
      devShells.${system}.default = pkgs.mkShell {
        buildInputs = [
          pkgs.docker # Pulls docker utility into the shell
          build_image
          test_image
          pkgs.dos2unix
          pkgs.xdg-utils
          pkgs.act
        ];

        shellHook = ''
          ENGINE=$(command -v podman || command -v docker)
          echo "🚀 Paseo dev environment loaded using ($ENGINE)!"
          echo "   Run 'build_image' to build the container locally."
          echo "   Run 'test_image'  to build and start on http://127.0.0.1:6767"
        '';
      };
    };
}
