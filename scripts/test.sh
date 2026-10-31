#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
set -eu
cd "$(dirname "$0")/.."

command -v gnustep-config >/dev/null 2>&1 || {
    echo "gnustep-config is required to build the model tests." >&2
    exit 1
}
mkdir -p obj
# GNUstep's own compiler flags select the runtime and Foundation headers.
# OBJC may be overridden to clang if GCC Objective-C is not installed.
OBJC=${OBJC:-gcc}
# shellcheck disable=SC2046
$OBJC $(gnustep-config --objc-flags) -ISources \
    Tests/test_voice_model.m \
    Sources/Models/WMParticipant.m Sources/Models/WMVoiceModel.m \
    -o obj/test-voice-model $(gnustep-config --base-libs)
./obj/test-voice-model
