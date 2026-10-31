# WMDiscord — final archive handoff

## Repository status

**Archived experimental snapshot — version 0.3.2.** No further upstream feature work is planned. Forks are welcome under GPL-2.0-only.

## What is present

- Modular Objective-C application using GNUstep AppKit.
- Discord local RPC IPC client and OAuth token handling.
- Voice participant and channel state model.
- Window Maker / NeXTSTEP-inspired overlay view.
- Unicode-aware name handling and font diagnostics.
- Background avatar download/cache implementation.
- X11 EWMH window hints and ShapeInput click-through support.
- Demo mode and a voice-model test.

## Last known verification

- GNUstep Make, Base, GUI, and the GNUstep X11 backend were installed on an EndeavourOS + Window Maker system.
- The 0.3.1 source compiled and linked successfully there. The 0.3.2 follow-up source snapshot was prepared but not confirmed by a complete user-side test.
- An earlier RPC test completed the IPC handshake and authentication, subscribed to voice events, selected the active channel, and reported a snapshot with four voice states.
- The 0.3.1 demo did not visibly display a window in the reported Window Maker test. The 0.3.2 follow-up was not confirmed end-to-end. The final overlay behavior is therefore unresolved.
- Unicode glyph fallback, avatar appearance, click-through, persistent positioning, and overlay behavior in games are not confirmed end-to-end.

## Build

On Arch-based systems, install the GNUstep development packages, GNUstep GUI and its X11 backend, GCC Objective-C, X11 development libraries, and libcurl. Then:

```sh
export GNUSTEP_MAKEFILES="$(gnustep-config --variable=GNUSTEP_MAKEFILES)"
make
./WMDiscord.app/WMDiscord --demo
./scripts/test.sh
```

See `docs/BUILDING.md` for details.

## Important security notes

- Never commit `WMDISCORD_CLIENT_SECRET`, OAuth access tokens, refresh tokens, or the local token store.
- Rotate Discord credentials that have been exposed.
- Live RPC voice access depends on Discord granting the required scope to the application.

## Continuing development

The upstream project is not accepting further work. Fork the public repository and maintain changes independently. See `REPOSITORY-SETUP.md` for the intended GitHub archive workflow.
