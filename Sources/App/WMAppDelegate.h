// SPDX-License-Identifier: GPL-2.0-only
#ifndef WM_APP_DELEGATE_H
#define WM_APP_DELEGATE_H

#import <AppKit/AppKit.h>
#import "../Discord/WMRPCClient.h"
#import "../Models/WMVoiceModel.h"
#import "../Overlay/WMOverlayView.h"
#import "../Overlay/WMAvatarCache.h"

@interface WMAppDelegate : NSObject <NSApplicationDelegate, WMRPCClientDelegate,
    WMOverlayViewDelegate, WMAvatarCacheDelegate>
{
    NSWindow *_panel;
    WMOverlayView *_overlayView;
    WMVoiceModel *_voiceModel;
    WMRPCClient *_rpcClient;
    WMAvatarCache *_avatarCache;
    NSTimer *_demoTimer;
    NSTimer *_x11Timer;
    BOOL _demoMode;
    BOOL _alwaysVisible;
    BOOL _clickThrough;
    NSUInteger _demoSpeakingIndex;
}
- (void)toggleClickThrough:(id)sender;
- (void)toggleClickThroughFromHotkey;
- (void)setOverlayCorner:(id)sender;
@end

#endif
