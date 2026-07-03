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

    # 2. Automatically generate the assertions for ALL defined submodules dynamically!
    config = {
      assertions = mapAttrsToList (serviceName: serviceCfg: {
        assertion = serviceCfg.enable -> (serviceCfg.telegramBotToken != "");
        message = "services.alerts_tg.${serviceName} error: telegramBotToken cannot be empty when enabled.";
      }) cfg ++ mapAttrsToList (serviceName: serviceCfg: {
        assertion = serviceCfg.enable -> (serviceCfg.telegramChatId != "");
        message = "services.alerts_tg.${serviceName} error: telegramChatId cannot be empty when enabled.";
      }) cfg;
    };
    
    imports = [
      self.nixosModules.alerts-login-tg
    ];
  };
}