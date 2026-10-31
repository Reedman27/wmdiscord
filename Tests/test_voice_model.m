// SPDX-License-Identifier: GPL-2.0-only
#import <Foundation/Foundation.h>
#include <stdio.h>
#include <stdlib.h>
#import "../Sources/Models/WMVoiceModel.h"

static void Check(BOOL condition, NSString *message)
{
    if (!condition) {
        fprintf(stderr, "FAIL: %s\n", [message UTF8String]);
        exit(1);
    }
}

int main(void)
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    WMVoiceModel *model = [[WMVoiceModel alloc] init];

    NSDictionary *alice = [NSDictionary dictionaryWithObjectsAndKeys:
        [NSDictionary dictionaryWithObjectsAndKeys:@"u-alice", @"id", @"Alice", @"username", nil], @"user",
        [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool:NO], @"mute",
            [NSNumber numberWithBool:YES], @"self_mute", nil], @"voice_state", nil];
    NSDictionary *bob = [NSDictionary dictionaryWithObjectsAndKeys:
        [NSDictionary dictionaryWithObjectsAndKeys:@"u-bob", @"id", @"Bob", @"username", nil], @"user",
        [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool:YES], @"deaf", nil], @"voice_state", nil];
    NSDictionary *channel = [NSDictionary dictionaryWithObjectsAndKeys:
        @"c-1", @"id", @"General", @"name", [NSArray arrayWithObjects:alice, bob, nil], @"voice_states", nil];
    [model applyChannelSnapshot:channel];
    NSArray *people = [model participantSnapshots];
    Check([people count] == 2, @"channel snapshot should add both members");
    Check([[model channelName] isEqualToString:@"General"], @"channel name should be retained");
    BOOL unicodeNamePreserved = NO;
    for (NSDictionary *person in people) {
        if ([[person objectForKey:@"id"] isEqualToString:@"u-alice"]) {
            unicodeNamePreserved = [[person objectForKey:@"name"] isEqualToString:@"Alice"];
            Check([[person objectForKey:@"avatar"] hasPrefix:@"default_"], @"users without custom avatars should receive a default avatar bucket");
        }
    }
    Check(unicodeNamePreserved, @"participant names should remain intact in the model");

    NSDictionary *unicodeUser = [NSDictionary dictionaryWithObjectsAndKeys:
        [NSDictionary dictionaryWithObjectsAndKeys:@"u-unicode", @"id", @"月の騎士 🎮", @"global_name", @"abc123", @"avatar", nil], @"user",
        [NSDictionary dictionary], @"voice_state", nil];
    [model applyEvent:@"VOICE_STATE_CREATE" data:unicodeUser];
    BOOL unicodeAndAvatarPreserved = NO;
    for (NSDictionary *person in [model participantSnapshots]) {
        if ([[person objectForKey:@"id"] isEqualToString:@"u-unicode"])
            unicodeAndAvatarPreserved = [[person objectForKey:@"name"] isEqualToString:@"月の騎士 🎮"] &&
                [[person objectForKey:@"avatar"] isEqualToString:@"abc123"];
    }
    Check(unicodeAndAvatarPreserved, @"Unicode display names and custom avatar hashes should be preserved");

    NSDictionary *decoratedUser = [NSDictionary dictionaryWithObjectsAndKeys:
        [NSDictionary dictionaryWithObjectsAndKeys:@"u-decorated", @"id", @"꧁ঔৣ☬RĪØT☬ঔৣ꧂", @"username", nil], @"user",
        [NSDictionary dictionary], @"voice_state", nil];
    [model applyEvent:@"VOICE_STATE_CREATE" data:decoratedUser];
    BOOL decoratedNamePreserved = NO;
    for (NSDictionary *person in [model participantSnapshots]) {
        if ([[person objectForKey:@"id"] isEqualToString:@"u-decorated"])
            decoratedNamePreserved = [[person objectForKey:@"name"] isEqualToString:@"꧁ঔৣ☬RĪØT☬ঔৣ꧂"];
    }
    Check(decoratedNamePreserved, @"decorative Unicode characters must survive the voice model unchanged");

    [model applyEvent:@"SPEAKING_START" data:[NSDictionary dictionaryWithObject:@"u-bob" forKey:@"user_id"]];
    people = [model participantSnapshots];
    BOOL bobSpeaking = NO, aliceMuted = NO, bobDeafened = NO;
    for (NSDictionary *person in people) {
        if ([[person objectForKey:@"id"] isEqualToString:@"u-bob"]) {
            bobSpeaking = [[person objectForKey:@"speaking"] boolValue];
            bobDeafened = [[person objectForKey:@"deafened"] boolValue];
        }
        if ([[person objectForKey:@"id"] isEqualToString:@"u-alice"])
            aliceMuted = [[person objectForKey:@"muted"] boolValue];
    }
    Check(bobSpeaking, @"speaking start should set the speaking flag");
    Check(aliceMuted, @"nested self_mute should count as muted");
    Check(bobDeafened, @"nested deaf flag should count as deafened");

    NSDictionary *aliceUpdate = [NSDictionary dictionaryWithObjectsAndKeys:
        [NSDictionary dictionaryWithObjectsAndKeys:@"u-alice", @"id", @"AliceUpdated", @"username", nil], @"user",
        [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool:NO], @"mute",
            [NSNumber numberWithBool:NO], @"self_mute", nil], @"voice_state", nil];
    [model applyEvent:@"VOICE_STATE_UPDATE" data:aliceUpdate];
    for (NSDictionary *person in [model participantSnapshots]) {
        if ([[person objectForKey:@"id"] isEqualToString:@"u-alice"]) {
            Check([[person objectForKey:@"name"] isEqualToString:@"AliceUpdated"], @"voice state update should refresh participant name");
            Check(![[person objectForKey:@"muted"] boolValue], @"voice state update should clear mute state");
        }
    }
    [model applyEvent:@"SPEAKING_STOP" data:[NSDictionary dictionaryWithObject:@"u-bob" forKey:@"user_id"]];
    for (NSDictionary *person in [model participantSnapshots]) {
        if ([[person objectForKey:@"id"] isEqualToString:@"u-bob"])
            Check(![[person objectForKey:@"speaking"] boolValue], @"speaking stop should clear the speaking flag");
    }

    [model applyEvent:@"VOICE_STATE_DELETE" data:[NSDictionary dictionaryWithObject:@"u-alice" forKey:@"user_id"]];
    Check([[model participantSnapshots] count] == 1, @"voice state delete should remove a member");

    [model applyEvent:@"VOICE_SETTINGS_UPDATE" data:[NSDictionary dictionaryWithObjectsAndKeys:
        [NSNumber numberWithBool:YES], @"mute", [NSNumber numberWithBool:NO], @"deaf", nil]];
    Check([model isSelfMuted], @"local mute state should update");
    Check(![model isSelfDeafened], @"local deaf state should update");

    [model applyChannelSnapshot:nil];
    Check([[model participantSnapshots] count] == 0, @"leaving voice should clear members");
    Check([[model channelName] length] == 0, @"leaving voice should clear channel name");
    [model applyChannelSnapshot:channel];
    [model applyEvent:@"VOICE_CHANNEL_SELECT" data:[NSDictionary dictionaryWithObject:[NSNull null] forKey:@"channel_id"]];
    Check([[model channelName] length] == 0, @"voice channel select with null id should clear the channel");

    [model release];
    [pool drain];
    puts("PASS: voice model state transitions");
    return 0;
}
