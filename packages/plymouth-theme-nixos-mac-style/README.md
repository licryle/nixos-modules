# plymouth-theme-nixos-mac-style

Standalone package + option-based NixOS module for the **NixOS** variant of
[Linux Distro Logos – macOS Boot Style](https://www.opendesktop.org/p/2106821)
by `tobilinuxer` (X11 license, v1.1).

The archive is vendored here because OpenDesktop/Pling download URLs are
signed, IP-bound and expire, which would make a plain `fetchurl` break on the
next rebuild.

## As a package

```nix
{ inputs, pkgs, ... }:
let
  theme = inputs.nixos-modules.packages.${pkgs.system}.plymouth-theme-nixos-mac-style;
in
{
  boot.plymouth = {
    enable = true;
    theme = "nixos-mac-style";
    themePackages = [ theme ];
    font = "${pkgs.cantarell-fonts}/share/fonts/cantarell/Cantarell-VF.otf";
  };
}
```

Build directly:

```sh
nix build .#plymouth-theme-nixos-mac-style
```

## As a NixOS module

```nix
{
  imports = [ inputs.nixos-modules.nixosModules.nixosMacStylePlymouth ];

  boot.plymouth.nixos-mac-style = {
    enable = true;
    silentBoot = true; # default: quiet kernel + no systemd status flashes
    earlyKms = false;  # default: no extra GPU drivers in the initrd
  };
}
```

Options:

| Option | Default | Meaning |
| --- | --- | --- |
| `enable` | `false` | Enable Plymouth + this theme. |
| `silentBoot` | `true` | `loglevel=0`, `quiet`, `rd.systemd.show_status=false`, `systemd.show_status=false`, no blinking cursor. Press `Esc` at boot for the text log. |
| `theme` | vendored package | Override the theme package. |
| `font` | Cantarell VF | Font used by the theme. |
| `earlyKms` | `false` | Add `i915`/`xe`/`amdgpu`/`radeon` to the initrd (~55 MB). Never adds `nouveau` or NVIDIA blobs — those pull ~1.5 GB of firmware and overflow a typical ESP. |

All `boot.plymouth` attributes set by the module use `mkDefault`, so anything
you configure directly wins.
