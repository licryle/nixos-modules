{ self, ... }:

{
  flake.nixosModules.alerts-tg-sudo = { config, lib, pkgs, ... }:

  # Test syntax with  nix eval .#nixosModules.alerts-tg-sudo

  let
    # Look up configuration values from the global config tree instead of arguments
    inherit (lib) mkEnableOption mkOption types mkIf;
    cfg = config.services.alerts_tg.login;

    notifyScript = pkgs.writeShellApplication {
      name = "sudo-notify-action";
      runtimeInputs = [ pkgs.coreutils pkgs.gawk pkgs.curl pkgs.systemd pkgs.nettools ];

      text = ''
        HOST="$(hostname || echo NixOS-Server)"
        TIME="$(date)"
        USER_NAME="''${1:-Unknown}"
        COMMAND="''${2:-Unknown}"

        if [ -f "${cfg.telegramBotToken}" ]; then
          TOKEN="$(cat "${cfg.telegramBotToken}")"
        else
          TOKEN="${cfg.telegramBotToken}"
        fi

        MESSAGE="🚨 *SUDO ALERT* 🚨

🖥️ *Host:* \`$HOST\`
👤 *User:* \`$USER_NAME\`
⌨ *Command:* \`$COMMAND\`
🕒 *Time:* \`$TIME\`"

        curl --silent --show-error --fail -X POST \
          "https://api.telegram.org/bot$TOKEN/sendMessage" \
          --data-urlencode "chat_id=${cfg.telegramChatId}" \
          --data-urlencode "parse_mode=Markdown" \
          --data-urlencode "text=$MESSAGE" \
          --output /dev/null
      '';
    };

    monitorScript = pkgs.writeShellApplication {
      name = "sudo-monitor";
      runtimeInputs = [ pkgs.systemd notifyScript pkgs.gnugrep pkgs.gawk ];

      text = ''
        journalctl -t sudo --since "now" -f -o cat | \
        grep --line-buffered "COMMAND=" | \
        awk -F' : | ; COMMAND=' '{
          print $1 "|" $3
          fflush()
        }' | \
        while IFS="|" read -r username command; do
          if [ -n "$username" ] && [ -n "$command" ]; then
            echo "Processing sudo alert for user: $username"
            ${notifyScript}/bin/sudo-notify-action "$username" "$command"
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

      systemd.services.sudo-notify = {
        description = "Sudo commands monitor";
        wantedBy = [ "multi-user.target" ];

        serviceConfig = {
          Type = "simple";
          Restart = "always";
          RestartSec = "5s";
          ExecStart = "${monitorScript}/bin/sudo-monitor";
        };
      };
    };
  };
}