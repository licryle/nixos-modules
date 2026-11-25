{...}: {
  flake.nixosModules.vgn98ProV1 = { config, lib, pkgs, ... }:
    let
      cfg = config.hardware.vgn.v98ProV1;
      src = ./.;
      physicalKeys = builtins.fromJSON (builtins.readFile (src + "/data/physical-keys.json"));
      logicalKeys = builtins.fromJSON (builtins.readFile (src + "/data/logical-keys.json"));
      lightingModeAliases = builtins.fromJSON (builtins.readFile (src + "/data/lighting-modes.json"));
      vgnctlFile = builtins.path { path = src + "/scripts/vgnctl.pl"; };
      generatorFile = builtins.path { path = src + "/scripts/generate-config.pl"; };

      declarativeSpec = pkgs.writeText "vgn98pro-spec.json" (builtins.toJSON {
        lighting = cfg.lighting;
        performance = cfg.performance;
        keys = cfg.keys;
        fnKeys = cfg.fnKeys;
        customLighting = cfg.customLighting;
        macros = cfg.macros;
        physicalKeys = physicalKeys;
        logicalKeys = logicalKeys;
        lightingModeAliases = lightingModeAliases;
      });

      generatedConfig = pkgs.runCommand "vgn98pro-config.json" {
        nativeBuildInputs = [ pkgs.perl ];
      } ''
        ${pkgs.perl}/bin/perl ${generatorFile} ${cfg.baseConfig} ${declarativeSpec} $out
      '';

      keyConfigType = lib.types.submodule {
        options = {
          value = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "Logical key name or macro name; must exist in the key tables.";
          };
        };
      };

      customLightType = lib.types.submodule {
        options = {
          rgb = lib.mkOption {
            type = lib.types.nullOr (lib.types.listOf (lib.types.ints.between 0 255));
            default = null;
            description = "RGB triple for this key.";
          };
          r = lib.mkOption { type = lib.types.nullOr (lib.types.ints.between 0 255); default = null; };
          g = lib.mkOption { type = lib.types.nullOr (lib.types.ints.between 0 255); default = null; };
          b = lib.mkOption { type = lib.types.nullOr (lib.types.ints.between 0 255); default = null; };
        };
      };

      macroEventType = lib.types.submodule {
        options = {
          delay = lib.mkOption {
            type = lib.types.ints.between 0 65535;
            default = 2;
            description = "Delay before this event in milliseconds.";
          };
          status = lib.mkOption {
            type = lib.types.enum [ "down" "up" ];
            default = "down";
            description = "Key press or release.";
          };
          code = lib.mkOption {
            type = lib.types.ints.between 0 255;
            default = 0;
            description = "HID key code, or mouse button number for deviceType 2.";
          };
          deviceType = lib.mkOption {
            type = lib.types.enum [ 1 2 ];
            default = 1;
            description = "1 for keyboard codes, 2 for mouse buttons.";
          };
        };
      };

      macroType = lib.types.submodule {
        options = {
          name = lib.mkOption {
            type = lib.types.str;
            description = "Name used by key bindings.";
          };
          mode = lib.mkOption {
            type = lib.types.enum [ "once" "repeat-finish" "repeat-stop" ];
            default = "once";
            description = ''
              HUB trigger mode:
              once          = Click to Execute Once
              repeat-finish = Press to Repeat, Complete Current Macro After Release Then Stop
              repeat-stop   = Press to Repeat, Release to Stop Immediately
            '';
          };
          repeat = lib.mkOption {
            type = lib.types.ints.between 1 254;
            default = 1;
            description = "Extra repeat count used by the \"once\" mode.";
          };
          events = lib.mkOption {
            type = lib.types.listOf macroEventType;
            default = [];
            description = "Macro events in execution order.";
          };
        };
      };

      script = pkgs.writeShellScriptBin "vgnctl" ''
        exec ${pkgs.perl}/bin/perl ${vgnctlFile} "$@"
      '';


      restoreOnConnect = pkgs.writeShellScriptBin "vgnctl-restore-on-connect" ''
        sleep 1
        ${script}/bin/vgnctl restore /etc/vgnctl/config.json >> /tmp/vgnctl-restore.log 2>&1
      '';
    in {
      options.hardware.vgn.v98ProV1 = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Install vgnctl and restore this keyboard configuration on connect.";
        };

        baseConfig = lib.mkOption {
          type = lib.types.path;
          default = ./config/v98pro-factory.json;
          description = "vgnctl-v4 snapshot used as the baseline for declarative overrides.";
        };

        lighting = {
          enable = lib.mkOption {
            type = lib.types.nullOr lib.types.bool;
            default = null;
            description = "Backlight on/off. null keeps the base config.";
          };
          brightness = lib.mkOption {
            type = lib.types.nullOr (lib.types.enum [ 0 1 2 3 4 ]);
            default = null;
            description = "Backlight brightness, 0 through 4.";
          };
          mode = lib.mkOption {
            type = lib.types.nullOr (lib.types.either lib.types.str lib.types.int);
            default = null;
            description = "Lighting mode name or number.";
          };
          speed = lib.mkOption {
            type = lib.types.nullOr (lib.types.enum [ 0 1 2 3 4 ]);
            default = null;
            description = "Lighting speed, 0 fastest through 4 slowest.";
          };
          chroma = lib.mkOption {
            type = lib.types.nullOr lib.types.bool;
            default = null;
            description = "Per-key rainbow/chroma effect.";
          };
          color = lib.mkOption {
            type = lib.types.nullOr (lib.types.strMatching "[0-9a-fA-F]{6}");
            default = null;
            description = "Six-digit hex RGB color, e.g. \"00796b\".";
          };
        };

        performance = {
          macMode = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Swap Win/Alt and map F1-F12 to media keys.";
          };
          sleepTime = lib.mkOption {
            type = lib.types.enum [ "never" 0 1 3 5 10 30 ];
            default = 1;
            description = "Idle sleep time: \"never\", 1, 3, 5, 10 or 30 minutes.";
          };
          pollingRate = lib.mkOption {
            type = lib.types.enum [ 1000 500 250 125 ];
            default = 500;
            description = "USB polling rate in Hz.";
          };
          smartSpeedX = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "SMART SPEED X input optimization.";
          };
          sixKeyRollover = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Switch from full-key to 6-key rollover.";
          };
          winLock = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Lock the Windows key.";
          };
          wasdSwap = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Swap WASD with arrow keys.";
          };
        };

        keys = lib.mkOption {
          type = lib.types.attrsOf keyConfigType;
          default = {};
          description = "Key overrides indexed by symbolic name or key number.";
        };

        fnKeys = lib.mkOption {
          type = lib.types.attrsOf keyConfigType;
          default = {};
          description = "Fn-layer key overrides indexed by symbolic name or key number.";
        };

        customLighting = lib.mkOption {
          type = lib.types.attrsOf customLightType;
          default = {};
          description = "Per-key RGB overrides indexed by symbolic name or key number.";
        };

        macros = lib.mkOption {
          type = lib.types.nullOr (lib.types.listOf macroType);
          default = null;
          description = "Macro definitions. null keeps the base macro table.";
        };
      };

      config = lib.mkIf cfg.enable {
        services.udev.extraRules = ''
          SUBSYSTEM=="hidraw", ATTRS{idVendor}=="320f", ATTRS{idProduct}=="5055", MODE="0660", GROUP="input", TAG+="uaccess"
          SUBSYSTEM=="hidraw", ACTION=="add", ATTRS{idVendor}=="320f", ATTRS{idProduct}=="5055", ENV{ID_USB_INTERFACE_NUM}=="01", RUN+="${restoreOnConnect}/bin/vgnctl-restore-on-connect"
        '';

        environment.etc."vgnctl/config.json".source = generatedConfig;

        environment.systemPackages = [ script ];
      };
    };
}
