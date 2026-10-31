# WMDiscord architecture

## Runtime overview

```text
Discord desktop client
       │ local Unix socket
       ▼
WMRPCClient ───── WMOAuthStore / WMCurlRuntime
       │ voice snapshots + events
       ▼
WMAppDelegate ─── WMVoiceModel ─── WMParticipant
       │                                  │
       ▼                                  │ user ID + avatar hash
WMOverlayView ◄───────────────────────────┘
       │             ▲
       │             └── WMAvatarCache (async CDN worker + disk cache)
       ▼
WMX11Hints (EWMH utility/above/sticky, ShapeInput, Ctrl+Alt+O)
```

## Modules

- `Sources/App/WMAppDelegate`: application lifecycle, visible-by-default behavior, optional auto-hide until voice, menu, saved positions, demo mode, and main-thread coordination.
- `Sources/Discord/WMRPCClient`: POSIX IPC framing, reconnect, RPC command/response handling, authorization state machine, event subscriptions, and channel snapshots.
- `Sources/Discord/WMOAuthStore`: HTTPS authorization-code exchange and refresh, restrictive token-file permissions.
- `Sources/Utilities/WMCurlRuntime`: process-wide `pthread_once` initialization shared by OAuth and avatar networking. `curl_global_cleanup` is deliberately not called while the app may still use libcurl.
- `Sources/Models/WMParticipant`: normalized nickname/global name/username, avatar hash, speaking/mute/deafen/bot state. It calculates the default avatar bucket for users without a custom avatar.
- `Sources/Models/WMVoiceModel`: channel and participant state transitions independent of AppKit.
- `Sources/Overlay/WMOverlayView`: Window Maker / NeXTSTEP-inspired bevelled layout, Unicode-aware name clipping, participant rows, avatar drawing, drag handling.
- `Sources/Overlay/WMAvatarCache`: asynchronous, bounded Discord CDN downloads, atomic disk cache writes, main-thread `NSImage` creation, and UI invalidation callback.
- `Sources/Platform/WMX11Hints`: narrow Xlib integration for EWMH type/state requests, X Shape input pass-through, and global `Ctrl+Alt+O` hotkey.

## Unicode

RPC JSON is decoded as UTF-8 into Foundation strings. The view does not truncate names by a raw UTF-16 code-unit count; it measures rendered width and truncates at `rangeOfComposedCharacterSequenceAtIndex:` boundaries. The app prepends Noto and broad-coverage PostScript face names to GNUstep's preferred-font fallback list. It does not pass Fontconfig family labels to `NSFont fontWithName:size:`. Correct rendering still depends on installed fonts and the GNUstep Cairo/fontconfig backend. See `OVERLAY.md` for suggested Arch packages.

## Avatar cache

The `GET_SELECTED_VOICE_CHANNEL` snapshot and voice-state dispatches contain a `user` object with the Discord ID and avatar hash. WMParticipant preserves those fields. WMAvatarCache builds a CDN URL using the ID/hash pair, bounds each response to 2 MiB, verifies HTTP 200 and an `image/*` content type, writes through a mode-0600 temporary file and atomic rename, then asks the main thread to construct an NSImage and redraw. Files are stored under `~/.cache/wmdiscord/avatars`. Missing custom avatar hashes map to Discord's default avatar bucket URL.

## X11 overlay contract

- The GNUstep panel is located by title through XQueryTree. `NSWindow windowNumber` is never assumed to be an XID.
- EWMH marks it as a utility window with above/sticky/skip-taskbar/skip-pager requests and asks compositors not to bypass composition for the overlay itself.
- X Shape 1.1 `ShapeInput` is set to an empty region for pointer pass-through and reset to the default region for interaction.
- A small POSIX pthread monitors a passive root-window grab for `Ctrl+Alt+O`; it marshals the toggle to the AppKit main thread.
- EWMH cannot guarantee placement above a focused fullscreen window: the recommended stacking order puts fullscreen windows above dock/above windows. Borderless-windowed mode is the practical compatibility target.

## Threading contract

The RPC worker owns the Discord socket. The avatar worker owns avatar HTTP transfers and disk writes. The hotkey worker owns its Xlib display connection. AppKit objects are created/drawn and delegate updates occur on the main thread. Worker-to-main notifications use `performSelectorOnMainThread:`. Stop methods signal and join workers before their owner is released.

## IPC framing

Each Discord IPC message has an 8-byte header followed by JSON bytes:

| Offset | Size | Value |
|---:|---:|---|
| 0 | 4 | opcode, little-endian uint32 |
| 4 | 4 | payload length, little-endian uint32 |
| 8 | N | UTF-8 JSON payload |

The client caps payloads at 4 MiB, handles partial reads/writes, and responds to opcode PING with PONG.

## Verification status

The 0.3.1 source compiled on the original EndeavourOS + Window Maker test system, but the reported demo run did not display a visible window. A 0.3.2 follow-up was prepared but not verified end-to-end. Avatar rendering, click-through, and game-overlay behavior remain unverified as a complete end-to-end experience.
