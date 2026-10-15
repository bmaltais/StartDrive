#!/bin/bash
# Builds vptr, the virtual-pointer client the nested tour recorder uses, into the folder given (default: here).
# Needs gcc, wayland-scanner and the wayland client library (pkg-config wayland-client).
set -eu
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
out=${1:-$here}
mkdir -p "$out"
wayland-scanner client-header "$here/wlr-virtual-pointer-unstable-v1.xml" "$out/wlr-virtual-pointer-unstable-v1-client-protocol.h"
wayland-scanner private-code "$here/wlr-virtual-pointer-unstable-v1.xml" "$out/wlr-virtual-pointer-unstable-v1-protocol.c"
# shellcheck disable=SC2046
gcc -O2 -Wall -I"$out" -o "$out/vptr" "$here/vptr.c" "$out/wlr-virtual-pointer-unstable-v1-protocol.c" $(pkg-config --cflags --libs wayland-client)
