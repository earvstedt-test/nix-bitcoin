#!/usr/bin/env bash

# Modules integration test runner.
# The test (./test.nix) uses the NixOS testing framework and is executed in a VM.
#
# Usage:
#   Run test
#   ./run-tests.sh
#
#   Run test and save result to avoid garbage collection
#   ./run-tests.sh build --out-link /tmp/nix-bitcoin-test
#
#   Run interactive test debugging
#   ./run-tests.sh debug
#
#   This starts the testing VM and drops you into a Python REPL where you can
#   manually execute the tests from ./test-script.py

set -eo pipefail

numCPUs=${numCPUs:-$(nproc)}
# Min. 800 MiB needed to avoid 'out of memory' errors
memoryMiB=${memoryMiB:-2048}

scriptDir=$(cd "${BASH_SOURCE[0]%/*}" && pwd)

export NIX_PATH=nixpkgs=$(nix eval --raw -f "$scriptDir/../pkgs/nixpkgs-pinned.nix" nixpkgs)

# Run the test. No temporary files are left on the host system.
run() {
    # TMPDIR is also used by the test driver for VM tmp files
    export TMPDIR=$(mktemp -d -p /tmp nix-bitcoin-test.XXXXXX)
    trap "rm -rf $TMPDIR" EXIT

    nix-build --out-link $TMPDIR/driver "$scriptDir/test.nix" -A driver

    # Variable 'tests' contains the Python code that is executed by the driver on startup
    if [[ $1 == --interactive ]]; then
        echo "Running interactive testing environment"
        tests=$(
            echo 'is_interactive = True'
            # The test script raises an error when 'is_interactive' is defined so
            # that it just loads the initial helper functions and stops before
            # executing the actual tests
            echo 'try:'
            echo '    exec(os.environ["testScript"])'
            echo 'except:'
            echo '    pass'
            # Start VM
            echo 'start_all()'
            # Start REPL
            echo 'import code'
            echo 'code.interact(local=globals())'
        )
    else
        tests='exec(os.environ["testScript"])'
    fi

    echo "VM stats: CPUs: $numCPUs, memory: $memoryMiB MiB"
    [[ $NB_TEST_ENABLE_NETWORK ]] || QEMU_NET_OPTS='restrict=on'
    env -i \
        NIX_PATH="$NIX_PATH" \
        TMPDIR="$TMPDIR" \
        tests="$tests" \
        QEMU_OPTS="-smp $numCPUs -m $memoryMiB -nographic $QEMU_OPTS"  \
        QEMU_NET_OPTS="$QEMU_NET_OPTS" \
        $TMPDIR/driver/bin/nixos-test-driver
}

debug() {
    run --interactive
}

# Run the test by building the test derivation
build() {
    vmTestNixExpr | nix-build --no-out-link "$@" -
}

# On continuous integration nodes there are few other processes running alongside the
# test, so use more memory here for maximum performance.
exprForCI() {
    memoryMiB=3072
    memTotalKiB=$(awk '/MemTotal/ { print $2 }' /proc/meminfo)
    memAvailableKiB=$(awk '/MemAvailable/ { print $2 }' /proc/meminfo)
    # Round down to nearest multiple of 50 MiB for improved test build caching
    ((memAvailableMiB = memAvailableKiB / (1024 * 50) * 50))
    ((memAvailableMiB < memoryMiB)) && memoryMiB=$memAvailableMiB
    >&2 echo "Host memory: total $((memTotalKiB / 1024)) MiB, available $memAvailableMiB MiB, VM $memoryMiB MiB"
    vmTestNixExpr
}

vmTestNixExpr() {
  cat <<EOF
    (import "$scriptDir/test.nix" {}).overrideAttrs (old: rec {
      buildCommand = ''
        export QEMU_OPTS="-smp $numCPUs -m $memoryMiB"
        echo "VM stats: CPUs: $numCPUs, memory: $memoryMiB MiB"
      '' + old.buildCommand;
    })
EOF
}

eval "${@:-build}"
