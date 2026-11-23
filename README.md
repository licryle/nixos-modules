# Licryle's personal NixOS Modules Archive

My personal collection of modular, production-ready NixOS module definitions structured to scale using `flake-parts` and modern Nix paradigms.

## 🚀 Overview

This repository uses a **dendritic module design**.
Currently only supports 2 types of Telegram Alerts (login & sudo).

---

## 🛠️ Module Features

### macOS-style Plymouth theme (`boot.plymouth.nixos-mac-style`)
A vendored `nixos-mac-style` Plymouth theme, exported both as a package
(`packages.<system>.plymouth-theme-nixos-mac-style`) and as a NixOS module
(`nixosModules.nixosMacStylePlymouth`) with `enable`, `silentBoot`, and
`earlyKms` options. See `packages/plymouth-theme-nixos-mac-style/README.md`.

### USB connect/disconnect chime (`services.usbChime`)
`nixosModules.usbChime` installs a `systemd.user` watcher that follows
`udevadm monitor` and plays the `device-added` / `device-removed` events of a
Freedesktop sound theme through `canberra-gtk-play`. `sound-theme-freedesktop`
and `cosmic-sound-theme` are installed as fallbacks.

```nix
imports = [ inputs.nixos-modules.nixosModules.usbChime ];

services.usbChime = {
  enable = true;
  user = "licryle";     # defaults to first normal user in config.users.users
  theme = "COSMIC";     # null = follow GTK/Noctalia's gtk-sound-theme-name
  volume = 3;           # optional, canberra-gtk-play -V; integer only
  # connectFile = ./connect.oga;       # bypass theme for this event
  # disconnectFile = ./disconnect.oga;
  # debounceMs = 300;
};
```

Notes:
- `theme` is implemented with `canberra-gtk-play --property=canberra.xdg-theme.name=…`.
  Setting `CANBERRA_THEME` does **not** work because GTK's `gtk-sound-theme-name`
  takes precedence.
- `volume` must be an integer; libcanberra rejects decimals (`"3.0"` fails with
  `Invalid argument`) despite the tool's help text claiming floating point.
- Audition sounds with `canberra-gtk-play -i device-added` and
  `canberra-gtk-play -i device-added --property=canberra.xdg-theme.name=COSMIC`.
- Requires home-manager in the consumer's module list for the user service;
  when absent, only the packages/themes are installed.

### Telegram Security Alerts (`services.alerts_tg`)
Enables real-time notification to specified Telegram chats triggered by log listening.

* **Independent Configuration Profiles**: Spin up individual channels for `login`, `sudo`.
* **Agenix-Native Runtime Secrets Handling**: Shell execution wrappers automatically intercept raw text string values *or* runtime file paths (like decrypted `/run/agenix/*` points) without baking highly privileged tokens into the public-facing world-readable Nix store.

---

## How to use it

### 1. Register as a Flake Input
Add this module archive to your personal system repository's `flake.nix`:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    
    # Track this module repository
    licryle.url = "github:licryle/nixos-modules"; 
  };

  outputs = inputs@{ self, nixpkgs, licryle, ... }: {
    nixosConfigurations.my-machine = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        ./configuration.nix
        
        # Load the base parent alerts orchestration framework
        licryle.nixosModules.alerts_tg
      ];
    };
  };
}
```

### 2. Configure System Services
Activate your specific alerting channels cleanly inside your profile definitions (e.g., `base-system.nix`).

#### Option A: Direct String Configuration (Testing/Quick Deploy)
```nix
services.alerts_tg.login = {
  enable = true;
  telegramChatId = "1273004695";
  telegramBotToken = "123456789:ABCdefGhIJKlmNoPQRsTUVwxyZ";
};
```

#### Option B: Secure Configuration (Recommended via Agenix)
```nix
services.alerts_tg.login = {
  enable = true;
  telegramChatId = nasCfg.telegramChatId;
  telegramBotToken = config.age.secrets.tglogging_bot_token.path; # Pass decrypted secret path safely
};
```

#### Tip: centralize the config
```nix
{ self, inputs, hostCfg, ...}: {
  flake.nixosModules.base-system = { pkgs, ... }:
  let
    alerts_tg_conf = {
      enable = true;
      telegramBotToken = hostCfg.tgAlertsBotToken;
      telegramChatId = hostCfg.tgAlertsChatId;
    };
  in {
    imports = [
      inputs.licryle.nixosModules.alerts_tg
    ];

    services.alerts_tg.login = alerts_tg_conf;
    services.alerts_tg.sudo = alerts_tg_conf;
  };
}
```

---

## 💻 Local Testing & Iterative Workflows

To avoid pushing every small edit to GitHub during active development cycles, utilize local evaluation overrides directly targeting your sandbox folder.

### Local Syntax Verification
Ensure all expressions are valid, references are bound, and curly brackets match without running a full compilation task:
```bash
nix eval .#nixosModules.alerts_tg
nix eval .#nixosModules.alerts_tg_login
nix eval .#nixosModules.alerts_tg_sudo
```

## 🛡️ License
Have fun with it, please feel free to PR improvements!