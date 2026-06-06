{ pkgs, ... }:

let
  bibata = pkgs.bibata-cursors;
  hyprcursor-util = "${pkgs.hyprcursor}/bin/hyprcursor-util";

  bibata-hyprcursor = pkgs.stdenvNoCC.mkDerivation {
    pname = "bibata-hyprcursor";
    version = bibata.version;

    nativeBuildInputs = with pkgs; [ hyprcursor xcur2png ];

    phases = [ "installPhase" ];

    installPhase = ''
      runHook preInstall

      bibataDir="${bibata}/share/icons"
      outDir="$out/share/icons"
      mkdir -p "$outDir"

      # Copy original XCursor themes
      cp -r "$bibataDir/Bibata-Modern-Ice" "$outDir/"
      cp -r "$bibataDir/Bibata-Modern-Classic" "$outDir/"
      chmod -R u+w "$outDir"

      # Convert each theme to Hyprcursor
      for themeName in Bibata-Modern-Ice Bibata-Modern-Classic; do
        workdir=$(mktemp -d)
        mkdir -p "$workdir/extracted" "$workdir/out"

        # Extract XCursor to PNG
        hyprcursor-util --extract "$bibataDir/$themeName" --output "$workdir/extracted"

        extractDir="$workdir/extracted/extracted_$themeName"

        # Fix manifest name (hyprcursor-util uses "Extracted Theme" by default)
        sed -i "s/^name = .*/name = $themeName/" "$extractDir/manifest.hl"

        # Create Hyprcursor theme
        hyprcursor-util --create "$extractDir" --output "$workdir/out"

        # Move generated theme_<name> into the XCursor directory
        generatedDir="$workdir/out/theme_$themeName"
        cp -r "$generatedDir/"* "$outDir/$themeName/"

        rm -rf "$workdir"
      done

      runHook postInstall
    '';

    meta = with pkgs.lib; {
      description = "Bibata cursor themes with both XCursor and Hyprcursor support";
      license = licenses.gpl3;
      platforms = platforms.linux;
    };
  };
in
{
  home.pointerCursor = {
    name = "Bibata-Modern-Ice";
    package = bibata-hyprcursor;
    size = 32;
    gtk.enable = true;
    x11.enable = true;
  };
}
