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

### VGN V98 Pro V1 keyboard (`hardware.vgn.v98ProV1`)
`nixosModules.vgn98ProV1` makes the VGN V98 Pro V1 (USB `320f:5055`)
fully declarative. It installs `vgnctl`, generates a `vgnctl-v4` config from
Nix options at build time, and restores it automatically on device connect
through a udev rule. No browser or VGN HUB is required.

The implementation lives in `modules/vgn98ProV1/`:

- `vgn98ProV1.nix` — NixOS module and options
- `scripts/vgnctl.pl` — HID save/restore tool; cmd 20/21 macro read/write
- `scripts/generate-config.pl` — build-time config generator and validator
- `data/physical-keys.json` — physical key name → key index
- `data/logical-keys.json` — logical key name → HID value, grouped `Basic` / `Expansion`
- `data/lighting-modes.json` — HUB lighting mode names
- `config/v98pro-factory.json` — baseline snapshot

See `modules/vgn98ProV1/README.md` for module-local details.

```nix
imports = [ inputs.nixos-modules.nixosModules.vgn98ProV1 ];

hardware.vgn.v98ProV1 = {
  lighting = {
    enable = true;
    brightness = 4;
    mode = "Stepping Snow Without Trace";
    speed = 2;
    chroma = false;
    color = "00796b";
  };

  performance = {
    macMode = false;
    sleepTime = 1;          # "never" | 0 | 1 | 3 | 5 | 10 | 30
    pollingRate = 1000;     # 1000 | 500 | 250 | 125
    smartSpeedX = true;
    sixKeyRollover = false;
    winLock = false;
    wasdSwap = false;
  };

  # Target name -> source name or macro name.
  keys."F12".value = "PrintScreen";
  fnKeys."Left Shift".value = "NIXlessthan";

  customLighting."Esc".rgb = [ 255 0 0 ];

  macros = [
    {
      name = "NIXlessthan";
      mode = "repeat-finish";
      events = [
        { delay = 2; status = "down"; code = 224; deviceType = 1; }
        { delay = 2; status = "up"; code = 224; deviceType = 1; }
      ];
    }
  ];
};
```

Macro modes are the three HUB values:

```text
once          Click to Execute Once
repeat-finish Press to Repeat, Complete Current Macro After Release Then Stop
repeat-stop   Press to Repeat, Release to Stop Immediately
```

The macro list is padded to 16 slots at generation time with empty
`Macro 5`…`Macro 16` entries, so empty macros do not need to be written by hand.

Unknown target names, unknown source names, invalid RGB values, invalid
indices, and out-of-range options fail the build. Restore verification reads
back FI, key/Fn/RGB blocks, and the macro table (cmd 20) before reporting
success. Connect-time restore output is written to `/tmp/vgnctl-restore.log`.

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
nix eval .#nixosModules.vgn98ProV1
```

## 🛡️ License
Have fun with it, please feel free to PR improvements!