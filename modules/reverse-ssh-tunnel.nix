{ self, ... }:

{
  flake.nixosModules.reverse_ssh_tunnel = { config, lib, pkgs, ... }:

  # Test syntax with: nix eval .#nixosModules.reverse_ssh_tunnel
  let
    inherit (lib) mkEnableOption mkOption mkIf types;
    cfg = config.services.reverse_ssh_tunnel;

    tunnelSubmodule = { name, config, ... }: {
      options = {
        enable = mkOption {
          type = types.bool;
          default = true;
          description = "Whether to enable this specific tunnel instance.";
        };

        host = mkOption {
          type = types.str;
          description = "Remote SSH server hostname or IP address.";
        };

        sshPort = mkOption {
          type = types.port;
          default = 22;
          description = "SSH connection port on the remote server.";
        };

        user = mkOption {
          type = types.str;
          default = "root";
          description = "Remote SSH user name.";
        };

        remotePort = mkOption {
          type = types.port;
          description = "Port to listen on the remote SSH server.";
        };

        localPort = mkOption {
          type = types.port;
          description = "Local port to expose remotely.";
        };

        bindAddress = mkOption {
          type = types.str;
          default = "0.0.0.0";
          description = "Address on the remote host to bind the remote port to.";
        };

        identityFile = mkOption {
          type = types.nullOr types.path;
          default = null;
          example = "/etc/ssh/ssh_host_ed25519_key";
          description = "Path to private key file for SSH key authentication.";
        };

        environmentFile = mkOption {
          type = types.nullOr types.path;
          default = null;
          example = lib.literalExpression "config.age.secrets.tunnelPassword.path";
          description = ''
            Environment file containing `SSHPASS=your_password`.
            Required when using password-based authentication via sshpass.
          '';
        };

        strictHostKeyChecking = mkOption {
          type = types.enum [ "yes" "no" "accept-new" ];
          default = "accept-new";
          description = "SSH StrictHostKeyChecking policy.";
        };
      };
    };

    enabledTunnels = lib.filterAttrs (_: tunnel: tunnel.enable) cfg.tunnels;

    mkTunnelService = name: tunnelCfg:
      let
        sshOpts = [
          "-o ServerAliveInterval=30"
          "-o ServerAliveCountMax=3"
          "-o StrictHostKeyChecking=${tunnelCfg.strictHostKeyChecking}"
          "-p ${toString tunnelCfg.sshPort}"
        ]
        ++ (lib.optional (tunnelCfg.identityFile != null) "-i ${tunnelCfg.identityFile}")
        ++ (lib.optional (tunnelCfg.environmentFile != null) "-o PubkeyAuthentication=no");

        sshOptsStr = lib.concatStringsSep " " sshOpts;

        tunnelCmd = ''
          ${pkgs.autossh}/bin/autossh -M 0 \
            -N \
            ${sshOptsStr} \
            -R ${tunnelCfg.bindAddress}:${toString tunnelCfg.remotePort}:localhost:${toString tunnelCfg.localPort} \
            ${tunnelCfg.user}@${tunnelCfg.host}
        '';
      in
      {
        description = "Persistent Reverse SSH Tunnel - ${name}";
        after = [ "network.target" ];
        wants = [ "network.target" ];
        wantedBy = [ "multi-user.target" ];

        path = [ pkgs.openssh pkgs.sshpass pkgs.autossh ];

        environment = {
          AUTOSSH_GATETIME = "0";
          AUTOSSH_POLL = "60";
          AUTOSSH_PATH = "${pkgs.openssh}/bin/ssh";
        };

        serviceConfig = {
          Type = "simple";
          User = "root";
          EnvironmentFile = lib.optional (tunnelCfg.environmentFile != null) tunnelCfg.environmentFile;
          Restart = "always";
          RestartSec = "10";
        };

        script =
          if tunnelCfg.environmentFile != null then
            "exec ${pkgs.sshpass}/bin/sshpass -e ${tunnelCmd}"
          else
            "exec ${tunnelCmd}";
      };
  in {
    options.services.reverse_ssh_tunnel = {
      enable = mkEnableOption "Generic persistent reverse SSH tunnels";

      tunnels = mkOption {
        type = types.attrsOf (types.submodule tunnelSubmodule);
        default = {};
        description = "Set of named reverse SSH tunnel instances.";
      };
    };

    config = mkIf cfg.enable {
      assertions = lib.mapAttrsToList (name: tunnelCfg: {
        assertion = (tunnelCfg.identityFile != null) || (tunnelCfg.environmentFile != null);
        message = "services.reverse-ssh-tunnel.tunnels.${name} requires either identityFile or environmentFile.";
      }) enabledTunnels;

      systemd.services = lib.mapAttrs' (name: tunnelCfg:
        lib.nameValuePair "reverse-ssh-tunnel-${name}" (mkTunnelService name tunnelCfg)
      ) enabledTunnels;
    };
  };
}