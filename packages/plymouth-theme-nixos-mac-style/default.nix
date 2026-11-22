{ lib, stdenv, unzip }:

stdenv.mkDerivation {
  pname = "plymouth-theme-nixos-mac-style";
  version = "1.1-unstable-2026-07-15";

  src = ./nixos-mac-style.zip;

  nativeBuildInputs = [ unzip ];

  unpackPhase = ''
    runHook preUnpack
    unzip $src
    runHook postUnpack
  '';

  installPhase = ''
    runHook preInstall

    # Plymouth looks up themes by this exact directory name.
    theme=$out/share/plymouth/themes/nixos-mac-style
    mkdir -p "$theme"
    cp -r nixos-mac-style/. "$theme/"

    # The upstream .plymouth file hardcodes /usr/share; point it at the store.
    substituteInPlace "$theme/nixos-mac-style.plymouth" \
      --replace-fail \
        "ImageDir=/usr/share/plymouth/themes/nixos-mac-style/images" \
        "ImageDir=$theme/images"

    # nixpkgs only ships the Cantarell variable font, which does not expose a
    # separate "Cantarell Light" family to fontconfig. Plain Cantarell avoids
    # silently falling back to DejaVu for the title.
    substituteInPlace "$theme/nixos-mac-style.plymouth" \
      --replace-fail "TitleFont=Cantarell Light 30" "TitleFont=Cantarell 30"

    # Not needed at boot.
    rm -f "$theme/Screenshot.png"

    runHook postInstall
  '';

  meta = {
    description = "NixOS macOS-style Plymouth boot animation";
    homepage = "https://www.opendesktop.org/p/2106821";
    license = lib.licenses.x11;
    platforms = lib.platforms.linux;
  };
}
