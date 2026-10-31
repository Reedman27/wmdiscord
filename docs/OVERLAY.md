# Overlay behavior and configuration

> **Experimental / not fully verified:** These are behaviors implemented or attempted in the 0.3.2 source. The reported 0.3.1 Window Maker demo did not visibly appear, and the 0.3.2 follow-up was not verified end-to-end. The complete overlay has not been validated.

## Visual design

WMDiscord 0.3.2 uses a compact, square-cornered, beveled panel inspired by Window Maker and classic NeXTSTEP titlebars: raised title strip, three small metal title controls, inset channel display, alternating participant rows, circular avatars, and restrained speaking highlights. It avoids rounded, neon-heavy Discord-clone styling.

## Automatic visibility

- Default mode: the overlay stays visible so connection and authorization status are inspectable, even before joining voice.
- Demo mode: `./WMDiscord.app/WMDiscord --demo` always shows the simulated roster.
- Discreet mode: `./WMDiscord.app/WMDiscord --hide-until-voice` hides until Discord selects a voice channel.

## Placement

- Drag the panel to any location. The origin is saved in `NSUserDefaults` and restored next launch.
- The WMDiscord application menu has Position → Top Left / Top Right / Bottom Left / Bottom Right presets.
- Corner placement uses the current screen's visible work area, leaving a 22-point margin.

## Click-through

Press **Ctrl+Alt+O** to toggle X11 pointer pass-through. With pass-through enabled, mouse clicks and pointer movement go to the window/game underneath. Press the same global hotkey again to restore interaction and dragging. The state is saved between runs. This uses X Shape 1.1 `ShapeInput`; if the X server does not support that extension, the app logs that click-through could not be applied.

## Avatars

Voice-state payloads contain user ID and avatar hash fields. WMDiscord downloads custom avatars from Discord's CDN in the background and caches them under:

```text
~/.cache/wmdiscord/avatars/
```

Images are capped at 2 MiB, checked for an image content type, and written atomically. Users without a custom avatar use Discord's default avatar bucket. The first frame of animated avatars is expected to display; animated playback has not yet been validated on GNUstep.

Avatar fetching requires an internet connection to `cdn.discordapp.com`. If a profile image cannot be fetched, WMDiscord keeps rendering a generated initial instead of blocking or failing the row.

## Unicode names

Names remain UTF-8/NSString text from the Discord RPC payload. Before AppKit initializes, the process forces `GNUSTEP_STRING_ENCODING=NSUTF8StringEncoding`; this matters because GNUstep documents a legacy ISO-8859-1 default for string encoding. The app configures `NSFont` preferred families and sets a broad PostScript-name fallback list and uses NotoSans-Regular when available. UI width clipping occurs on composed-character boundaries, so combining sequences, surrogate pairs, flags, and joined emoji are not cut in half.

The GNUstep GUI docs describe the encoding environment and the need to select fonts with suitable script coverage: <https://www.gnustep.org/resources/documentation/User/Gui/LanguageSetup.html>. Fontconfig provides script-specific fallback when a preferred font lacks a glyph; see <https://wiki.archlinux.org/title/Fonts>.

On EndeavourOS / Arch install a broad set of fonts:

```sh
yay -S --needed fontconfig noto-fonts noto-fonts-cjk noto-fonts-emoji
fc-cache -f
./scripts/check-fonts.sh
```

If one particular symbol still displays as an empty box, its exact code point may not exist in the installed fonts. Run `fc-match` diagnostics and add that script's font family, or send the exact character sequence (not a token or secret) so we can identify the coverage needed.

For EndeavourOS / Arch, install common fallback families:

```sh
yay -S --needed noto-fonts noto-fonts-cjk noto-fonts-emoji
```

`noto-fonts` covers broad scripts and symbols; `noto-fonts-cjk` adds Chinese/Japanese/Korean glyphs; `noto-fonts-emoji` adds emoji glyphs. Some niche scripts may need their corresponding Noto family. GNUstep's NSFont API supports an ordered preferred-font fallback list; the Cairo/fontconfig backend and installed font coverage determine the final glyph.

## Games and fullscreen behavior

WMDiscord asks the X11 window manager to keep the borderless utility window above normal windows and on all workspaces. It does not take focus when refreshing its roster, This is intended to keep the overlay visible when the game receives focus.

There is an important X11 limitation: the EWMH recommended stacking order puts a focused `_NET_WM_STATE_FULLSCREEN` window above `_NET_WM_WINDOW_TYPE_UTILITY` and `_NET_WM_STATE_ABOVE` windows. Games/compositors may also bypass composition for fullscreen rendering. Therefore no ordinary managed X11 window can promise to appear over every exclusive/true-fullscreen game. The supported compatibility target is **windowed or borderless-windowed** mode. Some games may still cover the overlay; test per game and compositor.

Reference: [Extended Window Manager Hints — stacking order](https://specifications.freedesktop.org/wm/latest-single/#idm45801755101760).


## Window visibility troubleshooting

The panel is a normal borderless `NSWindow` and an EWMH utility window, not a dock-type client. It paints an opaque background so it remains visible without an X11 compositor. Startup logs should include `Overlay window created` and `Overlay visible`. If those appear but no window is visible, inspect the X11 tree while the demo process is running:

```sh
xwininfo -root -tree | grep -i -A3 -B2 WMDiscord
xprop -root _NET_CLIENT_LIST_STACKING
```

`_NET_WM_WINDOW_TYPE_UTILITY` allows Window Maker to manage the window as a normal utility client. `--hide-until-voice` opts into hiding the overlay before a voice channel is selected; default and demo modes remain visible.
