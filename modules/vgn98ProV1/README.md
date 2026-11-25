# VGN V98 Pro V1 module

`nixosModules.vgn98ProV1` makes the VGN V98 Pro V1 (`320f:5055`) declarative.
It installs `vgnctl`, generates a `vgnctl-v4` config at build time, and
restores it on device connect through a udev rule. No browser or VGN HUB is
required.

## Layout

```text
vgn98ProV1.nix        NixOS module and options
scripts/vgnctl.pl     HID save/restore tool
scripts/generate-config.pl  Build-time config generator and validator
data/physical-keys.json Physical key name -> key index
data/logical-keys.json Logical key name -> HID value (Basic/Expansion)
data/lighting-modes.json  HUB lighting mode names
config/v98pro-factory.json  Baseline HID snapshot
```

## Option namespace

```nix
hardware.vgn.v98ProV1
```

Key bindings use one path only:

```nix
keys."F12".value = "PrintScreen";
fnKeys."Left Shift".value = "NIXlessthan";
```

`.value` accepts a name from `data/logical-keys.json`, or a declared macro name.

## Macro modes

```nix
mode = "once";            # Click to Execute Once
mode = "repeat-finish";   # Press to Repeat, Complete Current Macro After Release Then Stop
mode = "repeat-stop";     # Press to Repeat, Release to Stop Immediately
```

The generator pads the macro list to 16 slots automatically, so empty macros
do not need to be written by hand.

## Validation

The build fails on:

- unknown target names
- unknown source or macro names
- invalid key indices or HID values
- out-of-range lighting/performance values

Restore verifies FI, key/Fn/RGB blocks, and the macro table by reading them
back from the keyboard. Connect-time restore output is written to:

```text
/tmp/vgnctl-restore.log
```
