{ self, ... }:

{
  flake.nixosModules.alerts-login-tg = { config, lib, pkgs, ... }:

  # Test syntax with  nix eval .#nixosModules.alerts-login-tg

  let
    # Look up configuration values from the global config tree instead of arguments
    inherit (lib) mkEnableOption mkOption types mkIf;
    cfg = config.services.alerts_tg.login;

    notifyScript = pkgs.writeShellApplication {
      name = "login-notify-action";
      runtimeInputs = [ pkgs.coreutils pkgs.gawk pkgs.curl pkgs.systemd pkgs.nettools ];

      text = ''
        HOST="$(hostname || echo NixOS-Server)"
        TIME="$(date)"
        USER_NAME="''${1:-Unknown}"

        MESSAGE="🚨 *LOGIN ALERT* 🚨

🖥️ *Host:* \`$HOST\`
👤 *User:* \`$USER_NAME\`
🕒 *Time:* \`$TIME\`"

        curl --silent --show-error --fail -X POST \
          "https://api.telegram.org/bot${cfg.telegramBotToken}/sendMessage" \
          --data-urlencode "chat_id=${cfg.telegramChatId}" \
          --data-urlencode "parse_mode=Markdown" \
          --data-urlencode "text=$MESSAGE" \
          --output /dev/null
      '';
    };

    monitorScript = pkgs.writeShellApplication {
      name = "login-monitor";
      runtimeInputs = [ pkgs.systemd notifyScript pkgs.gnugrep ];

      text = ''
        journalctl -u systemd-logind.service -f -o cat --since "now" | \
        sed -un 's/.*New session .* of user \(.*\)\./\1/p' | \
        while read -r username; do
          if [ -n "$username" ]; then
            echo "Processing login alert for user: $username"
            ${notifyScript}/bin/login-notify-action "$username"
          fi
        done
      '';
    };

  in {
    config = lib.mkIf cfg.enable {
      environment.systemPackages = [
        notifyScript
        monitorScript
      ];

      systemd.services.login-notify = {
        description = "Login session monitor";
        wantedBy = [ "multi-user.target" ];

        serviceConfig = {
          Type = "simple";
          Restart = "always";
          RestartSec = "5s";
          ExecStart = "${monitorScript}/bin/login-monitor";
        };
      };
    };
  };
}