# Integration test, can be run without internet access.

import <nixpkgs/nixos/tests/make-test.nix> ({ lib, ... } : rec {
  name = "nix-bitcoin";

  hardened = {
    imports = [ <nixpkgs/nixos/modules/profiles/hardened.nix> ];
    security.allowUserNamespaces = true; # reenable disabled option
  };

  machine = { pkgs, ... }: with lib; {
    imports = [
      ../modules/nix-bitcoin.nix
      ../modules/secrets/generate-secrets.nix
      # using the hardened profile increases total test duration by ~50%, so disable it for now
      # hardened
    ];

    services.nix-bitcoin.enable = true;
    services.bitcoind.extraConfig = mkForce "connect=0";

    services.clightning.enable = true;
    services.spark-wallet.enable = true;
    services.lightning-charge.enable = true;
    services.nanopos.enable = true;

    services.lnd.enable = true;
    systemd.services.lnd.wantedBy = mkForce [];

    services.electrs.enable = true;

    services.liquidd = {
      enable = true;
      listen = mkForce false;
      extraConfig = "noconnect=1";
    };

    services.nix-bitcoin-webindex.enable = true;

    services.hardware-wallets = {
      trezor = true;
      ledger = true;
    };

    # to test that unused secrets are made inaccessible by 'setup-secrets'
    systemd.services.generate-secrets.postStart = ''
      install -o nobody -g nogroup -m777 <(:) /secrets/dummy
    '';
  };

  testScript = builtins.readFile ./test-script.pl;
})
