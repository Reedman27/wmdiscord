# WMDiscord

> **Archived project — preserved as an experimental prototype. Forks are welcome.**

WMDiscord is an experimental native Discord voice overlay for GNUstep, Objective-C, X11, and Window Maker. It was built as a small desktop application rather than a browser-based client or a Discord bot.

The project is no longer actively developed by the original author. The repository is being preserved so others can inspect the implementation, learn from it, or continue development in their own forks.

## Project status

This is **not a finished or production-ready application**.

- The 0.3.1 Objective-C/GNUstep application compiled on an EndeavourOS system using Window Maker on X11. The later 0.3.2 source snapshot was prepared, but its build and GUI behavior were not confirmed in the user’s test logs.
- The Discord RPC prototype successfully completed its IPC handshake and authentication, subscribed to voice events, and received a selected voice-channel snapshot containing four voice states.
- The 0.3.1 demo was reported not to produce a visible window. The 0.3.2 overlay revision was prepared as a follow-up, but its end-to-end behavior was not verified.
- Unicode fallback, avatar display, click-through, saved positioning, and behavior over games are implemented or attempted in the source but have not all been validated in real use.
- Discord RPC access, including `rpc.voice.read`, is subject to Discord's application access rules and may not be available to every application.

Expect bugs, incomplete behavior, and platform-specific issues.

## Technology

- Objective-C and GNUstep AppKit
- GNUstep Make (`GNUmakefile`)
- POSIX threads and Unix-domain sockets
- Xlib / EWMH / X Shape for X11 window integration
- libcurl for OAuth and avatar HTTP requests

## Build on Arch Linux / EndeavourOS

Install the compiler, GNUstep, X11, and curl development packages. Package names and availability can vary by distribution; GNUstep GUI and its X11 backend may be separate packages.

A typical Arch-based setup uses:

```sh
yay -S --needed base-devel gcc-objc gnustep-make gnustep-base \
  pkgconf curl libx11 libxext fontconfig
```

Make sure GNUstep GUI and the GNUstep X11 backend (`gnustep-gui` and `gnustep-back` on the AUR) are installed as well. On Arch-based systems the build tool is `make`:

```sh
export GNUSTEP_MAKEFILES="$(gnustep-config --variable=GNUSTEP_MAKEFILES)"
make
```

Run the simulated roster:

```sh
./WMDiscord.app/WMDiscord --demo
```

Run the model test:

```sh
./scripts/test.sh
```

See [`docs/BUILDING.md`](docs/BUILDING.md) for additional notes.

## Discord integration

The application communicates with the logged-in Discord desktop client using its local RPC IPC socket. It does not install a bot in a server. Live voice roster access requires the appropriate Discord RPC authorization scope; Discord controls which applications may use restricted scopes such as `rpc.voice.read`.

See [`docs/DISCORD-RPC.md`](docs/DISCORD-RPC.md). Never commit client secrets, OAuth tokens, or local token storage. Rotate any credential that has been exposed.

## Overlay limitations

The source contains a Window Maker-inspired panel, Unicode-aware text handling, avatar caching, X11 stacking hints, placement controls, and pointer pass-through support. These features were not all verified together in the final build. Ordinary and borderless-windowed applications are the realistic X11 compatibility target; a normal managed X11 window cannot guarantee visibility over every exclusive-fullscreen game.

See [`docs/OVERLAY.md`](docs/OVERLAY.md).

## Archived repository / forks

The original repository is intended to be archived and read-only. Anyone interested in continuing the project is welcome to fork it and maintain their own version. Please treat this code as a starting point, not as a supported release.

## License

WMDiscord is licensed under **GNU General Public License version 2 only** (`GPL-2.0-only`). See [`LICENSE`](LICENSE) for the complete license text.
