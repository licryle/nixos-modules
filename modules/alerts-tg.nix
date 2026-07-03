{ self, ... }:

{
  flake.nixosModules.alerts-tg = { config, lib, pkgs, ... }:

  # Test syntax with  nix eval .#nixosModules.alerts-tg

  let
    inherit (lib) mkEnableOption mkOption types mkIf;

    # Look up configuration values from the global config tree instead of arguments
    alertOptions = { name, config, ... }: {
      options = {
        enable = mkEnableOption "this specific Telegram alert";
        
        telegramBotToken = mkOption {
          type = types.str;
          description = "The Telegram bot token for ${name}.";
        };

        telegramChatId = mkOption {
          type = types.str;
          description = "Telegram chat or channel ID for ${name}.";
        };
      };

      # 2. Put the config verification logic RIGHT HERE inside the function blueprint!
      config = mkIf config.enable {
        assertions = [
          {
            assertion = config.telegramBotToken != "";
            message = "services.alerts_tg.${name} error: telegramBotToken cannot be empty when enabled.";
          }
          {
            assertion = config.telegramChatId != "";
            message = "services.alerts_tg.${name} error: telegramChatId cannot be empty when enabled.";
          }
        ];
      };
    };
  in {
    options.services.alerts_tg = {
      # 2. Assign the submodule to independent fields
      login = mkOption {
        type = types.submodule alertOptions;
        default = {};
        description = "Telegram alerts for user logins.";
      };

      sudo = mkOption {
        type = types.submodule alertOptions;
        default = {};
        description = "Telegram alerts for sudo commands.";
      };
    };
    
    imports = [
      self.nixosModules.alerts-login-tg
    ];
  };
}