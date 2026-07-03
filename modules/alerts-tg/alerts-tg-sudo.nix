{ self, ... }:

{
  flake.nixosModules.alerts_tg_sudo = { config, lib, pkgs, ... }:

  # Test syntax with  nix eval .#nixosModules.alerts_tg_sudo

  let
    # Look up configuration values from the global config tree instead of arguments
    inherit (lib) mkEnableOption mkOption types mkIf;
    cfg = config.services.alerts_tg.sudo;

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

        # Split Chat ID and Topic ID if an underscore exists
        RAW_ID="${cfg.telegramChatId}"
        CHAT_ID="''${RAW_ID%_*}"
        THREAD_ID="''${RAW_ID#*_}"

        # Initialize base curl arguments
        CURL_ARGS=(
          "--data-urlencode" "chat_id=$CHAT_ID"
          "--data-urlencode" "parse_mode=Markdown"
          "--data-urlencode" "text=$MESSAGE"
        )

        # If a thread ID was extracted from the underscore, append it to the arguments
        if [ "$CHAT_ID" != "$RAW_ID" ]; then
          CURL_ARGS+=("--data-urlencode" "message_thread_id=$THREAD_ID")
        fi

        curl --silent --show-error --fail -X POST \
          "https://api.telegram.org/bot$TOKEN/sendMessage" \
          "''${CURL_ARGS[@]}" \
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