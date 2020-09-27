{ config, lib, ... }:
with lib;
{
  options = {
    test = {
      noConnections = mkOption {
        type = types.bool;
        default = !config.test.container.enableWAN;
        description = ''
          Whether services should be configured to not connect to external hosts.
          This can silence some warnings while running the test in an offline environment.
        '';
      };
      data = mkOption {
        type = types.attrs;
        default = {};
        description = ''
          Attrs that are available in the Python test script under the global
          dictionary variable 'test_data'. The data is exported via JSON.
        '';
      };

      container = {
        enableWAN = mkEnableOption "container WAN access";
        addressPrefix = mkOption {
          type = types.str;
          default = "10.225.255";
          description = "The 24 bit prefix of the container addresses.";
        };
        forwardToLocalhost = mkOption {
          type = types.bool;
          default = false;
          description = ''
            Forward requests from the container's address to the container's localhost.
            Useful to test internal services from outside the container.
          '';
        };
      };
    };

    tests = mkOption {
      type = with types; attrsOf bool;
      default = {};
      description = "Python tests that should be run.";
    };
  };
}
