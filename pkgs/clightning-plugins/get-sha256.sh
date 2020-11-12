#! /usr/bin/env nix-shell
#! nix-shell -i bash -p git
set -euo pipefail

archive_hash () {
    repo=$1
    rev=$2
    nix-prefetch-url --unpack "https://github.com/${repo}/archive/${rev}.tar.gz" 2> /dev/null | tail -n 1
}

TMPDIR="$(mktemp -d -p /tmp)"
trap "rm -rf $TMPDIR" EXIT

cd "$TMPDIR"
echo "Fetching latest DavHau/mach-nix release"
git clone https://github.com/DavHau/mach-nix 2> /dev/null
cd mach-nix

latest=$(git describe --tags `git rev-list --tags --max-count=1`)
echo "Latest release is ${latest}"
echo "sha256: $(archive_hash DavHau/mach-nix $latest)"

cd "$TMPDIR"
echo "Fetching latest lightningd/plugins release"
git clone https://github.com/lightningd/plugins 2> /dev/null
cd plugins

latest="$(git rev-parse master)"
echo "ref: ${latest}"
echo "sha256: $(archive_hash lightningd/plugins $latest)"
