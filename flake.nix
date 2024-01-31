{
  description = "Tagion is a decentrialized monetary system";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      gitRev =
        if (builtins.hasAttr "rev" self)
        then self.rev
        else "dirty";

      # BlockstreamResearch secp256k1-zkp fork
      secp256k1-zkp = with import nixpkgs { system = "x86_64-linux"; };
        stdenv.mkDerivation rec {
          pname = "secp256k1-zkp";

          version = "0.3.2";

          src = fetchFromGitHub {
            owner = "BlockstreamResearch";
            repo = "secp256k1-zkp";
            rev = "d575ef9aca7cd1ed79735c95ec9f296554ea1df7";
            sha256 = "sha256-Z8TrMxlNduPc4lEzA34jjo75sUJYh5fLNBnXg7KJy8I=";
          };

          nativeBuildInputs = [ autoreconfHook ];

          configureFlags = [
            "--enable-experimental"
            "--enable-benchmark=no"
            "--enable-module-recovery"
            "--enable-module-schnorrsig"
            "--enable-module-musig"
          ];

          doCheck = true;

        };
    in
    {

      formatter.x86_64-linux = nixpkgs.legacyPackages.x86_64-linux.nixpkgs-fmt;

      packages.x86_64-linux.default =
        # Notice the reference to nixpkgs here.
        with import nixpkgs { system = "x86_64-linux"; };
        stdenv.mkDerivation {
          name = "tagion";

          buildInputs = [
            nng
            secp256k1-zkp
            mbedtls
          ];

          nativeBuildInputs = [
            dmd
            dtools
            gnumake
            pkg-config
          ];

          src = self;

          configurePhase = ''
            echo DC=dmd >> local.mk
            echo USE_SYSTEM_LIBS=1 >> local.mk
            echo INSTALL=$out/bin >> local.mk
            echo NNG_ENABLE_TLS=1 >> local.mk
          '';

          buildPhase = ''
            make GIT_HASH=${gitRev} tagion
          '';

          installPhase = ''
            mkdir -p $out/bin; make install
          '';
        };

      devShells.x86_64-linux.default =
        # Notice the reference to nixpkgs here.
        with import nixpkgs { system = "x86_64-linux"; };
        mkShell {
          buildInputs = [
            self.packages.x86_64-linux.default.nativeBuildInputs
            self.packages.x86_64-linux.default.buildInputs
            dub
            ldc
            gcc
            git
            libtool
            autoconf
            automake
            autoreconfHook
            cmake
          ];
        };

      # Experimental work on nix unittest build. execute using nix build .#unittest
      # Idea is to use this along with nix run in order to run unittests with nix
      packages.x86_64-linux.unittest =
        with import nixpkgs { system = "x86_64-linux"; };
        stdenv.mkDerivation {
          name = "unittest";

          buildInputs = [
            nng
            secp256k1-zkp
            mbedtls
          ];

          nativeBuildInputs = [
            dmd
            dtools
            gnumake
            pkg-config
          ];

          src = self;
          configurePhase = ''
            echo DC=dmd >> local.mk
            echo INSTALL=$out/bin >> local.mk
            echo NNG_ENABLE_TLS=1 >> local.mk
          '';

          buildPhase = ''
            make GIT_HASH=${gitRev} proto-unittest-build
          '';

          installPhase = ''
            mkdir -p $out/bin; make install-bin
          '';
        };
      packages.x86_64-linux.dockerImage =
        with import nixpkgs { system = "x86_64-linux"; };
        dockerTools.buildImage {
          name = "tagion-docker";
          tag = "latest";
          fromImage = dockerTools.pullImage {
            imageName = "alpine";
            imageDigest = "sha256:13b7e62e8df80264dbb747995705a986aa530415763a6c58f84a3ca8af9a5bcd";
            sha256 = "sha256-6tIIMFzCUPRJahTPoM4VG3XlD7ofFPfShf3lKdmKSn0=";
            finalImageName = "alpine";
            os = "linux";
            arch = "x86_64";
          };
          copyToRoot = pkgs.buildEnv {
            name = "image-root";
            paths = [ self.packages.x86_64-linux.default ];
            pathsToLink = [ "/bin" ];
          };

          # contents = [ self.packages.x86_64-linux.default];
          config = {
            Cmd = [ "/bin/sh" ];
            Env = [ ];
            Volumes = { };
          };
        };
    };
}
