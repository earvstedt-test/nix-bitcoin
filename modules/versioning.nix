{ config, pkgs, lib, ... }:

with lib;
let
  version = config.nix-bitcoin.configVersion;

  # Sorted by increasing version numbers
  changes = [
    {
      version = "0.0.18";
      condition = config.services.lightning-loop.enable;
      message = ''
        The lightning-loop data dir location was changed.
        To move it to the new location, run the following shell command on your nix-bitcoin node:
        sudo mv ${config.services.lnd.dataDir}/.loop ${config.services.lightning-loop.dataDir}
      '';
    }
    {
      version = "0.1";
      message = ''
        dummy
      '';
    }
  ];

  incompatibleChanges = optionals
    (version != null && versionOlder lastChange)
    (builtins.filter (change: versionOlder change && (change.condition or true)) changes);

  messagesStr = ''

    This version of nix-bitcoin contains the following changes
    that are incompatible with your config (version ${version}):

    ${concatMapStringsSep "\n" (change: ''
      - ${change.message}(This change was introduced in version ${change.version})
    '') incompatibleChanges}
    After addressing the above changes, set nix-bitcoin.configVersion = "${lastChange.version}";
    in your nix-bitcoin configuration.
  '';

  lastChange = builtins.elemAt changes (builtins.length changes - 1);
  versionOlder = change: (builtins.compareVersions change.version version) > 0;
in
{
  options = {
    nix-bitcoin.configVersion = mkOption {
      type = with types; nullOr str;
      default = null;
      description = ''
        Set this option to the nix-bitcoin release version that your config is
        compatible with.

        When upgrading to a backwards-incompatible release, nix-bitcoin will throw an
        error during evaluation and provide hints for migrating your config to the
        new release.
      '';
    };
  };

  ## No config because there are no backwards incompatible releases yet
  config = {
    # Force evaluation. An actual option value is never assigned
    system.extraDependencies = optional (builtins.length incompatibleChanges > 0) (builtins.throw messagesStr);
  };
}
