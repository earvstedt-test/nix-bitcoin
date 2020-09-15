{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.lightning-loop;
  inherit (config) nix-bitcoin-services;
  secretsDir = config.nix-bitcoin.secretsDir;
  configFile = pkgs.writeText "loopd.conf" ''
    datadir=${cfg.dataDir}
    logdir=${cfg.dataDir}/logs
    tlscertpath=${secretsDir}/loop-cert
    tlskeypath=${secretsDir}/loop-key

    lnd.host=${config.services.lnd.listen}:10009
    lnd.macaroondir=${config.services.lnd.dataDir}/chain/bitcoin/mainnet
    lnd.tlspath=${secretsDir}/lnd-cert

    ${optionalString (cfg.proxy != null) "server.proxy=${cfg.proxy}"}

    ${cfg.extraConfig}
  '';
in {

  options.services.lightning-loop = {
    enable = mkEnableOption "lightning-loop";
    package = mkOption {
      type = types.package;
      default = pkgs.nix-bitcoin.lightning-loop;
      defaultText = "pkgs.nix-bitcoin.lightning-loop";
      description = "The package providing lightning-loop binaries.";
    };
    dataDir = mkOption {
      type = types.path;
      default = "/var/lib/lightning-loop";
      description = "The data directory for Loop.";
    };
    proxy = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Connect through SOCKS5 proxy";
    };
    extraConfig = mkOption {
      type = types.lines;
      default = "";
      example = ''
        debuglevel=trace
      '';
      description = "Extra command line arguments passed to loopd.";
    };
    cli = mkOption {
      default = pkgs.writeScriptBin "loop"
      # Switch user because lnd makes datadir contents readable by user only
      ''
        ${cfg.cliExec} sudo -u lnd ${cfg.package}/bin/loop --tlscertpath ${secretsDir}/loop-cert "$@"
      '';
      description = "Binary to connect with the lnd instance.";
    };
    inherit (nix-bitcoin-services) cliExec;
    enforceTor =  nix-bitcoin-services.enforceTor;
  };

  config = mkIf cfg.enable {
    assertions = [
      { assertion = config.services.lnd.enable;
        message = "lightning-loop requires lnd.";
      }
    ];

    environment.systemPackages = [ cfg.package (hiPrio cfg.cli) ];

    systemd.tmpfiles.rules = [
      "d '${cfg.dataDir}' 0770 lnd lnd - -"
    ];

    systemd.services.lightning-loop = {
      description = "Run loopd";
      wantedBy = [ "multi-user.target" ];
      requires = [ "lnd.service" ];
      after = [ "lnd.service" ];
      preStart = ''
        install -m600 ${configFile} '${cfg.dataDir}/loopd.conf'
      '';
      serviceConfig = nix-bitcoin-services.defaultHardening // {
        WorkingDirectory = cfg.dataDir;
        ExecStart = "${cfg.package}/bin/loopd --configfile=${cfg.dataDir}/loopd.conf";
        User = "lnd";
        Restart = "on-failure";
        RestartSec = "10s";
        ReadWritePaths = "${cfg.dataDir}";
      } // (if cfg.enforceTor
          then nix-bitcoin-services.allowTor
          else nix-bitcoin-services.allowAnyIP);
    };

     nix-bitcoin.secrets = {
       loop-key.user = "lnd";
       loop-cert.user = "lnd";
     };
  };
}
