# Building WMDiscord

WMDiscord uses GNUstep AppKit for its Objective-C interface, POSIX APIs for sockets and threads, Xlib for X11 integration, and libcurl for HTTPS requests.

## Dependencies

You need:

- GCC with Objective-C support
- GNU Make
- GNUstep Make
- GNUstep Base
- GNUstep GUI
- A GNUstep X11 backend
- X11 development headers and libraries (`libX11`, `libXext`)
- libcurl development headers
- Fontconfig (recommended for Unicode fallback)

On Arch Linux / EndeavourOS, the repository dependencies commonly include:

```sh
yay -S --needed base-devel gcc-objc gnustep-make gnustep-base \
  pkgconf curl libx11 libxext fontconfig
```

GNUstep GUI and its backend may be separate AUR packages (`gnustep-gui` and `gnustep-back`). Package metadata can change; use the distribution's current package instructions. Do not replace an installed JPEG implementation solely to satisfy a stale third-party package dependency.

## Compile

From the repository root:

```sh
export GNUSTEP_MAKEFILES="$(gnustep-config --variable=GNUSTEP_MAKEFILES)"
make clean
make
```

The executable is inside the GNUstep application bundle:

```sh
./WMDiscord.app/WMDiscord
```

The simulated roster can be launched without a Discord session:

```sh
./WMDiscord.app/WMDiscord --demo
```

## Tests and diagnostics

```sh
./scripts/dev-check.sh
./scripts/test.sh
./scripts/check-fonts.sh
```

The model test covers participant state transitions. It does not validate the complete AppKit window, the Discord RPC service, or fullscreen-game behavior.

## Build verification status

The 0.3.1 source compiled and linked on an EndeavourOS system with Window Maker on X11. The reported demo test did not show a visible window. A 0.3.2 follow-up source snapshot was prepared, but its build and GUI behavior were not confirmed end-to-end. The source should be treated as experimental.
