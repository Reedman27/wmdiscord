// SPDX-License-Identifier: GPL-2.0-only
#ifndef WM_PARTICIPANT_H
#define WM_PARTICIPANT_H

#import <Foundation/Foundation.h>

@interface WMParticipant : NSObject <NSCopying>
{
    NSString *_userID;
    NSString *_displayName;
    NSString *_avatarHash;
    BOOL _speaking;
    BOOL _muted;
    BOOL _deafened;
    BOOL _bot;
}
- (id)initWithUserID:(NSString *)userID;
- (NSString *)userID;
- (NSString *)displayName;
- (NSString *)avatarHash;
- (BOOL)isSpeaking;
- (BOOL)isMuted;
- (BOOL)isDeafened;
- (BOOL)isBot;
- (void)setDisplayName:(NSString *)value;
- (void)setAvatarHash:(NSString *)value;
- (void)setSpeaking:(BOOL)value;
- (void)setMuted:(BOOL)value;
- (void)setDeafened:(BOOL)value;
- (void)setBot:(BOOL)value;
- (void)applyVoicePayload:(NSDictionary *)payload;
- (NSDictionary *)dictionaryRepresentation;
@end

#endif
