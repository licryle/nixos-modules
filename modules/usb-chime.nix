{ self, ... }:

{
  # Test syntax with: nix eval .#nixosModules.usbChime
  flake.nixosModules.usbChime = { config, lib, pkgs, ... }:
    let
      inherit (lib) mkEnableOption mkOption mkIf types;
      cfg = config.services.usbChime;

      # canberra-gtk-play arguments for one event.
      argsFor = event: file: ''
        ${
          if file != null
          then ''args=(-f "${file}")''
          else ''args=(-i ${event})''
        }
        ${lib.optionalString (cfg.volume != null) ''args+=(-V "${toString cfg.volume}")''}
        ${lib.optionalString (cfg.theme != null) ''args+=(--property "canberra.xdg-theme.name=${cfg.theme}")''}
      '';

      watcher = pkgs.writeShellScriptBin "usb-chime-watch" ''
        set -uo pipefail

        canberra="${lib.getExe' pkgs.libcanberra-gtk3 "canberra-gtk-play"}"
        udevadm="${lib.getExe' pkgs.systemd "udevadm"}"
        date="${lib.getExe' pkgs.coreutils "date"}"
        awk="${lib.getExe' pkgs.gawk "awk"}"

        last=0
        debounce_ms=${toString cfg.debounceMs}

        # Use process substitution so the loop keeps its variables in this shell.
        while IFS= read -r line; do
          case "$line" in
            # Header: UDEV  [123.456] add  /devices/... (usb)
            UDEV[[:space:]]*)
              action=$($awk '{print $3}' <<< "$line")
              devtype=""
              ;;
            DEVTYPE=*)
              devtype="''${line#DEVTYPE=}"
              ;;
            # Blank line ends one event's property block.
            "")
              if [ "$devtype" = "usb_device" ]; then
                case "$action" in
                  add)
                    ${argsFor "device-added" cfg.connectFile}
                    ;;
                  remove)
                    ${argsFor "device-removed" cfg.disconnectFile}
                    ;;
                  *)
                    args=()
                    ;;
                esac

                if [ "''${#args[@]}" -gt 0 ]; then
                  now=$($date +%s%3N)
                  if [ $((now - last)) -ge "$debounce_ms" ]; then
                    last=$now
                    "$canberra" "''${args[@]}" >/dev/null 2>&1 || true
                  fi
                fi
              fi
              action=""
              devtype=""
              ;;
          esac
        done < <("$udevadm" monitor --udev --subsystem-match=usb --property 2>/dev/null)
      '';
    in {
      options.services.usbChime = {
        enable = mkEnableOption "USB connect/disconnect chimes";

        user = mkOption {
          type = types.str;
          default =
            let
              normalUsers = lib.filterAttrs (_: u: u.isNormalUser or false) config.users.users;
            in
            if normalUsers == { } then "root" else lib.head (lib.attrNames normalUsers);
          defaultText = lib.literalExpression "first normal user in config.users.users";
          description = ''
            User whose systemd --user session and sound theme are used for
            playback. Defaults to the first normal user; set explicitly if
            that is wrong for your machine.
          '';
        };

        theme = mkOption {
          type = types.nullOr types.str;
          default = null;
          example = "COSMIC";
          description = ''
            Freedesktop sound theme to use for the chimes. When null, the
            theme selected by the desktop session (GTK's gtk-sound-theme-name)
            is used. Implemented via canberra-gtk-play's
            --property=canberra.xdg-theme.name override.
          '';
        };

        connectFile = mkOption {
          type = types.nullOr types.path;
          default = null;
          description = ''
            Sound file played on USB connect instead of the theme's
            device-added event (canberra-gtk-play -f).
          '';
        };

        disconnectFile = mkOption {
          type = types.nullOr types.path;
          default = null;
          description = ''
            Sound file played on USB disconnect instead of the theme's
            device-removed event (canberra-gtk-play -f).
          '';
        };

        volume = mkOption {
          type = types.nullOr types.int;
          default = null;
          example = 3;
          description = ''
            Volume adjustment passed as canberra-gtk-play -V. Null uses the
            event's own volume. libcanberra rejects decimals despite the help
            text claiming a floating point value, so this is an integer,
            e.g. 3 or -3.
          '';
        };

        debounceMs = mkOption {
          type = types.int;
          default = 300;
          description = ''
            Minimum milliseconds between chimes, used to coalesce the burst
            of udev events a single plug/unplug produces.
          '';
        };
      };

      config = mkIf cfg.enable {
        # Themes plus the CLI, so users can audition sounds with
        # canberra-gtk-play -i device-added.
        environment.systemPackages = with pkgs; [
          sound-theme-freedesktop
          cosmic-sound-theme
          libcanberra-gtk3
        ];

        # Only valid when the consumer has home-manager in their module list.
        home-manager = mkIf (config ? home-manager) {
          users.${cfg.user}.systemd.user.services.usb-chime = {
            Unit = {
              Description = "USB connect/disconnect chime (Freedesktop sound theme)";
            };
            Service = {
              Type = "simple";
              ExecStart = "${watcher}/bin/usb-chime-watch";
              Restart = "on-failure";
              RestartSec = 2;
            };
            Install = {
              WantedBy = [ "default.target" ];
            };
          };
        };
      };
    };
}
