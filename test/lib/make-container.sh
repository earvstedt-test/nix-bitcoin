#!/usr/bin/env bash

# Usage:
#
#   run-tests.sh [--scenario|-s <scenario>] container
#
#     Start container and start a shell session with helper commands
#     for accessing the container.
#     A short command documentation is printed at the start of the session.
#     The container is destroyed after exiting the shell.
#     An existing container is destroyed before starting.
#
#     When running this command from inside an existing shell session,
#     the current container is updated without restarting by switching
#     its NixOS configuration.
#     Provide arg --destroy|-d to destroy and restart the container instead.
#
#   run-tests.sh [--scenario|-s <scenario>] container --create|-c
#
#     Create and start container.
#
#   run-tests.sh container --run|-r c systemctl status bitcoind
#
#     Run a command in the shell session environmentand exit.
#     Destroy the container afterwards.
#     All arguments following `--run` are used as a command.
#
#     Example: Start shell inside container
#     run-tests.sh container --run c
#
#
#   The following args can be combined with all other args:
#
#   --no-destroy|-n
#
#     By default, all commands destroy an existing container before starting and,
#     when appropriate, before exiting.
#     This ensures that containers start with no leftover filesystem state from
#     previous runs and that containers don't consume system resources after use.
#     This args disables auto-destructing containers.
#
#   --command|--cmd
#
#     Provide a custom extra-container command.
#
#   All extra args are passed to extra-container:
#   run-tests.sh container --build-args --builders 'ssh://worker - - 8'

set -eo pipefail

if [[ $EUID != 0 ]]; then
    # NixOS containers require root permissions.
    # By using sudo here and not at the user's call-site this script can detect if it is running
    # inside an existing shell session (by checking var `insideContainerSession`).
    exec sudo scenario="$scenario" testDir="$testDir" NIX_PATH="$NIX_PATH" \
         scenarioOverridesFile="$scenarioOverridesFile" "$testDir/lib/make-container.sh" "$@"
fi

if [[ $(sysctl -n net.ipv4.ip_forward) != 1 ]]; then
    echo "Error: IP forwarding (net.ipv4.ip_forward) is not enabled"
    exit 1
fi
if [[ ! -e /run/current-system/nixos-version ]]; then
    echo "Error: This script needs NixOS to run"
    exit 1
fi

export containerName=nb-test
containerCommand="create --start"
startShell=1
destroy=1
forceDestroy=
runCommand=

while :; do
    case $1 in
        --create|-c)
            shift
            startShell=
            ;;
        --run|-r)
            shift
            startShell=
            runCommand=("$@")
            set --
            ;;
        --no-destroy|-n)
            destroy=
            shift
            ;;
        --destroy|-d)
            destroy=1
            forceDestroy=1
            shift
            ;;
        --command|-o)
            containerCommand=$2
            shift
            shift
            ;;
        *)
            break
    esac
done

if ! type -P extra-container > /dev/null; then
    echo "Building extra-container."
    echo "Hint: Skip this step by adding extra-container to PATH."
    nix-build --out-link /tmp/extra-container "$testDir"/../pkgs -A extra-container
    export PATH="/tmp/extra-container/bin${PATH:+:}$PATH"
fi

afterContainerCreated() {
    if [[ $startNewShell ]]; then
        # This usually only fails when container creation was interrupted.
        # Ignore error messages in this case.
        containerIp=$(extra-container show-ip $containerName 2> /dev/null) || exit 1
    else
        containerIp=$(extra-container show-ip $containerName)
    fi

    echo "Container address: $containerIp ${startShell:+(\$ip)}"
    echo "Container filesystem: /var/lib/containers/$containerName"

    if [[ ! ($startNewShell || $runCommand) ]]; then
        exit
    fi

    tmpDir=$(mktemp -d nix-bitcoin-container.XXX)
    atExit() {
        rm -rf "$tmpDir"
        if [[ $destroy ]]; then
            echo "Destroying container."
            extra-container destroy $containerName
        fi
    }
    trap "atExit" EXIT

    install -m 600 "$testDir/../examples/ssh-keys/id-nb" "$tmpDir/key"

    c() {
        if [[ $# > 0 ]]; then
            extra-container run $containerName -- "$@" | cat;
        else
            nixos-container root-login $containerName
        fi
    }
    cssh() {
        ssh -i "$tmpDir/key" -o ConnectTimeout=1 \
            -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR \
            -o ControlMaster=auto -o ControlPath=$tmpDir/ssh-connection -o ControlPersist=60 \
            root@$containerIp "$@"
    }
    export ip=$containerIp

    echo
    if [[ $runCommand ]]; then
        echo "Running command."
        "${runCommand[0]}" "${runCommand[@]:1}"
        echo
    else
        echo 'Starting shell.'
        echo 'Run "c COMMAND" to execute a command in the container'
        echo 'Run "c" to start a shell session inside the container'
        echo 'Run "cssh" for SSH'

        export -f c cssh
        bash --rcfile <(echo 'export insideContainerSession=1')
    fi
}

if [[ ($startShell && $insideContainerSession && ! $forceDestroy) ]]; then
    destroy=
fi

if [[ $destroy ]]; then
    extra-container destroy $containerName
fi

[[ $startShell && ! $insideContainerSession ]] && startNewShell=1 || startNewShell=

if [[ $startNewShell ]]; then
    # When starting a shell, continue the script when container creation gets interrupted.
    # This way, the user can interrupt waiting for the startup of all services
    # and interact with the starting container.
    # If the interrupt happens before the container is reachable
    # (indicated by the failure of `extra-container show-ip`), the script exits.
    trap afterContainerCreated SIGINT
fi

# Create container
extra-container $containerCommand "$@" <<EOF
(import "$testDir/tests.nix" { scenario = "$scenario"; }).container
EOF

afterContainerCreated
