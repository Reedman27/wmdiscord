#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
set -eu

if ! command -v fc-match >/dev/null 2>&1; then
    echo "fontconfig tools are missing; install fontconfig."
    exit 1
fi

printf '%s\n' 'WMDiscord Unicode font coverage:'
for family in "Noto Sans" "Noto Sans CJK JP" "Noto Sans Arabic" "Noto Sans Symbols 2" "Noto Color Emoji"; do
    printf '  %-24s ' "$family"
    fc-match --format '%{family} | %{file}\n' "$family" | head -n 1
 done

printf '\nTest individual script coverage (fontconfig fallback):\n'
for pattern in 'sans-serif:charset=670' 'sans-serif:charset=4e00' 'sans-serif:charset=1f3ae' 'sans-serif:charset=10330'; do
    printf '  %-30s ' "$pattern"
    fc-match --format '%{family} | %{file}\n' "$pattern" | head -n 1
 done
