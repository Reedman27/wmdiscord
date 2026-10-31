// SPDX-License-Identifier: GPL-2.0-only
#import <AppKit/AppKit.h>
#import "App/WMAppDelegate.h"
#include <locale.h>
#include <stdlib.h>

int main(int argc, const char **argv)
{
    (void)argc;
    (void)argv;

    /* Discord RPC JSON is UTF-8. GNUstep documents ISO-8859-1 as its legacy
       default unless this is set before the AppKit/Foundation stack starts. */
    (void)setenv("GNUSTEP_STRING_ENCODING", "NSUTF8StringEncoding", 1);
    (void)setlocale(LC_CTYPE, "");

    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    [NSApplication sharedApplication];
    WMAppDelegate *delegate = [[WMAppDelegate alloc] init];
    [NSApp setDelegate:delegate];
    [NSApp run];
    [delegate release];
    [pool drain];
    return 0;
}
