# SPDX-License-Identifier: GPL-2.0-only
GNUSTEP_MAKEFILES ?= $(shell gnustep-config --variable=GNUSTEP_MAKEFILES 2>/dev/null)
include $(GNUSTEP_MAKEFILES)/common.make

APP_NAME = WMDiscord
VERSION = 0.3.2

WMDiscord_OBJC_FILES = \
    Sources/main.m \
    Sources/Utilities/WMCurlRuntime.m \
    Sources/App/WMAppDelegate.m \
    Sources/Discord/WMRPCClient.m \
    Sources/Discord/WMOAuthStore.m \
    Sources/Models/WMParticipant.m \
    Sources/Models/WMVoiceModel.m \
    Sources/Overlay/WMOverlayView.m \
    Sources/Overlay/WMAvatarCache.m \
    Sources/Platform/WMX11Hints.m

ADDITIONAL_OBJCFLAGS += -std=gnu11 -Wall -Wextra -Wformat=2 -Werror=implicit-function-declaration -Werror=return-type -pthread
ADDITIONAL_GUI_LIBS += -lX11 -lXext -lcurl -pthread

include $(GNUSTEP_MAKEFILES)/application.make
