#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
set -eu
printf '%s\n' '=== X session ==='
printf 'DISPLAY=%s\n' "${DISPLAY:-<unset>}"
printf 'XDG_SESSION_TYPE=%s\n' "${XDG_SESSION_TYPE:-<unset>}"
printf '\n%s\n' '=== WMDiscord processes ==='
pgrep -af 'WMDiscord.app/WMDiscord|WMDiscord --' || true
printf '\n%s\n' '=== WMDiscord X11 windows ==='
if command -v xwininfo >/dev/null 2>&1; then
    xwininfo -root -tree | grep -i -A3 -B2 'WMDiscord' || true
else
    echo 'xwininfo missing; install xorg-xwininfo.'
fi
printf '\n%s\n' '=== Root stacking list ==='
if command -v xprop >/dev/null 2>&1; then
    xprop -root _NET_CLIENT_LIST_STACKING 2>/dev/null || true
else
    echo 'xprop missing; install xorg-xprop.'
fi
