// SPDX-License-Identifier: GPL-2.0-only
#import "WMVoiceModel.h"
#import "WMParticipant.h"

static NSInteger WMCompareSnapshots(id left, id right, void *context)
{
    (void)context;
    NSString *a = [left objectForKey:@"name"];
    NSString *b = [right objectForKey:@"name"];
    return (NSInteger)[a localizedCaseInsensitiveCompare:b];
}

@implementation WMVoiceModel
- (id)init
{
    self = [super init];
    if (self) {
        _participants = [[NSMutableDictionary alloc] init];
        _channelName = [@"" copy];
        _channelID = [@"" copy];
        _status = [@"Waiting for Discord" copy];
    }
    return self;
}
- (void)dealloc
{
    [_participants release]; [_channelName release]; [_channelID release]; [_status release];
    [super dealloc];
}
- (void)reset
{
    [_participants removeAllObjects];
    [self setChannelName:@"" channelID:@""];
    _selfMuted = NO; _selfDeafened = NO;
}
- (void)setStatus:(NSString *)status
{
    NSString *next = ([status isKindOfClass:[NSString class]] && [status length]) ? status : @"";
    if (_status != next) { [_status release]; _status = [next copy]; }
}
- (NSString *)status { return _status; }
- (NSString *)channelName { return _channelName; }
- (void)setChannelName:(NSString *)name channelID:(NSString *)channelID
{
    NSString *safeName = [name isKindOfClass:[NSString class]] ? name : @"";
    NSString *safeID = [channelID isKindOfClass:[NSString class]] ? channelID : @"";
    if (_channelName != safeName) { [_channelName release]; _channelName = [safeName copy]; }
    if (_channelID != safeID) { [_channelID release]; _channelID = [safeID copy]; }
    if ([safeID length] == 0) [_participants removeAllObjects];
}
- (BOOL)isSelfMuted { return _selfMuted; }
- (BOOL)isSelfDeafened { return _selfDeafened; }

- (NSArray *)participantSnapshots
{
    NSMutableArray *result = [NSMutableArray arrayWithCapacity:[_participants count]];
    for (WMParticipant *participant in [_participants allValues])
        [result addObject:[participant dictionaryRepresentation]];
    [result sortUsingFunction:WMCompareSnapshots context:NULL];
    return result;
}

- (NSString *)_userIDFromPayload:(NSDictionary *)data
{
    NSString *uid = [data objectForKey:@"user_id"];
    NSDictionary *user = [data objectForKey:@"user"];
    if (![uid isKindOfClass:[NSString class]] && [user isKindOfClass:[NSDictionary class]])
        uid = [user objectForKey:@"id"];
    return [uid isKindOfClass:[NSString class]] ? uid : nil;
}

- (WMParticipant *)_participantForID:(NSString *)uid create:(BOOL)create
{
    if (![uid isKindOfClass:[NSString class]] || [uid length] == 0) return nil;
    WMParticipant *participant = [_participants objectForKey:uid];
    if (!participant && create) {
        participant = [[[WMParticipant alloc] initWithUserID:uid] autorelease];
        [_participants setObject:participant forKey:uid];
    }
    return participant;
}

- (void)applyChannelSnapshot:(NSDictionary *)channel
{
    if (![channel isKindOfClass:[NSDictionary class]] || channel == (id)[NSNull null]) {
        [self setChannelName:@"" channelID:@""];
        return;
    }
    NSString *channelID = [channel objectForKey:@"id"];
    NSString *name = [channel objectForKey:@"name"];
    [self setChannelName:(name ? name : @"Voice channel") channelID:channelID];
    NSArray *states = [channel objectForKey:@"voice_states"];
    if ([states isKindOfClass:[NSArray class]]) {
        [_participants removeAllObjects];
        for (NSDictionary *state in states) {
            NSString *uid = [self _userIDFromPayload:state];
            WMParticipant *participant = [self _participantForID:uid create:YES];
            [participant applyVoicePayload:state];
        }
    }
}

- (void)applyEvent:(NSString *)event data:(NSDictionary *)data
{
    if (![event isKindOfClass:[NSString class]] || ![data isKindOfClass:[NSDictionary class]]) return;
    if ([event isEqualToString:@"VOICE_STATE_CREATE"] || [event isEqualToString:@"VOICE_STATE_UPDATE"]) {
        NSString *uid = [self _userIDFromPayload:data];
        WMParticipant *participant = [self _participantForID:uid create:YES];
        [participant applyVoicePayload:data];
    } else if ([event isEqualToString:@"VOICE_STATE_DELETE"]) {
        NSString *uid = [self _userIDFromPayload:data];
        if (uid) [_participants removeObjectForKey:uid];
    } else if ([event isEqualToString:@"SPEAKING_START"] || [event isEqualToString:@"SPEAKING_STOP"]) {
        NSString *uid = [self _userIDFromPayload:data];
        WMParticipant *participant = [self _participantForID:uid create:YES];
        [participant setSpeaking:[event isEqualToString:@"SPEAKING_START"]];
    } else if ([event isEqualToString:@"VOICE_SETTINGS_UPDATE"]) {
        id mute = [data objectForKey:@"mute"];
        id deaf = [data objectForKey:@"deaf"];
        if ([mute respondsToSelector:@selector(boolValue)]) _selfMuted = [mute boolValue];
        if ([deaf respondsToSelector:@selector(boolValue)]) _selfDeafened = [deaf boolValue];
    } else if ([event isEqualToString:@"VOICE_CHANNEL_SELECT"]) {
        id channelID = [data objectForKey:@"channel_id"];
        if (channelID == (id)[NSNull null] || ![channelID isKindOfClass:[NSString class]]) {
            [self setChannelName:@"" channelID:@""];
        }
    }
}
@end
