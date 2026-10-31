#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
set -eu
cd "$(dirname "$0")/.."

fail() { echo "ERROR: $*" >&2; exit 1; }

# Arch/EndeavourOS calls GNU Make's package `make` and installs the
# executable as /usr/bin/make. Some other systems expose it as `gmake`.
MAKE_BIN=$(command -v make 2>/dev/null || command -v gmake 2>/dev/null || true)
[ -n "$MAKE_BIN" ] || fail "GNU Make is missing (Arch package: make)"

command -v gnustep-config >/dev/null 2>&1 || fail "gnustep-config is missing; install GNUstep Make and Base development packages"
command -v pkg-config >/dev/null 2>&1 || fail "pkg-config is missing (Arch package: pkgconf)"

# Discover GNUstep's makefile directory if the shell environment was not
# initialized. This is the path used by the Arch gnustep-make package.
if [ -z "${GNUSTEP_MAKEFILES:-}" ]; then
    GS_MAKEFILES=$(gnustep-config --variable=GNUSTEP_MAKEFILES 2>/dev/null || true)
    if [ -n "$GS_MAKEFILES" ] && [ -d "$GS_MAKEFILES" ]; then
        export GNUSTEP_MAKEFILES="$GS_MAKEFILES"
    fi
fi
if [ -z "${GNUSTEP_MAKEFILES:-}" ]; then
    for GS_ENV in /usr/share/GNUstep/Makefiles/GNUstep.sh /usr/lib/GNUstep/Makefiles/GNUstep.sh; do
        if [ -r "$GS_ENV" ]; then
            # shellcheck disable=SC1090
            . "$GS_ENV"
            break
        fi
    done
fi
[ -n "${GNUSTEP_MAKEFILES:-}" ] || fail "GNUSTEP_MAKEFILES is unset; source your distribution's GNUstep.sh"
[ -f "$GNUSTEP_MAKEFILES/common.make" ] || fail "GNUstep makefiles not found at $GNUSTEP_MAKEFILES"

pkg-config --exists libcurl || fail "libcurl development files are missing"
pkg-config --exists x11 || fail "X11 development files are missing"

# Verify the AppKit headers and Objective-C compiler front end are available.
OBJC_CC=${OBJC:-gcc}
command -v "$OBJC_CC" >/dev/null 2>&1 || fail "Objective-C compiler '$OBJC_CC' not found (Arch package: gcc-objc)"
XEXT_PROBE=$(mktemp "${TMPDIR:-/tmp}/wmdiscord-xext-probe.XXXXXX")
if ! printf '#include <X11/Xlib.h>\n#include <X11/extensions/shape.h>\nint main(void) { return 0; }\n' | \
    "$OBJC_CC" -x c - -o "$XEXT_PROBE" -lX11 -lXext >/dev/null 2>&1; then
    rm -f "$XEXT_PROBE"
    fail "X Shape headers/library are missing (Arch package: libxext)"
fi
rm -f "$XEXT_PROBE"
if ! printf '#import <AppKit/AppKit.h>\nint main(void) { return 0; }\n' | \
    "$OBJC_CC" -x objective-c $(gnustep-config --objc-flags) -fsyntax-only - >/dev/null 2>&1; then
    fail "GNUstep AppKit headers/compiler are unavailable; install GNUstep GUI development files and gcc-objc"
fi

printf 'GNU Make: %s\n' "$MAKE_BIN"
printf 'GNUstep Makefiles: %s\n' "$GNUSTEP_MAKEFILES"
printf 'Objective-C compiler: %s\n' "$OBJC_CC"
printf 'libcurl: %s\n' "$(pkg-config --modversion libcurl)"
printf 'X11: %s\n' "$(pkg-config --modversion x11)"
printf 'X Shape extension: available (-lXext)\n'
printf '\nDependency check passed. Build with: %s\n' "${MAKE_BIN##*/}"
