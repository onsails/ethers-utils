{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/release-22.11";
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    devenv.url = "github:cachix/devenv";
    flake-utils.url = "github:numtide/flake-utils";
    fenix = {
      url = "github:nix-community/fenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    crane = {
      url = "github:ipetkov/crane";
      inputs = {
        flake-utils.follows = "flake-utils";
        nixpkgs.follows = "nixpkgs";
      };
    };
  };

  outputs =
    { self
    , nixpkgs
    , flake-utils
    , fenix
    , devenv
    , crane
    , nixpkgs-unstable
    } @ inputs:
    flake-utils.lib.eachDefaultSystem (system:
    let
      pkgs = import nixpkgs
        {
          inherit system;
          overlays = [
            fenix.overlays.default
            (self: super: {
              unstable = (import nixpkgs-unstable { inherit system; });
            })
          ];
        };

      nativeBuildInputs = with pkgs;
        [
          pkg-config
          openssl
        ] ++ lib.optionals
          stdenv.isDarwin
          (with darwin.apple_sdk; [
            libiconv
            frameworks.Security
          ]);

      buildInputs = with pkgs; [
        cargo-nextest
      ];

      rustToolchain = fenix.packages.${system}.fromToolchainFile
        {
          file = ./rust-toolchain.toml;
          # sha256 = pkgs.lib.fakeSha256;
          sha256 = "sha256-S7epLlflwt0d1GZP44u5Xosgf6dRrmr8xxC+Ml2Pq7c=";
        };
    in
    rec {
      packages =
        with pkgs;
        let
          craneLib = crane.lib.${system}.overrideToolchain rustToolchain;
          # src = craneLib.cleanCargoSource ./.;
          # https://github.com/ipetkov/crane/blob/d78cb0453b9823d2102f7b22bb98686215462416/docs/API.md#libfiltercargosources
          jsonFilter = path: _type:
            !builtins.isNull (builtins.match ".*json$" path);
          jsonOrCargo = path: type:
            (jsonFilter path type) || (craneLib.filterCargoSources path type);
          src = lib.cleanSourceWith {
            src = ./.;
            filter = jsonOrCargo;
          };
          cargoArtifacts = craneLib.buildDepsOnly {
            inherit src nativeBuildInputs;
          };
          rustPackage = craneLib.buildPackage {
            inherit src nativeBuildInputs buildInputs cargoArtifacts;

            # # until this is clear https://github.com/ipetkov/crane/discussions/196
            doCheck = false;
          };
          rustTest = craneLib.mkCargoDerivation {
            inherit src nativeBuildInputs buildInputs;

            cargoArtifacts = craneLib.buildDepsOnly {
              inherit src nativeBuildInputs buildInputs;
              CARGO_PROFILE = "";
            };

            buildPhaseCargoCommand = ''
              mkdir -p $out
              cargo nextest archive --archive-file $out/archive.tar.zst
            '';
          };
        in
        {
          rustPackage = rustPackage;
          rustTest = rustTest;

          docker = dockerImage null;
          dockerLocal = dockerImage "local";
        };

      defaultPackage = packages.docker;

      devShell =
        devenv.lib.mkShell {
          inherit inputs pkgs;

          modules = with pkgs; [
            {
              env.RUSTC_WRAPPER = "${pkgs.sccache}/bin/sccache";

              packages = [
                sccache
                cargo-watch
                cargo-nextest
                unstable.cargo-release
              ] ++ buildInputs;

              env.RUSTFLAGS = (builtins.map (a: ''-L ${a}/lib'') nativeBuildInputs) ++ (lib.optionals stdenv.isDarwin (with darwin.apple_sdk; [
                "-L framework=${frameworks.Security}/Library/Frameworks"
              ]));

              # https://devenv.sh/languages/
              languages.nix.enable = true;
              languages.rust = {
                enable = true;
                version = "stable";
              };

              scripts.cargo-udeps.exec = ''
                PATH=${fenix.packages.${system}.latest.rustc}/bin:$PATH
                ${pkgs.cargo-udeps}/bin/cargo-udeps $@
              '';

              # https://github.com/nektos/act/issues/1184#issuecomment-1248575427
              # non-root runner is required for nix
              scripts.act.exec = ''
                ${pkgs.act}/bin/act -P ubuntu-latest=ghcr.io/catthehacker/ubuntu:runner-latest $@
              '';

              # https://devenv.sh/pre-commit-hooks/
              pre-commit.hooks = {
                shellcheck.enable = true;

                clippy.enable = true;
                rustfmt.enable = true;
              };
            }
          ];
        };
    });
}
