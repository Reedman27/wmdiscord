// SPDX-License-Identifier: GPL-2.0-only
#ifndef WM_OVERLAY_VIEW_H
#define WM_OVERLAY_VIEW_H

#import <AppKit/AppKit.h>
#import "WMAvatarCache.h"

@protocol WMOverlayViewDelegate <NSObject>
- (void)overlayViewDidMoveToOrigin:(NSPoint)origin;
@end

@interface WMOverlayView : NSView
{
    NSArray *_participants;
    NSString *_status;
    NSString *_channel;
    BOOL _selfMuted;
    BOOL _selfDeafened;
    BOOL _clickThrough;
    NSPoint _dragStart;
    NSPoint _windowStart;
    id<WMOverlayViewDelegate> _delegate; /* assign */
    WMAvatarCache *_avatarCache; /* assign; owned by AppDelegate */
}
- (BOOL)isOpaque;
- (void)setStatus:(NSString *)status channel:(NSString *)channel;
- (void)setParticipants:(NSArray *)participants selfMuted:(BOOL)muted selfDeafened:(BOOL)deafened;
- (void)setAvatarCache:(WMAvatarCache *)cache;
- (void)setDelegate:(id<WMOverlayViewDelegate>)delegate;
- (void)setClickThrough:(BOOL)value;
@end

#endif
