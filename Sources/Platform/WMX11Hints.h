// SPDX-License-Identifier: GPL-2.0-only
#ifndef WM_X11_HINTS_H
#define WM_X11_HINTS_H

#import <AppKit/AppKit.h>

typedef void (*WMX11HotkeyCallback)(void *context);

/* EWMH integration: identifies the GNUstep window by title; never assumes an
   NSWindow windowNumber is an XID. */
void WMApplyX11OverlayHints(NSWindow *window, NSString *windowTitle);
BOOL WMSetX11ClickThrough(NSString *windowTitle, BOOL enabled);
BOOL WMStartX11HotkeyMonitor(WMX11HotkeyCallback callback, void *context);
void WMStopX11HotkeyMonitor(void);

#endif
