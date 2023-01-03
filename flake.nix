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
    nix-rust-utils.url = "github:onsails/nix-rust-utils";
  };

  outputs =
    { self
    , nixpkgs
    , flake-utils
    , fenix
    , devenv
    , crane
    , nixpkgs-unstable
    , nix-rust-utils
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
          src = nix-rust-utils.cleanSourceWithExts {
            inherit pkgs craneLib;
            src = ./.;
            exts = "json";
          };
          cargoArtifacts = craneLib.buildDepsOnly {
            inherit src nativeBuildInputs;
          };
          rustPackage = craneLib.buildPackage {
            inherit src nativeBuildInputs buildInputs cargoArtifacts;

            # # until this is clear https://github.com/ipetkov/crane/discussions/196
            doCheck = false;
          };
          rustTest = nix-rust-utils.mkNextest {
            inherit src craneLib pkgs buildInputs;
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

          modules = with pkgs;
            (nix-rust-utils.mkDevenvModules {
              inherit pkgs rustToolchain;
              libs = nativeBuildInputs;
            }) ++ [
              {
                env.RUSTC_WRAPPER = "${pkgs.sccache}/bin/sccache";

                packages = [
                  sccache
                  cargo-watch
                  cargo-nextest
                  unstable.cargo-release
                  cargo-semver-checks
                ] ++ buildInputs;

                # https://devenv.sh/languages/
                languages.nix.enable = true;

                # https://github.com/nektos/act/issues/1184#issuecomment-1248575427
                # non-root runner is required for nix
                scripts.act.exec = ''
                  ${pkgs.act}/bin/act -P ubuntu-latest=ghcr.io/catthehacker/ubuntu:runner-latest \
                  $@
                '';

                scripts.release.exec = ''
                  cargo semver-checks check-release
                  release-unchecked $@
                '';

                scripts.release-unchecked.exec = ''
                  cargo release --execute $@
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
