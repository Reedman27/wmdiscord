// SPDX-License-Identifier: GPL-2.0-only
#import "WMOverlayView.h"

static NSColor *WMColor(CGFloat red, CGFloat green, CGFloat blue, CGFloat alpha)
{
    return [NSColor colorWithCalibratedRed:red green:green blue:blue alpha:alpha];
}

static NSDictionary *WMTextAttributes(NSFont *font, NSColor *color)
{
    return [NSDictionary dictionaryWithObjectsAndKeys:font, NSFontAttributeName,
        color, NSForegroundColorAttributeName, nil];
}

/* Clip at composed-character boundaries, never in the middle of a surrogate
   pair, combining mark sequence, flag, or joined emoji. */
static NSString *WMStringFittingWidth(NSString *string, NSDictionary *attributes, CGFloat width)
{
    if (![string isKindOfClass:[NSString class]]) return @"";
    if ([string sizeWithAttributes:attributes].width <= width) return string;
    NSString *ellipsis = @"…";
    NSUInteger end = 0;
    while (end < [string length]) {
        NSRange range = [string rangeOfComposedCharacterSequenceAtIndex:end];
        NSUInteger next = NSMaxRange(range);
        NSString *candidate = [[string substringToIndex:next] stringByAppendingString:ellipsis];
        if ([candidate sizeWithAttributes:attributes].width > width) break;
        end = next;
    }
    return end ? [[string substringToIndex:end] stringByAppendingString:ellipsis] : ellipsis;
}

static NSString *WMFirstComposedCharacter(NSString *string)
{
    if (![string isKindOfClass:[NSString class]] || [string length] == 0) return @"?";
    return [string substringWithRange:[string rangeOfComposedCharacterSequenceAtIndex:0]];
}

static void WMDrawBevel(NSRect rect, NSColor *topLeft, NSColor *bottomRight, CGFloat width)
{
    NSBezierPath *top = [NSBezierPath bezierPath];
    [top moveToPoint:NSMakePoint(NSMinX(rect), NSMinY(rect))];
    [top lineToPoint:NSMakePoint(NSMinX(rect), NSMaxY(rect))];
    [top lineToPoint:NSMakePoint(NSMaxX(rect), NSMaxY(rect))];
    [topLeft setStroke]; [top setLineWidth:width]; [top stroke];
    NSBezierPath *bottom = [NSBezierPath bezierPath];
    [bottom moveToPoint:NSMakePoint(NSMaxX(rect), NSMaxY(rect))];
    [bottom lineToPoint:NSMakePoint(NSMaxX(rect), NSMinY(rect))];
    [bottom lineToPoint:NSMakePoint(NSMinX(rect), NSMinY(rect))];
    [bottomRight setStroke]; [bottom setLineWidth:width]; [bottom stroke];
}

@implementation WMOverlayView
- (BOOL)isOpaque { return YES; }
- (id)initWithFrame:(NSRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        _participants = [[NSArray alloc] init];
        _status = [@"Starting" copy];
        _channel = [@"" copy];
    }
    return self;
}

- (void)dealloc
{
    [_participants release]; [_status release]; [_channel release];
    [super dealloc];
}

- (void)setDelegate:(id<WMOverlayViewDelegate>)delegate { _delegate = delegate; }
- (void)setAvatarCache:(WMAvatarCache *)cache { _avatarCache = cache; [self setNeedsDisplay:YES]; }
- (void)setClickThrough:(BOOL)value { _clickThrough = value; [self setNeedsDisplay:YES]; }

- (void)setStatus:(NSString *)status channel:(NSString *)channel
{
    NSString *newStatus = [status isKindOfClass:[NSString class]] ? status : @"";
    NSString *newChannel = [channel isKindOfClass:[NSString class]] ? channel : @"";
    [_status release]; _status = [newStatus copy];
    [_channel release]; _channel = [newChannel copy];
    [self setNeedsDisplay:YES];
}

- (void)setParticipants:(NSArray *)participants selfMuted:(BOOL)muted selfDeafened:(BOOL)deafened
{
    [_participants release];
    _participants = [(participants ? participants : [NSArray array]) copy];
    _selfMuted = muted; _selfDeafened = deafened;
    [self setNeedsDisplay:YES];
}

- (void)drawRect:(NSRect)dirtyRect
{
    (void)dirtyRect;
    NSRect bounds = [self bounds];
    CGFloat width = bounds.size.width, height = bounds.size.height;

    /* NeXT/Window Maker-inspired squared metal frame and raised titlebar. */
    [WMColor(0.16, 0.18, 0.21, 0.985) setFill];
    NSRectFill(bounds);
    WMDrawBevel(NSInsetRect(bounds, 0.5, 0.5), WMColor(0.72, 0.75, 0.79, 1.0), WMColor(0.035, 0.04, 0.05, 1.0), 1.0);
    NSRect inner = NSInsetRect(bounds, 3.0, 3.0);
    [WMColor(0.105, 0.12, 0.145, 0.99) setFill]; NSRectFill(inner);
    WMDrawBevel(inner, WMColor(0.34, 0.38, 0.43, 1.0), WMColor(0.025, 0.03, 0.04, 1.0), 1.0);

    NSRect titleRect = NSMakeRect(5.0, height - 31.0, width - 10.0, 26.0);
    [WMColor(0.34, 0.39, 0.46, 1.0) setFill]; NSRectFill(titleRect);
    NSRect titleTop = NSMakeRect(titleRect.origin.x, NSMaxY(titleRect) - 2.0, titleRect.size.width, 2.0);
    [WMColor(0.56, 0.61, 0.67, 1.0) setFill]; NSRectFill(titleTop);
    NSRect titleBottom = NSMakeRect(titleRect.origin.x, titleRect.origin.y, titleRect.size.width, 2.0);
    [WMColor(0.12, 0.15, 0.19, 1.0) setFill]; NSRectFill(titleBottom);

    /* Three tiny NeXTSTEP-style titlebar controls. */
    for (NSUInteger i = 0; i < 3; i++) {
        NSRect button = NSMakeRect(11.0 + (CGFloat)i * 15.0, height - 24.0, 10.0, 10.0);
        [WMColor(0.53, 0.57, 0.62, 1.0) setFill]; NSRectFill(button);
        WMDrawBevel(button, WMColor(0.83, 0.85, 0.87, 1.0), WMColor(0.12, 0.14, 0.17, 1.0), 1.0);
    }
    NSDictionary *titleAttrs = WMTextAttributes([NSFont boldSystemFontOfSize:11.5], WMColor(0.97, 0.98, 1.0, 1.0));
    NSString *title = _clickThrough ? @"WMDiscord  ·  PASS-THROUGH" : @"WMDiscord";
    NSSize titleSize = [title sizeWithAttributes:titleAttrs];
    [title drawAtPoint:NSMakePoint((width - titleSize.width) / 2.0, height - 24.0) withAttributes:titleAttrs];

    NSDictionary *smallAttrs = WMTextAttributes([NSFont systemFontOfSize:9.0], WMColor(0.72, 0.76, 0.81, 1.0));
    NSDictionary *channelAttrs = WMTextAttributes([NSFont boldSystemFontOfSize:11.0], WMColor(0.96, 0.97, 0.98, 1.0));
    NSFont *participantFont = [NSFont fontWithName:@"Noto Sans" size:11.0];
    if (!participantFont) participantFont = [NSFont userFontOfSize:11.0];
    NSDictionary *nameAttrs = WMTextAttributes(participantFont, WMColor(0.94, 0.95, 0.97, 1.0));
    NSDictionary *stateAttrs = WMTextAttributes([NSFont systemFontOfSize:9.0], WMColor(0.68, 0.73, 0.79, 1.0));

    NSRect channelRect = NSMakeRect(9.0, height - 73.0, width - 18.0, 34.0);
    [WMColor(0.085, 0.10, 0.125, 1.0) setFill]; NSRectFill(channelRect);
    WMDrawBevel(channelRect, WMColor(0.035, 0.045, 0.06, 1.0), WMColor(0.39, 0.43, 0.49, 1.0), 1.0);
    NSString *subtitle = [_channel length] ? _channel : _status;
    subtitle = WMStringFittingWidth(subtitle, channelAttrs, width - 46.0);
    [subtitle drawAtPoint:NSMakePoint(17.0, height - 53.0) withAttributes:channelAttrs];
    NSString *connection = [_channel length] ? @"VOICE CONNECTED" : @"DISCORD STATUS";
    [connection drawAtPoint:NSMakePoint(17.0, height - 66.0) withAttributes:smallAttrs];

    NSString *selfState = _selfDeafened ? @"DEAFENED" : (_selfMuted ? @"MUTED" : @"");
    if ([selfState length]) {
        NSDictionary *badgeAttrs = WMTextAttributes([NSFont boldSystemFontOfSize:8.0],
            _selfDeafened ? WMColor(1.0, 0.52, 0.43, 1.0) : WMColor(1.0, 0.76, 0.38, 1.0));
        NSSize badgeSize = [selfState sizeWithAttributes:badgeAttrs];
        [selfState drawAtPoint:NSMakePoint(width - 17.0 - badgeSize.width, height - 53.0) withAttributes:badgeAttrs];
    }

    NSRect listHeader = NSMakeRect(10.0, height - 84.0, width - 20.0, 10.0);
    [WMColor(0.12, 0.14, 0.17, 1.0) setFill]; NSRectFill(listHeader);
    [@"VOICE PARTICIPANTS" drawAtPoint:NSMakePoint(16.0, height - 82.0) withAttributes:smallAttrs];

    NSUInteger visible = MIN([_participants count], (NSUInteger)6);
    CGFloat rowTop = height - 91.0;
    for (NSUInteger index = 0; index < visible; index++) {
        NSDictionary *person = [_participants objectAtIndex:index];
        BOOL speaking = [[person objectForKey:@"speaking"] boolValue];
        BOOL muted = [[person objectForKey:@"muted"] boolValue];
        BOOL deafened = [[person objectForKey:@"deafened"] boolValue];
        BOOL bot = [[person objectForKey:@"bot"] boolValue];
        NSString *name = [person objectForKey:@"name"];
        NSString *userID = [person objectForKey:@"id"];
        NSString *avatarHash = [person objectForKey:@"avatar"];
        if (![name isKindOfClass:[NSString class]]) name = @"Discord user";
        if (![userID isKindOfClass:[NSString class]]) userID = @"";
        if (![avatarHash isKindOfClass:[NSString class]]) avatarHash = @"";

        CGFloat rowY = rowTop - (CGFloat)index * 44.0 - 41.0;
        NSRect rowRect = NSMakeRect(10.0, rowY, width - 20.0, 40.0);
        [WMColor(index % 2 ? 0.16 : 0.145, index % 2 ? 0.18 : 0.165, index % 2 ? 0.21 : 0.195, 1.0) setFill];
        NSRectFill(rowRect);
        if (speaking) {
            [WMColor(0.25, 0.70, 0.39, 1.0) setStroke];
            NSBezierPath *active = [NSBezierPath bezierPathWithRect:NSInsetRect(rowRect, 0.5, 0.5)];
            [active setLineWidth:1.3]; [active stroke];
        } else {
            WMDrawBevel(rowRect, WMColor(0.23, 0.26, 0.30, 1.0), WMColor(0.075, 0.085, 0.105, 1.0), 0.7);
        }

        NSRect avatarRect = NSMakeRect(16.0, rowY + 4.0, 32.0, 32.0);
        NSImage *avatarImage = [_avatarCache imageForUserID:userID avatarHash:avatarHash];
        if (avatarImage) {
            NSBezierPath *clip = [NSBezierPath bezierPathWithOvalInRect:avatarRect];
            [NSGraphicsContext saveGraphicsState];
            [clip addClip];
            [avatarImage drawInRect:avatarRect];
            [NSGraphicsContext restoreGraphicsState];
        } else {
            NSBezierPath *placeholder = [NSBezierPath bezierPathWithOvalInRect:avatarRect];
            [WMColor(0.29, 0.33, 0.39, 1.0) setFill]; [placeholder fill];
            NSString *initial = [WMFirstComposedCharacter(name) uppercaseString];
            NSDictionary *initialAttrs = WMTextAttributes([NSFont boldSystemFontOfSize:12.0], WMColor(0.94, 0.95, 0.97, 1.0));
            NSSize initialSize = [initial sizeWithAttributes:initialAttrs];
            [initial drawAtPoint:NSMakePoint(NSMidX(avatarRect) - initialSize.width / 2.0,
                NSMidY(avatarRect) - initialSize.height / 2.0) withAttributes:initialAttrs];
        }
        NSBezierPath *avatarBorder = [NSBezierPath bezierPathWithOvalInRect:avatarRect];
        NSColor *avatarStroke = speaking ? WMColor(0.34, 0.94, 0.52, 1.0) : WMColor(0.49, 0.54, 0.60, 1.0);
        [avatarStroke setStroke];
        [avatarBorder setLineWidth:speaking ? 2.0 : 0.8]; [avatarBorder stroke];

        NSString *fittedName = WMStringFittingWidth(name, nameAttrs, width - 105.0);
        [fittedName drawAtPoint:NSMakePoint(56.0, rowY + 22.0) withAttributes:nameAttrs];
        NSString *state = speaking ? @"Speaking" : (deafened ? @"Deafened" :
            (muted ? @"Muted" : (bot ? @"Bot" : @"In voice")));
        NSDictionary *personState = WMTextAttributes([NSFont systemFontOfSize:9.0],
            speaking ? WMColor(0.43, 0.94, 0.58, 1.0) : WMColor(0.68, 0.73, 0.79, 1.0));
        [state drawAtPoint:NSMakePoint(56.0, rowY + 7.0) withAttributes:personState];

        NSString *mic = deafened ? @"DEAF" : (muted ? @"MUTE" : (speaking ? @"LIVE" : @"MIC"));
        NSDictionary *micAttrs = WMTextAttributes([NSFont boldSystemFontOfSize:7.5],
            speaking ? WMColor(0.43, 0.94, 0.58, 1.0) : (deafened ? WMColor(1.0, 0.52, 0.43, 1.0) : WMColor(0.72, 0.76, 0.81, 1.0)));
        NSSize micSize = [mic sizeWithAttributes:micAttrs];
        [mic drawAtPoint:NSMakePoint(width - 17.0 - micSize.width, rowY + 15.0) withAttributes:micAttrs];
    }

    if (visible == 0) {
        NSString *empty = [_channel length] ? @"Waiting for participants…" : @"Join a voice channel to show the overlay";
        [empty drawAtPoint:NSMakePoint(17.0, height - 117.0) withAttributes:stateAttrs];
    }
    if ([_participants count] > visible) {
        NSString *overflow = [NSString stringWithFormat:@"+ %lu more", (unsigned long)([_participants count] - visible)];
        [overflow drawAtPoint:NSMakePoint(17.0, 15.0) withAttributes:smallAttrs];
    } else {
        NSString *footer = [NSString stringWithFormat:@"%lu in voice", (unsigned long)[_participants count]];
        [footer drawAtPoint:NSMakePoint(17.0, 15.0) withAttributes:smallAttrs];
    }
    NSString *hint = _clickThrough ? @"Ctrl+Alt+O: interact" : @"drag to move  ·  Ctrl+Alt+O: pass through";
    NSString *fittedHint = WMStringFittingWidth(hint, smallAttrs, width - 115.0);
    NSSize hintSize = [fittedHint sizeWithAttributes:smallAttrs];
    [fittedHint drawAtPoint:NSMakePoint(width - 17.0 - hintSize.width, 15.0) withAttributes:smallAttrs];
}

- (void)mouseDown:(NSEvent *)event
{
    if (_clickThrough) return;
    _dragStart = [event locationInWindow];
    _windowStart = [[self window] frame].origin;
}

- (void)mouseDragged:(NSEvent *)event
{
    if (_clickThrough) return;
    NSPoint point = [event locationInWindow];
    NSPoint origin = NSMakePoint(_windowStart.x + point.x - _dragStart.x,
                                 _windowStart.y + point.y - _dragStart.y);
    [[self window] setFrameOrigin:origin];
}

- (void)mouseUp:(NSEvent *)event
{
    (void)event;
    if (_clickThrough || !_delegate) return;
    [_delegate overlayViewDidMoveToOrigin:[[self window] frame].origin];
}
@end
