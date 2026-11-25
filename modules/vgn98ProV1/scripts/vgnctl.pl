#!/usr/bin/env perl
# vgnctl -- save/restore the VGN V98 Pro (320f:5055) configuration.
# Talks directly to the vendor HID interface. No browser is involved.
use strict;
use warnings;
use IO::Select;
use Fcntl qw(O_RDWR O_NONBLOCK);
use JSON::PP;
use MIME::Base64 qw(encode_base64 decode_base64);
use POSIX qw(strftime);

# Vendor report id 4: 7-byte header + data, 64-byte writes.
# Commands: 5/6 function info, 8/9 keys, 38/39 Fn keys,
# 10/11 custom RGB, 20/21 macro table, 13 factory reset.
my $DEFAULT_FILE = "$ENV{HOME}/.config/vgnctl/config.json";
my $BLOCK_LEN = 392;

sub send_report {
  my ($dev, @payload) = @_;
  sysopen(my $fh, $dev, O_RDWR | O_NONBLOCK) or die "open $dev: $!\n";
  my @buf = (4, @payload);
  push @buf, 0 while @buf < 64;
  syswrite($fh, pack('C*', @buf)) == 64 or die "short write to $dev\n";
  my $sel = IO::Select->new($fh);
  my $data = "";
  for (1..50) {
    if ($sel->can_read(0.05)) {
      my $r = sysread($fh, $data, 64);
      if ($r && length($data) >= 8 && ord(substr($data, 0, 1)) == 4) { last; }
      $data = "";
    }
    select(undef, undef, undef, 0.01);
  }
  close $fh;
  return $data;
}

# Quick communication start/end are 7-byte payloads on the wire (8 bytes
# including the report id); padding them to 64 breaks block writes.
sub send_quick {
  my ($dev, $cmd) = @_;
  sysopen(my $fh, $dev, O_RDWR | O_NONBLOCK) or die "open $dev: $!\n";
  my @buf = (4, 0, 0, $cmd, 0, 0, 0, 0);
  syswrite($fh, pack('C*', @buf)) == @buf or die "short write to $dev\n";
  my $sel = IO::Select->new($fh);
  for (1..50) {
    last unless $sel->can_read(0.05);
    my $data = "";
    my $r = sysread($fh, $data, 64);
    last if $r && length($data) >= 8 && ord(substr($data, 0, 1)) == 4;
  }
  close $fh;
}

sub expect_report {
  my ($dev, $cmd, $len, $off_lo, $off_hi, @payload) = @_;
  for my $try (1..5) {
    my $d = send_report($dev, @payload);
    next unless length($d) >= 8;
    my @b = unpack('C*', $d);
    return $d if $b[3] == $cmd && $b[4] == $len
      && $b[5] == $off_lo && $b[6] == $off_hi;
    select(undef, undef, undef, 0.02);
  }
  die "no matching reply for command $cmd at offset "
      . ($off_hi * 256 + $off_lo) . "\n";
}

sub read_fi {
  my ($dev) = @_;
  my @fi;
  for my $off (0, 24) {
    my $d = expect_report($dev, 5, 24, $off, 0, 0, 0, 5, 24, $off, 0, 0);
    push @fi, unpack('C24', substr($d, 8, 24));
  }
  return pack('C*', @fi);
}

sub write_fi {
  my ($dev, $fi) = @_;
  die "function info must be 48 bytes\n" unless length($fi) == 48;
  for my $off (0, 24) {
    my @data = unpack('C24', substr($fi, $off, 24));
    expect_report($dev, 6, 24, $off, 0, 0, 0, 6, 24, $off, 0, 0, @data);
  }
}

# The 392-byte blocks are read/written in seven chunks. The last chunk
# declares len=48 but still carries 56 data bytes, matching the vendor
# tool's report framing.
my @CHUNKS = (
  [56, 0, 0, 56], [56, 56, 0, 56], [56, 112, 0, 56],
  [56, 168, 0, 56], [56, 224, 0, 56], [56, 24, 1, 56],
  [48, 80, 1, 56],
);

sub read_block {
  my ($dev, $cmd) = @_;
  send_quick($dev, 1);
  my $data = "";
  for my $c (@CHUNKS) {
    my ($len, $lo, $hi, $data_len) = @$c;
    my $d = expect_report($dev, $cmd, $len, $lo, $hi,
                  0, 0, $cmd, $len, $lo, $hi, 0);
    $data .= substr($d, 8, $data_len);
  }
  send_quick($dev, 2);
  return substr($data, 0, $BLOCK_LEN);
}

sub write_block {
  my ($dev, $cmd, $data) = @_;
  die "block must be $BLOCK_LEN bytes\n" unless length($data) == $BLOCK_LEN;
  send_quick($dev, 1);
  for my $c (@CHUNKS) {
    my ($len, $lo, $hi, $data_len) = @$c;
    my $chunk = substr($data, $hi * 256 + $lo, $data_len);
    $chunk .= "\0" x ($data_len - length($chunk));
    expect_report($dev, $cmd, $len, $lo, $hi,
          0, 0, $cmd, $len, $lo, $hi, 0,
          unpack('C*', $chunk));
  }
  send_quick($dev, 2);
}

sub verify_block {
  my ($dev, $cmd, $expected, $name) = @_;
  my $actual = read_block($dev, $cmd);
  die "$name write was not applied\n" unless $actual eq $expected;
}

# The macro table is exchanged directly with the keyboard: cmd 21 writes
# it and cmd 20 reads it back. Both use the same 56-byte chunk framing.
sub write_macro_table {
  my ($dev, $bytes) = @_;
  my ($pos, $chunk) = (0, 0);
  while ($pos < length($bytes)) {
    my $part = substr($bytes, $pos, 56);
    my $len = length($part);
    my $offset = 56 * $chunk;
    my ($lo, $hi) = ($offset & 255, ($offset >> 8) & 255);
    expect_report($dev, 21, $len, $lo, $hi,
          0, 0, 21, $len, $lo, $hi, 0,
          unpack('C*', $part));
    # The vendor tool waits between chunks; without it the table may
    # not be committed.
    select(undef, undef, undef, 0.02);
    $pos += $len;
    $chunk++;
  }
}

# The table header declares a length that is larger than the bytes the
# device actually stores, so derive the real length from the address
# table and action counts.
sub macro_table_length {
  my ($data) = @_;
  return length($data) if length($data) < 16;
  my $count = ord(substr($data, 4, 1)) | (ord(substr($data, 5, 1)) << 8);
  my $base = 16 + 2 * $count;
  return length($data) if length($data) < $base + 4;
  my $declared = ord(substr($data, 2, 1))
       | (ord(substr($data, 3, 1)) << 8);
  my @addr;
  for my $i (0 .. $count - 1) {
    push @addr, ord(substr($data, 16 + 2 * $i, 1))
      | (ord(substr($data, 17 + 2 * $i, 1)) << 8);
  }
  my $end = $base;
  for my $a (@addr) {
    next if $a < $base || $a + 4 > length($data);
    my $actions = ord(substr($data, $a, 1))
        | (ord(substr($data, $a + 1, 1)) << 8);
    next unless $actions && $actions < 1024;
    my $candidate = $a + 4 + 4 * $actions;
    # Stale bytes after the real table must not extend the record.
    next if $candidate > $declared || $candidate > length($data);
    $end = $candidate if $candidate > $end;
  }
  return $end <= length($data) ? $end : length($data);
}

sub read_macro_table {
  my ($dev) = @_;
  send_quick($dev, 1);
  my $data = "";
  my $declared;
  my $chunk = 0;
  while (1) {
    my $offset = 56 * $chunk;
    my ($lo, $hi) = ($offset & 255, ($offset >> 8) & 255);
    my $d = expect_report($dev, 20, 56, $lo, $hi,
                  0, 0, 20, 56, $lo, $hi, 0);
    $data .= substr($d, 8, 56);
    $chunk++;
    die "macro read did not converge\n" if $chunk > 200;
    if (!defined $declared && length($data) >= 4) {
      $declared = ord(substr($data, 2, 1))
        | (ord(substr($data, 3, 1)) << 8);
      die "implausible macro table length\n" if $declared > 65535;
    }
    last if defined $declared && length($data) >= $declared;
  }
  send_quick($dev, 2);
  return substr($data, 0, macro_table_length($data));
}

sub find_dev {
  my @candidates = ('/dev/input/by-id/usb-Telink_VGN_V98pro-if01-hidraw');
  for my $p (glob('/sys/bus/hid/devices/0003:320F:5055.*/hidraw/hidraw*')) {
    push @candidates, "/dev/$1" if $p =~ m{/([^/]+)$};
  }
  for my $dev (@candidates) {
    next unless -e $dev;
    my $d = send_report($dev, 0, 0, 5, 24, 0, 0, 0);
    return $dev if length($d) >= 8 && ord(substr($d, 0, 1)) == 4;
  }
  die "VGN V98 Pro vendor HID interface not found; is the keyboard plugged in?\n";
}

sub summary {
  my ($fi) = @_;
  my @b = unpack('C*', $fi);
  return sprintf(
    "light=%s brightness=%s mode=%s color=#%02x%02x%02x speed=%s",
    ($b[28] == 0 ? "on" : "off"), $b[2], $b[1],
    $b[6], $b[7], $b[8], $b[3]
  );
}

sub read_all {
  my ($dev) = @_;
  return {
    function_info   => read_fi($dev),
    key_matrix      => read_block($dev, 8),
    fn_key_matrix   => read_block($dev, 38),
    custom_lighting => read_block($dev, 10),
    macro_table     => read_macro_table($dev),
  };
}

my $cmd = shift @ARGV // "";
if ($cmd eq "save") {
  my $file = shift @ARGV // $DEFAULT_FILE;
  my $dev = find_dev();
  my $all = read_all($dev);
  my %blobs = map { $_ => encode_base64($all->{$_}, "") } keys %$all;
  my $obj = {
    format   => "vgnctl-v4",
    device   => "320f:5055",
    saved_at => strftime("%Y-%m-%dT%H:%M:%S%z", localtime),
    %blobs,
  };
  (my $dir = $file) =~ s{/[^/]+$}{};
  mkdir $dir if length($dir) && !-d $dir;
  open(my $fh, ">", $file) or die "write $file: $!\n";
  print $fh JSON::PP->new->pretty->canonical->encode($obj);
  close $fh;
  print "saved $dev to $file\n", summary($all->{function_info}), "\n";
  printf "macro table: %d bytes\n", length($all->{macro_table});
}
elsif ($cmd eq "restore") {
  my $file = shift @ARGV // $DEFAULT_FILE;
  open(my $fh, "<", $file) or die "read $file: $!\n";
  local $/; my $raw = <$fh>; close $fh;
  my $obj = JSON::PP->new->decode($raw);
  die "unrecognised config format\n" unless ($obj->{format} // "") eq "vgnctl-v4";
  die "config is for a different device\n" unless ($obj->{device} // "") eq "320f:5055";

  my $dev = find_dev();
  my $fi = decode_base64($obj->{function_info} // "");
  die "bad function info in config\n" unless length($fi) == 48;
  write_fi($dev, $fi);

  for my $entry ([key_matrix => 8, 9], [fn_key_matrix => 38, 39],
         [custom_lighting => 10, 11]) {
    my ($name, $read_cmd, $write_cmd) = @$entry;
    my $blob = decode_base64($obj->{$name} // "");
    die "bad $name in config\n" unless length($blob) == $BLOCK_LEN;
    write_block($dev, $write_cmd, $blob);
    verify_block($dev, $read_cmd, $blob, $name);
  }

  my $macro = decode_base64($obj->{macro_table} // "");
  die "bad macro table in config\n" unless length($macro);
  write_macro_table($dev, $macro);

  my $verify = read_all($dev);
  my $ok = 1;
  print "verification after restore:\n";
  for my $name (qw(function_info key_matrix fn_key_matrix custom_lighting macro_table)) {
    my $same = $verify->{$name} eq decode_base64($obj->{$name} // "");
    printf "%-16s %s%s\n", $name, ($same ? "IDENTICAL" : "DIFFERENT"),
      ($name eq "macro_table" ? " (" . length($macro) . " bytes)" : "");
    $ok = 0 unless $same;
  }
  die "restore verification failed\n" unless $ok;
  print "restored $file to $dev\n", summary($verify->{function_info}), "\n";
}
else {
  print "usage: vgnctl save [FILE]\n       vgnctl restore [FILE]\n";
  exit 1;
}
