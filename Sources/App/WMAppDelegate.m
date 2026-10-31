// SPDX-License-Identifier: GPL-2.0-only
#import "WMAppDelegate.h"
#import "../Platform/WMX11Hints.h"
#include <stdlib.h>

@interface WMAppDelegate ()
- (void)_refreshOverlay;
- (void)_installApplicationMenu;
- (void)_applyX11Hints;
- (void)_tickDemo:(NSTimer *)timer;
- (void)_saveOverlayOrigin:(NSPoint)origin;
@end

static void WMOverlayHotkeyCallback(void *context)
{
    WMAppDelegate *delegate = (WMAppDelegate *)context;
    [delegate performSelectorOnMainThread:@selector(toggleClickThroughFromHotkey)
        withObject:nil waitUntilDone:NO];
}

static void WMConfigureUnicodeFontFallback(void)
{
    /* NSFont +fontWithName:size: expects a PostScript name, not a Fontconfig
       family string.  Use known PostScript names and leave Fontconfig/Cairo
       free to supply per-glyph fallback for CJK, Arabic, emoji, etc. */
    NSArray *preferred = [NSArray arrayWithObjects:
        @"NotoSans-Regular", @"NotoSansCJKjp-Regular", @"NotoSansArabic-Regular",
        @"NotoSansHebrew-Regular", @"NotoSansDevanagari-Regular",
        @"NotoSansSymbols2-Regular", @"NotoColorEmoji", @"DejaVuSans",
        @"FreeSans", @"LiberationSans", nil];
    NSArray *existing = [NSFont preferredFontNames];
    NSMutableArray *fallbacks = [NSMutableArray arrayWithArray:preferred];
    for (NSString *fontName in existing) {
        if ([fontName isKindOfClass:[NSString class]] && ![fallbacks containsObject:fontName])
            [fallbacks addObject:fontName];
    }
    [NSFont setPreferredFontNames:fallbacks];

    NSFont *font = [NSFont fontWithName:@"NotoSans-Regular" size:11.0];
    if (!font) font = [NSFont userFontOfSize:11.0];
    if (font) {
        [NSFont setUserFont:font];
        NSLog(@"[WMDiscord] Participant font: %@; Unicode fallback families configured.", [font fontName]);
    } else {
        NSLog(@"[WMDiscord] Using GNUstep default font; Unicode fallback list configured.");
    }
}

@implementation WMAppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification
{
    (void)notification;
    WMConfigureUnicodeFontFallback();
    _voiceModel = [[WMVoiceModel alloc] init];
    NSArray *arguments = [[NSProcessInfo processInfo] arguments];
    _demoMode = [arguments containsObject:@"--demo"];
    /* Keep the overlay visible by default, including disconnected/no-channel
       states. --hide-until-voice opts into the more discreet auto-hide mode. */
    _alwaysVisible = ![arguments containsObject:@"--hide-until-voice"] ||
        [arguments containsObject:@"--always-visible"];
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    _clickThrough = [defaults boolForKey:@"WMDiscordClickThrough"];

    NSRect visible = [[NSScreen mainScreen] visibleFrame];
    CGFloat width = 324.0, height = 390.0, margin = 22.0;
    NSArray *savedOrigin = [defaults arrayForKey:@"WMDiscordOverlayOrigin"];
    NSPoint origin = NSMakePoint(NSMaxX(visible) - width - margin, NSMinY(visible) + margin);
    if ([savedOrigin isKindOfClass:[NSArray class]] && [savedOrigin count] == 2 &&
        [[savedOrigin objectAtIndex:0] respondsToSelector:@selector(doubleValue)] &&
        [[savedOrigin objectAtIndex:1] respondsToSelector:@selector(doubleValue)]) {
        origin.x = [[savedOrigin objectAtIndex:0] doubleValue];
        origin.y = [[savedOrigin objectAtIndex:1] doubleValue];
    }
    NSRect frame = NSMakeRect(origin.x, origin.y, width, height);
    _panel = [[NSWindow alloc] initWithContentRect:frame
        styleMask:NSBorderlessWindowMask backing:NSBackingStoreBuffered defer:NO];
    [_panel setTitle:@"WMDiscord"];
    [_panel setReleasedWhenClosed:NO];
    /* Use an opaque backing surface so this remains visible without a running
       X11 compositor. The view paints its own full background. */
    [_panel setOpaque:YES];
    [_panel setBackgroundColor:[NSColor colorWithCalibratedRed:0.16 green:0.18 blue:0.21 alpha:1.0]];
    [_panel setHasShadow:YES];
    [_panel setLevel:NSFloatingWindowLevel];

    _overlayView = [[WMOverlayView alloc] initWithFrame:NSMakeRect(0.0, 0.0, width, height)];
    [_overlayView setDelegate:self];
    [_panel setContentView:_overlayView];
    _avatarCache = [[WMAvatarCache alloc] initWithDelegate:self];
    [_overlayView setAvatarCache:_avatarCache];
    [_overlayView setClickThrough:_clickThrough];
    [self _installApplicationMenu];
    NSLog(@"[WMDiscord] Created overlay window at %.0f,%.0f size %.0fx%.0f.",
        frame.origin.x, frame.origin.y, frame.size.width, frame.size.height);
    [NSApp activateIgnoringOtherApps:YES];
    [_panel makeKeyAndOrderFront:nil];
    [_panel orderFrontRegardless];
    [self performSelector:@selector(_applyX11Hints) withObject:nil afterDelay:0.6];
    _x11Timer = [[NSTimer scheduledTimerWithTimeInterval:2.0 target:self selector:@selector(_applyX11Hints)
        userInfo:nil repeats:YES] retain];
    if (!WMStartX11HotkeyMonitor(WMOverlayHotkeyCallback, self))
        NSLog(@"[WMDiscord] Could not register Ctrl+Alt+O global click-through hotkey.");

    if (_clickThrough) [self _applyX11Hints];
    if (_demoMode) {
        [_voiceModel setStatus:@"Demo mode — simulated voice data"];
        [_voiceModel applyChannelSnapshot:[NSDictionary dictionaryWithObjectsAndKeys:
            @"demo-channel", @"id", @"Test server / General", @"name", [NSArray array], @"voice_states", nil]];
        NSArray *demo = [NSArray arrayWithObjects:
            [NSDictionary dictionaryWithObjectsAndKeys:@"demo-01", @"id", @"Sky", @"username", [NSNumber numberWithBool:NO], @"bot", nil],
            [NSDictionary dictionaryWithObjectsAndKeys:@"demo-02", @"id", @"月の騎士", @"username", [NSNumber numberWithBool:NO], @"bot", nil],
            [NSDictionary dictionaryWithObjectsAndKeys:@"demo-03", @"id", @"Александр", @"username", [NSNumber numberWithBool:NO], @"bot", nil],
            [NSDictionary dictionaryWithObjectsAndKeys:@"demo-04", @"id", @"Mika 🎮", @"username", [NSNumber numberWithBool:NO], @"bot", nil],
            [NSDictionary dictionaryWithObjectsAndKeys:@"demo-05", @"id", @"꧁ঔৣ☬RĪØT☬ঔৣ꧂", @"username", [NSNumber numberWithBool:NO], @"bot", nil],
            [NSDictionary dictionaryWithObjectsAndKeys:@"demo-06", @"id", @"ليلى", @"username", [NSNumber numberWithBool:NO], @"bot", nil],
            [NSDictionary dictionaryWithObjectsAndKeys:@"demo-07", @"id", @"별빛", @"username", [NSNumber numberWithBool:NO], @"bot", nil],
            [NSDictionary dictionaryWithObjectsAndKeys:@"demo-08", @"id", @"BuildBot", @"username", [NSNumber numberWithBool:YES], @"bot", nil], nil];
        for (NSDictionary *user in demo) {
            NSDictionary *payload = [NSDictionary dictionaryWithObjectsAndKeys:user, @"user",
                [NSDictionary dictionary], @"voice_state", nil];
            [_voiceModel applyEvent:@"VOICE_STATE_CREATE" data:payload];
        }
        _demoSpeakingIndex = 1;
        [_voiceModel applyEvent:@"SPEAKING_START" data:[NSDictionary dictionaryWithObject:@"demo-02" forKey:@"user_id"]];
        _demoTimer = [[NSTimer scheduledTimerWithTimeInterval:1.25 target:self
            selector:@selector(_tickDemo:) userInfo:nil repeats:YES] retain];
        [self _refreshOverlay];
        return;
    }

    const char *applicationID = getenv("WMDISCORD_CLIENT_ID");
    if (!applicationID || !applicationID[0]) {
        [_voiceModel setStatus:@"Set WMDISCORD_CLIENT_ID to connect"];
        [self _refreshOverlay];
        return;
    }
    const char *secret = getenv("WMDISCORD_CLIENT_SECRET");
    const char *redirect = getenv("WMDISCORD_REDIRECT_URI");
    NSString *clientID = [NSString stringWithUTF8String:applicationID];
    NSString *clientSecret = (secret && secret[0]) ? [NSString stringWithUTF8String:secret] : nil;
    NSString *redirectURI = (redirect && redirect[0]) ? [NSString stringWithUTF8String:redirect] : nil;
    _rpcClient = [[WMRPCClient alloc] initWithApplicationID:clientID
        clientSecret:clientSecret redirectURI:redirectURI delegate:self];
    [_rpcClient start];
    [self _refreshOverlay];
}

- (void)_installApplicationMenu
{
    NSMenu *mainMenu = [[[NSMenu alloc] initWithTitle:@"WMDiscord"] autorelease];
    NSMenuItem *rootItem = [[[NSMenuItem alloc] initWithTitle:@"WMDiscord" action:NULL keyEquivalent:@""] autorelease];
    NSMenu *appMenu = [[[NSMenu alloc] initWithTitle:@"WMDiscord"] autorelease];

    NSMenuItem *clickItem = [[[NSMenuItem alloc] initWithTitle:@"Toggle click-through (Ctrl+Alt+O)"
        action:@selector(toggleClickThrough:) keyEquivalent:@"o"] autorelease];
    [clickItem setTarget:self];
    [clickItem setKeyEquivalentModifierMask:(NSControlKeyMask | NSAlternateKeyMask)];
    [appMenu addItem:clickItem];

    NSMenuItem *positionItem = [[[NSMenuItem alloc] initWithTitle:@"Position" action:NULL keyEquivalent:@""] autorelease];
    NSMenu *positionMenu = [[[NSMenu alloc] initWithTitle:@"Position"] autorelease];
    NSArray *corners = [NSArray arrayWithObjects:
        [NSArray arrayWithObjects:@"Top Left", @"top-left", nil],
        [NSArray arrayWithObjects:@"Top Right", @"top-right", nil],
        [NSArray arrayWithObjects:@"Bottom Left", @"bottom-left", nil],
        [NSArray arrayWithObjects:@"Bottom Right", @"bottom-right", nil], nil];
    for (NSArray *corner in corners) {
        NSMenuItem *item = [[[NSMenuItem alloc] initWithTitle:[corner objectAtIndex:0]
            action:@selector(setOverlayCorner:) keyEquivalent:@""] autorelease];
        [item setTarget:self];
        [item setRepresentedObject:[corner objectAtIndex:1]];
        [positionMenu addItem:item];
    }
    [positionItem setSubmenu:positionMenu];
    [appMenu addItem:positionItem];
    [appMenu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *quit = [[[NSMenuItem alloc] initWithTitle:@"Quit WMDiscord"
        action:@selector(terminate:) keyEquivalent:@"q"] autorelease];
    [appMenu addItem:quit];
    [rootItem setSubmenu:appMenu];
    [mainMenu addItem:rootItem];
    [NSApp setMainMenu:mainMenu];
}

- (void)_applyX11Hints
{
    WMApplyX11OverlayHints(_panel, @"WMDiscord");
    (void)WMSetX11ClickThrough(@"WMDiscord", _clickThrough);
    /* Reassert mapping after EWMH hints; some WMs remap utility windows when
       their type/state properties change. */
    if ([_panel isVisible]) [_panel orderFrontRegardless];
}

- (void)_refreshOverlay
{
    [_overlayView setStatus:[_voiceModel status] channel:[_voiceModel channelName]];
    [_overlayView setParticipants:[_voiceModel participantSnapshots]
        selfMuted:[_voiceModel isSelfMuted] selfDeafened:[_voiceModel isSelfDeafened]];
    BOOL hasVoiceChannel = [[_voiceModel channelName] length] > 0;
    if (_demoMode || _alwaysVisible || hasVoiceChannel) {
        [_panel orderFrontRegardless];
        if (![_panel isVisible]) [_panel makeKeyAndOrderFront:nil];
        NSLog(@"[WMDiscord] Overlay visible (demo=%d, channel=%d, participants=%lu).",
            _demoMode, hasVoiceChannel, (unsigned long)[[_voiceModel participantSnapshots] count]);
    } else {
        [_panel orderOut:nil];
        NSLog(@"[WMDiscord] Overlay hidden until a voice channel is selected.");
    }
}

- (void)_tickDemo:(NSTimer *)timer
{
    (void)timer;
    NSArray *people = [_voiceModel participantSnapshots];
    if ([people count] < 2) return;
    NSString *previous = [[people objectAtIndex:_demoSpeakingIndex % [people count]] objectForKey:@"id"];
    [_voiceModel applyEvent:@"SPEAKING_STOP" data:[NSDictionary dictionaryWithObject:previous forKey:@"user_id"]];
    _demoSpeakingIndex = (_demoSpeakingIndex + 1) % [people count];
    NSString *next = [[people objectAtIndex:_demoSpeakingIndex] objectForKey:@"id"];
    [_voiceModel applyEvent:@"SPEAKING_START" data:[NSDictionary dictionaryWithObject:next forKey:@"user_id"]];
    [self _refreshOverlay];
}

- (void)toggleClickThrough:(id)sender
{
    (void)sender;
    _clickThrough = !_clickThrough;
    if (!WMSetX11ClickThrough(@"WMDiscord", _clickThrough)) {
        NSLog(@"[WMDiscord] X11 ShapeInput click-through could not be applied.");
        _clickThrough = !_clickThrough;
        return;
    }
    [[NSUserDefaults standardUserDefaults] setBool:_clickThrough forKey:@"WMDiscordClickThrough"];
    [_overlayView setClickThrough:_clickThrough];
    NSLog(@"[WMDiscord] Click-through %@. Hotkey: Ctrl+Alt+O.", _clickThrough ? @"enabled" : @"disabled");
}

- (void)toggleClickThroughFromHotkey { [self toggleClickThrough:nil]; }

- (void)setOverlayCorner:(id)sender
{
    NSString *corner = [sender respondsToSelector:@selector(representedObject)] ? [sender representedObject] : nil;
    if (![corner isKindOfClass:[NSString class]]) return;
    NSRect visible = [[NSScreen mainScreen] visibleFrame];
    NSRect panelFrame = [_panel frame];
    CGFloat margin = 22.0, x = NSMinX(visible) + margin, y = NSMinY(visible) + margin;
    if ([corner hasPrefix:@"top-"]) y = NSMaxY(visible) - panelFrame.size.height - margin;
    if ([corner hasSuffix:@"right"]) x = NSMaxX(visible) - panelFrame.size.width - margin;
    [_panel setFrameOrigin:NSMakePoint(x, y)];
    [self _saveOverlayOrigin:NSMakePoint(x, y)];
}

- (void)_saveOverlayOrigin:(NSPoint)origin
{
    [[NSUserDefaults standardUserDefaults] setObject:[NSArray arrayWithObjects:
        [NSNumber numberWithDouble:origin.x], [NSNumber numberWithDouble:origin.y], nil]
        forKey:@"WMDiscordOverlayOrigin"];
}

- (void)overlayViewDidMoveToOrigin:(NSPoint)origin { [self _saveOverlayOrigin:origin]; }

- (void)avatarCacheDidLoadAvatarForKey:(NSString *)key
{
    (void)key;
    [_overlayView setNeedsDisplay:YES];
}

- (void)rpcClientDidChangeStatus:(NSString *)status
{
    [_voiceModel setStatus:status];
    [self _refreshOverlay];
}

- (void)rpcClientDidConnect
{
    [_voiceModel setStatus:@"Discord RPC authenticated"];
    [self _refreshOverlay];
}

- (void)rpcClientDidDisconnectWithReason:(NSString *)reason
{
    [_voiceModel reset];
    [_voiceModel setStatus:reason];
    [self _refreshOverlay];
}

- (void)rpcClientDeliverEvent:(NSDictionary *)envelope
{
    NSString *event = [envelope objectForKey:@"event"];
    NSDictionary *data = [envelope objectForKey:@"data"];
    if ([event isEqualToString:@"VOICE_CHANNEL_DATA"]) {
        id channel = [data objectForKey:@"channel"];
        if (channel == (id)[NSNull null]) [_voiceModel applyChannelSnapshot:nil];
        else [_voiceModel applyChannelSnapshot:channel];
    } else {
        [_voiceModel applyEvent:event data:data];
    }
    [self _refreshOverlay];
}

- (void)applicationWillTerminate:(NSNotification *)notification
{
    (void)notification;
    [_demoTimer invalidate];
    [_x11Timer invalidate];
    WMStopX11HotkeyMonitor();
    [_rpcClient stop];
    [_avatarCache stop];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(id)sender
{
    (void)sender;
    return YES;
}

- (void)dealloc
{
    [_demoTimer invalidate]; [_demoTimer release];
    [_x11Timer invalidate]; [_x11Timer release];
    WMStopX11HotkeyMonitor();
    [_rpcClient stop]; [_rpcClient release];
    [_avatarCache stop]; [_avatarCache release];
    [_panel release]; [_overlayView release]; [_voiceModel release];
    [super dealloc];
}
@end
