// SPDX-License-Identifier: GPL-2.0-only
#ifndef WM_VOICE_MODEL_H
#define WM_VOICE_MODEL_H

#import <Foundation/Foundation.h>

@interface WMVoiceModel : NSObject
{
    NSMutableDictionary *_participants;
    NSString *_channelName;
    NSString *_channelID;
    NSString *_status;
    BOOL _selfMuted;
    BOOL _selfDeafened;
}
- (void)reset;
- (void)setStatus:(NSString *)status;
- (NSString *)status;
- (NSString *)channelName;
- (void)setChannelName:(NSString *)name channelID:(NSString *)channelID;
- (BOOL)isSelfMuted;
- (BOOL)isSelfDeafened;
- (NSArray *)participantSnapshots;
- (void)applyChannelSnapshot:(NSDictionary *)channel;
- (void)applyEvent:(NSString *)event data:(NSDictionary *)data;
@end

#endif
