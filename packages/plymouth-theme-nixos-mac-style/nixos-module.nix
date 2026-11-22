{ config, lib, pkgs, ... }:

let
  cfg = config.boot.plymouth.nixos-mac-style;
in
{
  options.boot.plymouth.nixos-mac-style = {
    enable = lib.mkEnableOption "macOS-style Plymouth boot theme";

    silentBoot = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Configure quiet kernel parameters and console log level for a clean
        splash screen. Kernel messages are still available with Esc at boot.
      '';
    };

    theme = lib.mkOption {
      type = lib.types.package;
      default = pkgs.callPackage ./default.nix { };
      defaultText = lib.literalExpression "pkgs.callPackage ./default.nix { }";
      description = "The nixos-mac-style Plymouth theme package.";
    };

    font = lib.mkOption {
      type = lib.types.path;
      default = "${pkgs.cantarell-fonts}/share/fonts/cantarell/Cantarell-VF.otf";
      description = ''
        Font used by the theme. nixpkgs ships Cantarell as a single variable
        font, so the theme's original "Cantarell Light" title is mapped to it.
      '';
    };

    earlyKms = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Add common open-source GPU drivers to the initrd so Plymouth's DRM
        renderer can start early. Increases initrd size by ~55 MB. Never adds
        nouveau or proprietary NVIDIA modules: their firmware globs drag
        ~1.5 GB of blobs into the initrd and overflow a typical ESP.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # mkDefault keeps these overridable when you configure boot.plymouth
    # yourself with a theme package imported from nixos-modules.
    boot.plymouth = {
      enable = lib.mkDefault true;
      theme = lib.mkDefault "nixos-mac-style";
      themePackages = lib.mkDefault [ cfg.theme ];
      font = lib.mkDefault cfg.font;
    };

    boot.consoleLogLevel = lib.mkIf cfg.silentBoot (lib.mkDefault 0);
    # Plain list (not mkDefault) so it merges with kernelParams defined by
    # hardware/host modules. silentBoot = false is the way to opt out.
    boot.kernelParams = lib.mkIf cfg.silentBoot [
      "quiet"
      "rd.systemd.show_status=false"
      "systemd.show_status=false"
      "vt.global_cursor_default=0"
    ];

    boot.initrd.availableKernelModules = lib.mkIf cfg.earlyKms [
      "i915"
      "xe"
      "amdgpu"
      "radeon"
    ];
  };
}
