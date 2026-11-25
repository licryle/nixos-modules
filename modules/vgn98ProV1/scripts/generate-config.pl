#!/usr/bin/env perl
# Generate a vgnctl-v4 config from a base snapshot plus declarative overrides.
use strict;
use warnings;
use JSON::PP;
use MIME::Base64 qw(encode_base64 decode_base64);

my ($base_file, $spec_file, $out_file) = @ARGV;
die "usage: generate-config.pl BASE SPEC OUT\n" unless $base_file && $spec_file && $out_file;

sub read_json {
  my ($file) = @_;
  open(my $fh, "<", $file) or die "read $file: $!\n";
  local $/;
  my $o = decode_json(<$fh>);
  close $fh;
  return $o;
}

sub has {
  my ($hash, $key) = @_;
  return exists $hash->{$key} && defined $hash->{$key};
}

sub set_byte {
  my ($buf, $off, $value) = @_;
  die "byte offset $off out of range\n" if $off < 0 || $off >= length($$buf);
  die "bad byte value $value\n" unless defined $value && $value =~ /^\d+$/;
  substr($$buf, $off, 1) = pack("C", $value & 255);
}

sub hex_bytes {
  my ($color) = @_;
  die "bad color $color\n" unless $color =~ /^#?([0-9a-fA-F]{6})$/;
  return unpack("C3", pack("H*", $1));
}

sub resolve_key {
  my ($aliases, $key) = @_;
  die "unknown physical key: $key\n" unless exists $aliases->{$key};
  my $idx = 0 + $aliases->{$key};
  die "physical key $key has invalid index $idx\n" if $idx < 0 || $idx > 127;
  return $idx;
}

sub resolve_mode {
  my ($aliases, $mode) = @_;
  return 0 + $mode if $mode =~ /^\d+$/;
  die "unknown lighting mode: $mode\n" unless exists $aliases->{$mode};
  return 0 + $aliases->{$mode};
}

sub macro_trigger {
  my ($index, $mode, $repeat) = @_;
  if ($mode eq "once") {
    my $n = $repeat // 1;
    die "invalid macro repeat\n" if $n < 1 || $n > 254;
    return (113, $index, $n);
  }
  return (112, $index, 1) if $mode eq "repeat-finish";
  return (112, $index, 3) if $mode eq "repeat-stop";
  die "unknown macro mode: $mode\n";
}

sub macro_bindings {
  my ($macros) = @_;
  my %bindings;
  for my $i (0 .. $#$macros) {
    my $m = $macros->[$i];
    my $name = $m->{name};
    next unless defined $name && length $name;
    my $mode = $m->{mode} // "once";
    my $repeat = $m->{repeat} // 1;
    $bindings{$name} = [macro_trigger($i, $mode, $repeat)];
  }
  return \%bindings;
}

sub resolve_value {
  my ($sources, $macros, $value) = @_;
  die "value must be a source key or macro name\n" if ref $value;
  return @{$sources->{$value}} if exists $sources->{$value};
  return @{$macros->{$value}} if exists $macros->{$value};
  die "unknown logical key or macro name: $value\n";
}

sub encode_macro_table {
  my ($macros) = @_;
  my @macros;
  for my $m (@$macros) {
    my $events = $m->{content} // $m->{events} // [];
    die "macro content must be a list\n" unless ref($events) eq "ARRAY";
    push @macros, { events => $events };
  }
  die "too many macros\n" if @macros > 32;

  my $total = 0;
  $total += scalar(@{$_->{events}}) for @macros;
  my $count = scalar @macros;
  my $declared = 16 + 2 * $count + 4 * $count + 4 * $total;
  die "macro table too large\n" if $declared > 65535;

  my @out = (
    0xaa, 0x55, $declared & 255, ($declared >> 8) & 255,
    $count & 255, ($count >> 8) & 255, 0, 0,
    (0) x 8,
  );

  my $addr = 16 + 2 * $count;
  for my $m (@macros) {
    push @out, $addr & 255, ($addr >> 8) & 255;
    my $actions = scalar @{$m->{events}};
    $addr += 4 + 4 * $actions if $actions;
  }

  my %mouse = (1 => 1, 2 => 2, 3 => 4, 4 => 16, 5 => 8);
  for my $m (@macros) {
    my $events = $m->{events};
    my $actions = scalar @$events;
    next unless $actions;
    push @out, $actions & 255, ($actions >> 8) & 255, 0, 0;
    for my $e (@$events) {
      my $delay = $e->{delay} // 0;
      my $status = ($e->{status} // "down") eq "down" ? 1 : 0;
      my $device_type = $e->{deviceType} // 1;
      my $flags = $device_type == 2 ? 1 : 10;
      $flags |= 128 if $status;
      my $code = $device_type == 2
        ? ($mouse{$e->{code}} // 0)
        : ($e->{code} // 0);
      push @out, $delay & 255, ($delay >> 8) & 255, $flags & 255, $code & 255;
    }
  }
  return pack("C*", @out);
}

my $base = read_json($base_file);
my $spec = read_json($spec_file);

die "unexpected base config format\n" unless ($base->{format} // "") eq "vgnctl-v4";

my $fi = decode_base64($base->{function_info} // "");
my %blobs = (
  key_matrix => decode_base64($base->{key_matrix} // ""),
  fn_key_matrix => decode_base64($base->{fn_key_matrix} // ""),
  custom_lighting => decode_base64($base->{custom_lighting} // ""),
);
die "bad base config lengths\n" unless length($fi) == 48;
for my $name (keys %blobs) {
  die "bad $name length\n" unless length($blobs{$name}) == 392;
}

my $light = $spec->{lighting} // {};
if (has($light, "enable")) { set_byte(\$fi, 28, $light->{enable} ? 0 : 1); }
if (has($light, "brightness")) { set_byte(\$fi, 2, $light->{brightness}); }
if (has($light, "mode")) {
  set_byte(\$fi, 1, resolve_mode($spec->{lightingModeAliases} // {}, $light->{mode}));
}
if (has($light, "speed")) {
  my %speed = (0 => 4, 1 => 3, 2 => 2, 3 => 1, 4 => 0);
  die "bad lighting speed\n" unless exists $speed{$light->{speed}};
  set_byte(\$fi, 3, $speed{$light->{speed}});
}
if (has($light, "chroma")) { set_byte(\$fi, 5, $light->{chroma} ? 255 : 0); }
if (has($light, "color")) {
  my @rgb = hex_bytes($light->{color});
  for my $i (0 .. 2) { set_byte(\$fi, 6 + $i, $rgb[$i]); }
}

my $perf = $spec->{performance} // {};
if (has($perf, "macMode")) { set_byte(\$fi, 27, $perf->{macMode} ? 255 : 0); }
if (has($perf, "sleepTime")) {
  my %sleep = (
    "never" => [255, 255], 0 => [255, 255],
    1 => [60, 0], 3 => [180, 0], 5 => [44, 1],
    10 => [88, 2], 30 => [8, 7],
  );
  my $key = "$perf->{sleepTime}";
  die "bad sleepTime\n" unless exists $sleep{$key};
  my @pair = @{$sleep{$key}};
  set_byte(\$fi, 13, $pair[0]);
  set_byte(\$fi, 14, $pair[1]);
}
if (has($perf, "pollingRate")) {
  my %rate = (1000 => 0, 500 => 1, 250 => 2, 125 => 3);
  die "bad pollingRate\n" unless exists $rate{$perf->{pollingRate}};
  set_byte(\$fi, 22, $rate{$perf->{pollingRate}});
}
if (has($perf, "smartSpeedX")) { set_byte(\$fi, 33, $perf->{smartSpeedX} ? 1 : 0); }
if (has($perf, "sixKeyRollover")) { set_byte(\$fi, 20, $perf->{sixKeyRollover} ? 0 : 255); }
if (has($perf, "winLock")) { set_byte(\$fi, 21, $perf->{winLock} ? 1 : 0); }
if (has($perf, "wasdSwap")) { set_byte(\$fi, 19, $perf->{wasdSwap} ? 1 : 0); }

my $macros = has($spec, "macros") ? $spec->{macros} : undef;
if ($macros) {
  die "too many macros\n" if @$macros > 16;
  my %used = map { $_->{name} => 1 } grep { defined $_->{name} } @$macros;
  for my $i (scalar(@$macros) .. 15) {
    my $name = "Macro " . ($i + 1);
    die "duplicate macro name $name\n" if $used{$name};
    push @$macros, { name => $name, events => [] };
    $used{$name} = 1;
  }
}
my $macro_bindings = $macros ? macro_bindings($macros) : {};
my $physical_keys = $spec->{physicalKeys} // {};
my $source_groups = $spec->{logicalKeys} // {};
my %logical_keys = (%{$source_groups->{Basic} // {}}, %{$source_groups->{Expansion} // {}});
for my $name (keys %$physical_keys) {
  die "invalid physical key index for $name\n"
    unless $physical_keys->{$name} =~ /^\d+$/
        && $physical_keys->{$name} >= 0 && $physical_keys->{$name} <= 127;
}
for my $name (keys %logical_keys) {
  my $v = $logical_keys{$name};
  die "invalid logical key value for $name\n"
    unless ref($v) eq "ARRAY" && @$v == 3
        && !grep { $_ !~ /^\d+$/ || $_ < 0 || $_ > 255 } @$v;
}

for my $entry (
  [keys => "key_matrix", $physical_keys],
  [fnKeys => "fn_key_matrix", $physical_keys],
) {
  my ($option, $blob, $aliases) = @$entry;
  my $map = $spec->{$option} // {};
  for my $name (keys %$map) {
    my $cfg = $map->{$name};
    my @value;
    if (has($cfg, "value")) {
      @value = resolve_value(\%logical_keys, $macro_bindings, $cfg->{value});
    }
    else {
      next;
    }
    my $idx = resolve_key($aliases, $name);
    for my $i (0 .. 2) { set_byte(\$blobs{$blob}, 3 * $idx + $i, $value[$i]); }
  }
}

my $lights = $spec->{customLighting} // {};
for my $name (keys %$lights) {
  my $cfg = $lights->{$name};
  my $idx = resolve_key($physical_keys, $name);
  my @rgb = has($cfg, "rgb") ? @{$cfg->{rgb}} : ($cfg->{r}, $cfg->{g}, $cfg->{b});
  die "customLighting.$name needs r/g/b\n" unless @rgb == 3;
  for my $i (0 .. 2) { set_byte(\$blobs{custom_lighting}, 3 * $idx + $i, $rgb[$i]); }
}

my $macro_table = $macros ? encode_macro_table($macros)
                          : decode_base64($base->{macro_table} // "");

my %out = (
  %$base,
  function_info => encode_base64($fi, ""),
  key_matrix => encode_base64($blobs{key_matrix}, ""),
  fn_key_matrix => encode_base64($blobs{fn_key_matrix}, ""),
  custom_lighting => encode_base64($blobs{custom_lighting}, ""),
  macro_table => encode_base64($macro_table, ""),
  format => "vgnctl-v4",
  device => "320f:5055",
  generated_at => scalar localtime,
);

open(my $fh, ">", $out_file) or die "write $out_file: $!\n";
print $fh JSON::PP->new->pretty->canonical->encode(\%out);
close $fh;
