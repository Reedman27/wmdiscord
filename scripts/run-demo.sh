#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
set -eu
cd "$(dirname "$0")/.."
if [ ! -x ./WMDiscord.app/WMDiscord ]; then
    echo "WMDiscord is not built. Run: make" >&2
    exit 1
fi
exec ./WMDiscord.app/WMDiscord --demo
