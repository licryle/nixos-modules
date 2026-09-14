{ self, ... }:

{
  flake.nixosModules.dockerized_paseo = { config, lib, pkgs, ... }:

  # Test syntax with: nix eval .#nixosModules.dockerized_paseo
  let
    inherit (lib) mkEnableOption mkOption types mkIf;
    cfg = config.services.dockerized_paseo;
  in {
    options.services.dockerized_paseo = {
      enable = mkEnableOption "Paseo server OCI container service";

      image = mkOption {
        type = types.str;
        default = "ghcr.io/licryle/nixos-modules/dockerized-paseo:latest";
        description = "Container image to run for Paseo.";
      };
      
      listenAddress = mkOption {
        type = types.str;
        default = "127.0.0.1";
        description = "Host interface address to bind the published port to. Set to 0.0.0.0 to expose externally.";
      };

      listenPort = mkOption {
        type = types.port;
        default = 6767;
        description = "Host port to map to Paseo daemon (6767).";
      };

      workspacePath = mkOption {
        type = types.str;
        default = "/var/lib/paseo/workspace";
        description = "Host directory path to mount into /workspace.";
      };

      dataDir = mkOption {
        type = types.str;
        default = "/var/lib/paseo/home";
        description = "Host directory path to mount into /home/paseo for persistent state and auth.";
      };

      allowHostnames = mkOption {
        type = types.listOf types.str;
        default = [ "127.0.0.1" "localhost" ];
        description = "List of hostnames allowed by Paseo. Expanded to comma-separated PASEO_HOSTNAMES.";
      };
      
      webUIPasswordFile = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = "Path to an agenix secret file containing the PASEO_PASSWORD=password (no quotes) string.";
      };

      relayEnabled = mkOption {
        type = types.bool;
        default = false;
        description = "Set PASEO_RELAY_ENABLED (controls internal relay server connection).";
      };

      environment = mkOption {
        type = types.attrsOf types.str;
        default = {};
        description = "Additional environment variables passed to the Paseo container.";
      };
    };

    config = mkIf cfg.enable {
      # Ensure state directories exist on the host system with permissions for UID 1000
      systemd.tmpfiles.rules = [
        "d ${cfg.workspacePath} 0755 1000 1000 - -"
        "d ${cfg.dataDir} 0755 1000 1000 - -"
      ];

      # Container lifecycle via systemd and Podman/Docker
      virtualisation.oci-containers.containers.paseo = {
        image = cfg.image;
        ports = [ "${cfg.listenAddress}:${toString cfg.listenPort}:6767" ];
        volumes = [
          "${cfg.workspacePath}:/workspace:Z"
          "${cfg.dataDir}:/home/paseo:Z"
        ];
        
        # Passes the agenix secret directly into the container env securely
        environmentFiles = lib.optional (cfg.webUIPasswordFile != null) cfg.webUIPasswordFile;
        
        environment = {
          PASEO_HOSTNAMES = lib.concatStringsSep "," cfg.allowHostnames;
          PASEO_RELAY_ENABLED = if cfg.relayEnabled then "true" else "false";
        } // cfg.environment;
      };
    };
  };
}