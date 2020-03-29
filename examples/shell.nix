let
  nix-bitcoin-src-derivation = release: (import <nixpkgs> {}).stdenv.mkDerivation {
    name = "nix-bitcoin-src";
    src = builtins.fetchurl release;
    sourceRoot = "./";
    installPhase = ''
    cp -r . $out
    '';
  };
  # This is either a path to a local nix-bitcoin source or an attribute set to
  # be used as the fetchurl argument.
  nix-bitcoin-release = import ./nix-bitcoin-release.nix;
  nix-bitcoin-path = (if (builtins.isAttrs nix-bitcoin-release)
    then (nix-bitcoin-src-derivation nix-bitcoin-release)
    else nix-bitcoin-release);
  nixpkgs-path = (import "${toString nix-bitcoin-path}/pkgs/nixpkgs-pinned.nix").nixpkgs;
  nixpkgs = import nixpkgs-path {};
  nix-bitcoin = nixpkgs.callPackage nix-bitcoin-path {};

  extraContainer = nixpkgs.callPackage (builtins.fetchTarball {
    url = "https://github.com/erikarvstedt/extra-container/archive/6cced2c26212cc1c8cc7cac3547660642eb87e71.tar.gz";
    sha256 = "0qr41mma2iwxckdhqfabw3vjcbp2ffvshnc3k11kwriwj14b766v";
  }) {};
in
with nixpkgs;

stdenv.mkDerivation rec {
  name = "nix-bitcoin-environment";

  buildInputs = [ nix-bitcoin.nixops19_09 figlet extraContainer ];

  shellHook = ''
    export NIX_PATH="nixpkgs=${nixpkgs-path}:nix-bitcoin=${toString nix-bitcoin-path}:."
    export PATH=${lib.makeBinPath [ nix-bitcoin.nix-bitcoin-release ]}:$PATH

    # ssh-agent and nixops don't play well together (see
    # https://github.com/NixOS/nixops/issues/256). I'm getting `Received disconnect
    # from 10.1.1.200 port 22:2: Too many authentication failures` if I have a few
    # keys already added to my ssh-agent.
    export SSH_AUTH_SOCK=""

    figlet "nix-bitcoin"
    (mkdir -p secrets; cd secrets; ${nix-bitcoin.generate-secrets})
  '';
}