let
  f =
    build-or-shell:
    { chan ? "5272327b81ed355bbed5659b8d303cf2979b6953"
    , compiler ? "ghc865"
    , withHoogle ? false
    , doHoogle ? false
    , doHaddock ? false
    , enableLibraryProfiling ? false
    , enableExecutableProfiling ? false
    , strictDeps ? false
    , isJS ? false
    , system ? builtins.currentSystem
    , optimize ? true
    , shpadoinkle-path ? null
    }:
    let


      # It's a shpadoinkle day
      shpadoinkle = if shpadoinkle-path != null then shpadoinkle-path else builtins.fetchGit {
        url    = https://gitlab.com/platonic/shpadoinkle.git;
        ref    = "master";
        rev    = "a107da66dca476ed5b5ee68981bc235d46107574";
      };


      nfc-src = builtins.fetchGit {
        url    = https://github.com/centromere/nfc.git;
        ref    = "master";
        rev    = "7a3bed84242e23b42d53ecd2efe9f8b1a2bfdea8";
      };


      # Get some utilities
      inherit (import (shpadoinkle + "/nix/util.nix") { inherit compiler isJS pkgs; }) compilerjs doCannibalize;


      # Build faster by doing less
      chill = p: (pkgs.haskell.lib.overrideCabal p {
        inherit enableLibraryProfiling enableExecutableProfiling;
      }).overrideAttrs (_: {
        inherit doHoogle doHaddock strictDeps;
      });


      # Overlay containing Shpadoinkle packages, and needed alterations for those packages
      # as well as optimizations from Reflex Platform
      shpadoinkle-overlay =
        import (shpadoinkle + "/nix/overlay.nix") { inherit compiler chan isJS enableLibraryProfiling enableExecutableProfiling; };


      # Haskell specific overlay (for you to extend)
      haskell-overlay = hself: hsuper: {
        "nfc" = hself.callCabal2nix "nfc" nfc-src {};
      };


      # Top level overlay (for you to extend)
      doorctl-overlay = self: super: {
        haskell = super.haskell //
          { packages = super.haskell.packages //
            { ${compilerjs} = super.haskell.packages.${compilerjs}.override (old: {
                overrides = super.lib.composeExtensions (old.overrides or (_: _: {})) haskell-overlay;
              });
            };
          };
        };


      # Complete package set with overlays applied
      pkgs = import
        (builtins.fetchTarball {
          url = "https://github.com/NixOS/nixpkgs/archive/${chan}.tar.gz";
        }) {
        inherit system;
        overlays = [
          shpadoinkle-overlay
          doorctl-overlay
        ];
      };


      ghcTools = with pkgs.haskell.packages.${compiler};
        [ cabal-install
          ghcid
        ] ++ (if isJS then [] else [ stylish-haskell ]);


      # We can name him George
      mkPkg = x:
        with builtins;
        let
          l = pkgs.lib;
          source = ../.;
        in
        pkgs.haskell.packages.${compilerjs}.callCabal2nix x
          (filterSource
             (path: type:
                let
                  relative = replaceStrings [(toString source + "/")] [""] path;
                in
                (l.hasPrefix "src" relative || l.hasPrefix "api" relative || l.hasPrefix "ui" relative) && type == "directory"
                || l.hasSuffix ".hs" path
                || l.hasSuffix ".cabal" path
             )
             source
          )
          {};


      doorctl = mkPkg "doorctl";


    in with pkgs; with lib;

      { build = chill doorctl;

        shell =
          pkgs.haskell.packages.${compilerjs}.shellFor {
            inherit withHoogle;
            packages    = _: [ doorctl ];
            COMPILER    = compilerjs;
            buildInputs = ghcTools;
            shellHook   = ''
              ${lolcat}/bin/lolcat ${../figlet}
              cat ${../intro}
            '';
          };
      }.${build-or-shell};
in
  { build = f "build";
    shell = f "shell";
  }
