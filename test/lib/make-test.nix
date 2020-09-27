scenario: testConfig:

{
  vm = import ./make-test-vm.nix {
    name = "nix-bitcoin-${scenario}";

    machine = {
      imports = [ testConfig ];
      # Needed because duplicity requires 270 MB of free temp space, regardless of backup size
      virtualisation.diskSize = 1024;
    };

    testScript = nodes: let
      cfg = nodes.nodes.machine.config;
      data = {
        data = cfg.test.data;
        tests = cfg.tests;
      };
      dataFile = builtins.toFile "test-data" (builtins.toJSON data);
      initData = ''
        import json

        with open("${dataFile}") as f:
            data = json.load(f)

        enabled_tests = set(test for (test, enabled) in data["tests"].items() if enabled)
        test_data = data["data"]
      '';
    in
      builtins.concatStringsSep "\n\n" [
        initData
        (builtins.readFile ./../tests.py)
        # Don't run tests in interactive mode.
        # is_interactive is set in ./run-tests.sh
        ''
          if not "is_interactive" in vars():
              run_tests()
        ''
      ];
  };

  container = { config, pkgs, lib, ... }: let
    containerName = "nb-test"; # 11 char length limit
    cfg = config.containers.${containerName}.config.test.container;
    containerAddress = "${cfg.addressPrefix}.2";
    hostAddress = "${cfg.addressPrefix}.1";
  in {
    containers.${containerName} = {
      privateNetwork = true;
      localAddress = containerAddress;
      inherit hostAddress;
      config = {
        imports = [
          testConfig
        ];

        # Always accept connections from the host system
        networking.firewall = {
          enable = true;
          extraCommands = ''
            iptables -w -A nixos-fw -s ${hostAddress} -j ACCEPT
          '';
        };

        services.openssh.enable = true;
        users.users.root = {
          openssh.authorizedKeys.keyFiles = [ ./../../examples/ssh-keys/id-nb.pub ];
        };

        systemd.services.forward-to-localhost = lib.mkIf cfg.forwardToLocalhost {
          wantedBy = [ "multi-user.target" ];
          script = ''
            ${pkgs.procps}/bin/sysctl -w net.ipv4.conf.all.route_localnet=1
            ${pkgs.iptables}/bin/iptables -t nat -I PREROUTING -p tcp \
              -d ${containerAddress} ! --dport 80 -j DNAT --to-destination 127.0.0.1
          '';
        };
      };
    };
    # Allow WAN access
    systemd.services."container@${containerName}" = lib.mkIf cfg.enableWAN {
      preStart = "${pkgs.iptables}/bin/iptables -w -t nat -A POSTROUTING -s ${containerAddress} -j MASQUERADE";
      postStop = "${pkgs.iptables}/bin/iptables -w -t nat -D POSTROUTING -s ${containerAddress} -j MASQUERADE || true";
    };
  };
}
