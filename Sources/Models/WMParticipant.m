// SPDX-License-Identifier: GPL-2.0-only
#import "WMParticipant.h"
#include <stdlib.h>
#include <stdint.h>

static BOOL WMBoolean(NSDictionary *dictionary, NSString *key)
{
    id value = [dictionary objectForKey:key];
    return [value respondsToSelector:@selector(boolValue)] ? [value boolValue] : NO;
}

@implementation WMParticipant
- (id)initWithUserID:(NSString *)userID
{
    self = [super init];
    if (self) {
        _userID = [userID copy];
        _displayName = [@"Discord user" copy];
    }
    return self;
}
- (void)dealloc
{
    [_userID release];
    [_displayName release];
    [_avatarHash release];
    [super dealloc];
}
- (NSString *)userID { return _userID; }
- (NSString *)displayName { return _displayName; }
- (NSString *)avatarHash { return _avatarHash; }
- (BOOL)isSpeaking { return _speaking; }
- (BOOL)isMuted { return _muted; }
- (BOOL)isDeafened { return _deafened; }
- (BOOL)isBot { return _bot; }
- (void)setDisplayName:(NSString *)value
{
    if (![value isKindOfClass:[NSString class]] || [value length] == 0) return;
    if (_displayName != value) { [_displayName release]; _displayName = [value copy]; }
}
- (void)setAvatarHash:(NSString *)value
{
    if (![value isKindOfClass:[NSString class]]) return;
    if (_avatarHash != value) { [_avatarHash release]; _avatarHash = [value copy]; }
}
- (void)setSpeaking:(BOOL)value { _speaking = value; }
- (void)setMuted:(BOOL)value { _muted = value; }
- (void)setDeafened:(BOOL)value { _deafened = value; }
- (void)setBot:(BOOL)value { _bot = value; }

- (void)applyVoicePayload:(NSDictionary *)payload
{
    if (![payload isKindOfClass:[NSDictionary class]]) return;
    NSDictionary *user = [payload objectForKey:@"user"];
    NSDictionary *voice = [payload objectForKey:@"voice_state"];
    if (![user isKindOfClass:[NSDictionary class]]) user = [NSDictionary dictionary];
    if (![voice isKindOfClass:[NSDictionary class]]) voice = [NSDictionary dictionary];

    NSString *name = [payload objectForKey:@"nick"];
    if (![name isKindOfClass:[NSString class]] || [name length] == 0)
        name = [user objectForKey:@"global_name"];
    if (![name isKindOfClass:[NSString class]] || [name length] == 0)
        name = [user objectForKey:@"username"];
    [self setDisplayName:name];
    NSString *avatar = [user objectForKey:@"avatar"];
    if (![avatar isKindOfClass:[NSString class]] || [avatar length] == 0) {
        /* Discord's default avatar bucket is derived from the user snowflake. */
        unsigned long long snowflake = (unsigned long long)strtoull([_userID UTF8String], NULL, 10);
        avatar = [NSString stringWithFormat:@"default_%llu", (snowflake >> 22) % 6ULL];
    }
    [self setAvatarHash:avatar];
    if ([user objectForKey:@"bot"]) [self setBot:WMBoolean(user, @"bot")];

    /* RPC payloads have used both top-level and nested voice-state flags. */
    BOOL muted = WMBoolean(payload, @"mute") || WMBoolean(payload, @"self_mute") ||
                 WMBoolean(voice, @"mute") || WMBoolean(voice, @"self_mute");
    BOOL deafened = WMBoolean(payload, @"deaf") || WMBoolean(payload, @"self_deaf") ||
                    WMBoolean(voice, @"deaf") || WMBoolean(voice, @"self_deaf");
    [self setMuted:muted];
    [self setDeafened:deafened];
}

- (NSDictionary *)dictionaryRepresentation
{
    return [NSDictionary dictionaryWithObjectsAndKeys:
        (_userID ? _userID : @""), @"id",
        (_displayName ? _displayName : @"Discord user"), @"name",
        [NSNumber numberWithBool:_speaking], @"speaking",
        [NSNumber numberWithBool:_muted], @"muted",
        [NSNumber numberWithBool:_deafened], @"deafened",
        [NSNumber numberWithBool:_bot], @"bot",
        (_avatarHash ? _avatarHash : @""), @"avatar", nil];
}

- (id)copyWithZone:(NSZone *)zone
{
    WMParticipant *copy = [[[self class] allocWithZone:zone] initWithUserID:_userID];
    [copy setDisplayName:_displayName];
    [copy setAvatarHash:_avatarHash];
    [copy setSpeaking:_speaking];
    [copy setMuted:_muted];
    [copy setDeafened:_deafened];
    [copy setBot:_bot];
    return copy;
}
@end
