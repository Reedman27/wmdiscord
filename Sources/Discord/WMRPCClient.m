// SPDX-License-Identifier: GPL-2.0-only
#import "WMRPCClient.h"
#import "WMOAuthStore.h"

#include <sys/socket.h>
#include <sys/un.h>
#include <sys/stat.h>
#include <sys/poll.h>
#include <unistd.h>
#include <errno.h>
#include <stdint.h>
#include <string.h>
#include <stdlib.h>
#include <time.h>

#define WM_RPC_MAX_FRAME (4U * 1024U * 1024U)

static uint32_t WMHostToLE32(uint32_t value)
{
    const uint16_t one = 1;
    if (*(const unsigned char *)&one == 1) return value;
    return ((value & 0x000000FFU) << 24) | ((value & 0x0000FF00U) << 8) |
           ((value & 0x00FF0000U) >> 8) | ((value & 0xFF000000U) >> 24);
}

static void WMSleepMS(long milliseconds)
{
    struct timespec request;
    request.tv_sec = milliseconds / 1000;
    request.tv_nsec = (milliseconds % 1000) * 1000000L;
    while (nanosleep(&request, &request) < 0 && errno == EINTR) { }
}

static void WMLog(NSString *message)
{
    fprintf(stderr, "[WMDiscord] %s\n", [message UTF8String] ? [message UTF8String] : "(message)");
}

@interface WMRPCClient (Worker)
- (void)_run;
- (int)_connectToDiscord;
- (BOOL)_installSocket:(int)fd;
- (BOOL)_writeAll:(const void *)bytes length:(size_t)length fd:(int)fd;
- (BOOL)_sendOpcode:(uint32_t)opcode object:(NSDictionary *)object fd:(int)fd;
- (NSDictionary *)_readFrameFD:(int)fd opcode:(uint32_t *)opcode;
- (BOOL)_readExact:(void *)buffer length:(size_t)length fd:(int)fd;
- (NSDictionary *)_request:(NSString *)command arguments:(NSDictionary *)arguments
                      event:(NSString *)event fd:(int)fd;
- (BOOL)_authenticateOnFD:(int)fd;
- (BOOL)_authorizeOnFD:(int)fd;
- (void)_processEvent:(NSString *)event data:(NSDictionary *)data;
- (void)_refreshSelectedChannelOnFD:(int)fd;
- (void)_subscribeChannel:(NSString *)channelID fd:(int)fd;
- (void)_unsubscribeChannel:(NSString *)channelID fd:(int)fd;
- (void)_deliverStatus:(NSString *)status;
- (void)_deliverConnected;
- (void)_deliverDisconnected:(NSString *)reason;
- (void)_deliverEvent:(NSString *)event data:(NSDictionary *)data;
@end

static BOOL WMIsStopping(WMRPCClient *client);
static void *WMWorkerEntry(void *opaque);

@implementation WMRPCClient

- (id)initWithApplicationID:(NSString *)applicationID clientSecret:(NSString *)clientSecret
                redirectURI:(NSString *)redirectURI delegate:(id<WMRPCClientDelegate>)delegate
{
    self = [super init];
    if (self) {
        _applicationID = [applicationID copy];
        _clientSecret = [clientSecret copy];
        _redirectURI = [redirectURI copy];
        _delegate = delegate;
        _socketFD = -1;
        pthread_mutex_init(&_mutex, NULL);
    }
    return self;
}

- (BOOL)start
{
    pthread_mutex_lock(&_mutex);
    if (_started) { pthread_mutex_unlock(&_mutex); return YES; }
    _stopping = NO;
    int rc = pthread_create(&_worker, NULL, WMWorkerEntry, self);
    if (rc == 0) _started = YES;
    pthread_mutex_unlock(&_mutex);
    if (rc != 0) WMLog([NSString stringWithFormat:@"pthread_create failed: %s", strerror(rc)]);
    return rc == 0;
}

- (void)stop
{
    pthread_mutex_lock(&_mutex);
    _stopping = YES;
    int fd = _socketFD;
    BOOL shouldJoin = _started;
    pthread_t thread = _worker;
    _started = NO;
    pthread_mutex_unlock(&_mutex);
    if (fd >= 0) shutdown(fd, SHUT_RDWR);
    if (shouldJoin && !pthread_equal(pthread_self(), thread)) pthread_join(thread, NULL);
}

- (BOOL)isStopping
{
    pthread_mutex_lock(&_mutex);
    BOOL result = _stopping;
    pthread_mutex_unlock(&_mutex);
    return result;
}

- (void)dealloc
{
    [self stop];
    [_applicationID release]; [_clientSecret release]; [_redirectURI release];
    [_subscribedChannelID release];
    pthread_mutex_destroy(&_mutex);
    [super dealloc];
}

- (void)_deliverStatus:(NSString *)status
{
    id delegate = _delegate;
    if (delegate && [delegate respondsToSelector:@selector(rpcClientDidChangeStatus:)])
        [delegate performSelectorOnMainThread:@selector(rpcClientDidChangeStatus:)
                                   withObject:status waitUntilDone:NO];
}
- (void)_deliverConnected
{
    id delegate = _delegate;
    if (delegate && [delegate respondsToSelector:@selector(rpcClientDidConnect)])
        [delegate performSelectorOnMainThread:@selector(rpcClientDidConnect) withObject:nil waitUntilDone:NO];
}
- (void)_deliverDisconnected:(NSString *)reason
{
    id delegate = _delegate;
    if (delegate && [delegate respondsToSelector:@selector(rpcClientDidDisconnectWithReason:)])
        [delegate performSelectorOnMainThread:@selector(rpcClientDidDisconnectWithReason:)
                                   withObject:reason waitUntilDone:NO];
}
- (void)_deliverEvent:(NSString *)event data:(NSDictionary *)data
{
    id delegate = _delegate;
    if (!delegate) return;
    NSDictionary *safeData = [data isKindOfClass:[NSDictionary class]] ? data : [NSDictionary dictionary];
    NSDictionary *envelope = [NSDictionary dictionaryWithObjectsAndKeys:
        (event ? event : @""), @"event", safeData, @"data", nil];
    if ([delegate respondsToSelector:@selector(rpcClientDeliverEvent:)])
        [delegate performSelectorOnMainThread:@selector(rpcClientDeliverEvent:)
                                   withObject:envelope waitUntilDone:NO];
}

- (BOOL)_installSocket:(int)fd
{
    pthread_mutex_lock(&_mutex);
    BOOL canInstall = !_stopping;
    if (canInstall) _socketFD = fd;
    pthread_mutex_unlock(&_mutex);
    return canInstall;
}

- (int)_connectToDiscord
{
    NSMutableArray *directories = [NSMutableArray array];
    const char *names[] = {"XDG_RUNTIME_DIR", "TMPDIR", "TMP", "TEMP"};
    for (NSUInteger i = 0; i < sizeof(names) / sizeof(names[0]); i++) {
        const char *value = getenv(names[i]);
        if (value && value[0]) {
            NSString *directory = [NSString stringWithUTF8String:value];
            if (directory && ![directories containsObject:directory]) [directories addObject:directory];
        }
    }
    [directories addObject:@"/tmp"];

    for (NSString *directory in directories) {
        for (int index = 0; index < 10 && !WMIsStopping(self); index++) {
            NSString *path = [directory stringByAppendingPathComponent:
                [NSString stringWithFormat:@"discord-ipc-%d", index]];
            struct stat info;
            if (lstat([path fileSystemRepresentation], &info) != 0 || !S_ISSOCK(info.st_mode)) continue;
            int fd = socket(AF_UNIX, SOCK_STREAM, 0);
            if (fd < 0) continue;
            struct sockaddr_un address;
            memset(&address, 0, sizeof(address));
            address.sun_family = AF_UNIX;
            const char *socketPath = [path fileSystemRepresentation];
            if (strlen(socketPath) >= sizeof(address.sun_path)) { close(fd); continue; }
            memcpy(address.sun_path, socketPath, strlen(socketPath) + 1);
            if (connect(fd, (struct sockaddr *)&address, sizeof(address)) == 0) {
                WMLog([NSString stringWithFormat:@"Connected to Discord IPC at %@", path]);
                return fd;
            }
            close(fd);
        }
    }
    return -1;
}

- (BOOL)_writeAll:(const void *)bytes length:(size_t)length fd:(int)fd
{
    const unsigned char *cursor = (const unsigned char *)bytes;
    size_t written = 0;
    while (written < length && !WMIsStopping(self)) {
#ifdef MSG_NOSIGNAL
        ssize_t count = send(fd, cursor + written, length - written, MSG_NOSIGNAL);
#else
        ssize_t count = send(fd, cursor + written, length - written, 0);
#endif
        if (count < 0 && errno == EINTR) continue;
        if (count <= 0) return NO;
        written += (size_t)count;
    }
    return written == length;
}

- (BOOL)_sendOpcode:(uint32_t)opcode object:(NSDictionary *)object fd:(int)fd
{
    NSError *error = nil;
    NSData *payload = [NSJSONSerialization dataWithJSONObject:object options:0 error:&error];
    if (!payload || [payload length] > WM_RPC_MAX_FRAME) {
        WMLog([NSString stringWithFormat:@"Could not serialize RPC frame: %@", error]);
        return NO;
    }
    /* Discord IPC wire order is opcode first, then payload length (both LE uint32). */
    uint32_t header[2] = {WMHostToLE32(opcode), WMHostToLE32((uint32_t)[payload length])};
    return [self _writeAll:header length:sizeof(header) fd:fd] &&
           [self _writeAll:[payload bytes] length:[payload length] fd:fd];
}

- (BOOL)_readExact:(void *)buffer length:(size_t)length fd:(int)fd
{
    unsigned char *cursor = (unsigned char *)buffer;
    size_t received = 0;
    while (received < length && !WMIsStopping(self)) {
        struct pollfd descriptor;
        descriptor.fd = fd; descriptor.events = POLLIN; descriptor.revents = 0;
        int ready = poll(&descriptor, 1, 500);
        if (ready < 0 && errno == EINTR) continue;
        if (ready < 0) {
            WMLog([NSString stringWithFormat:@"poll() failed while reading Discord IPC: %s", strerror(errno)]);
            return NO;
        }
        if (ready == 0) continue;
        if (descriptor.revents & POLLNVAL) {
            WMLog(@"Discord IPC socket became invalid while reading");
            return NO;
        }
        if ((descriptor.revents & (POLLERR | POLLHUP)) && !(descriptor.revents & POLLIN)) {
            WMLog([NSString stringWithFormat:@"Discord IPC socket hangup/error (revents=0x%x)", descriptor.revents]);
            return NO;
        }
        ssize_t count = recv(fd, cursor + received, length - received, 0);
        if (count < 0 && errno == EINTR) continue;
        if (count < 0) {
            WMLog([NSString stringWithFormat:@"recv() failed while reading Discord IPC: %s", strerror(errno)]);
            return NO;
        }
        if (count == 0) {
            WMLog(@"Discord closed the IPC stream (EOF)");
            return NO;
        }
        received += (size_t)count;
    }
    return received == length;
}

- (NSDictionary *)_readFrameFD:(int)fd opcode:(uint32_t *)opcode
{
    uint32_t header[2];
    if (![self _readExact:header length:sizeof(header) fd:fd]) return nil;
    uint32_t frameOpcode = WMHostToLE32(header[0]);
    uint32_t payloadLength = WMHostToLE32(header[1]);
    if (payloadLength > WM_RPC_MAX_FRAME) {
        WMLog([NSString stringWithFormat:@"Rejected oversized Discord IPC frame (%u bytes)", payloadLength]);
        return nil;
    }
    NSMutableData *payload = [NSMutableData dataWithLength:payloadLength];
    if (payloadLength && ![self _readExact:[payload mutableBytes] length:payloadLength fd:fd]) return nil;
    *opcode = frameOpcode;

    if (frameOpcode == 2) {
        id closeObject = nil;
        if (payloadLength) {
            NSError *closeError = nil;
            closeObject = [NSJSONSerialization JSONObjectWithData:payload options:0 error:&closeError];
        }
        if ([closeObject isKindOfClass:[NSDictionary class]]) {
            id code = [closeObject objectForKey:@"code"];
            id message = [closeObject objectForKey:@"message"];
            WMLog([NSString stringWithFormat:@"Discord sent IPC CLOSE (code=%@, message=%@)",
                code ? code : @"unknown", message ? message : @"no message"]);
        } else {
            WMLog([NSString stringWithFormat:@"Discord sent IPC CLOSE (payload=%u bytes)", payloadLength]);
        }
        return nil;
    }
    if (frameOpcode == 3) {
        uint32_t pongHeader[2] = {WMHostToLE32(4), WMHostToLE32(payloadLength)};
        if (![self _writeAll:pongHeader length:sizeof(pongHeader) fd:fd]) return nil;
        if (payloadLength && ![self _writeAll:[payload bytes] length:payloadLength fd:fd]) return nil;
        *opcode = 4;
        return [NSDictionary dictionary];
    }
    if (frameOpcode == 4) return [NSDictionary dictionary]; /* PONG has no JSON payload contract. */
    if (frameOpcode != 1) return [NSDictionary dictionary];
    NSError *error = nil;
    id parsed = [NSJSONSerialization JSONObjectWithData:payload options:NSJSONReadingMutableContainers error:&error];
    if (![parsed isKindOfClass:[NSDictionary class]]) {
        if (error) WMLog([NSString stringWithFormat:@"Invalid JSON in Discord IPC frame: %@", error]);
        return [NSDictionary dictionary];
    }
    return parsed;
}

- (NSDictionary *)_request:(NSString *)command arguments:(NSDictionary *)arguments event:(NSString *)event fd:(int)fd
{
    NSString *nonce = [[NSProcessInfo processInfo] globallyUniqueString];
    NSMutableDictionary *request = [NSMutableDictionary dictionaryWithObjectsAndKeys:
        command, @"cmd", nonce, @"nonce",
        (arguments ? arguments : [NSDictionary dictionary]), @"args", nil];
    if (event) [request setObject:event forKey:@"evt"];
    WMLog([NSString stringWithFormat:@"RPC -> %@%@", command, event ? [NSString stringWithFormat:@" (event %@)", event] : @""]);
    if (![self _sendOpcode:1 object:request fd:fd]) {
        WMLog([NSString stringWithFormat:@"Failed to send RPC command %@", command]);
        return nil;
    }

    while (!WMIsStopping(self)) {
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        uint32_t opcode = 0;
        NSDictionary *frame = [self _readFrameFD:fd opcode:&opcode];
        if (!frame) {
            WMLog([NSString stringWithFormat:@"RPC connection ended while waiting for %@ response", command]);
            [pool drain]; return nil;
        }
        if (opcode == 1) {
            id replyNonce = [frame objectForKey:@"nonce"];
            id replyEvent = [frame objectForKey:@"evt"];
            if ([replyNonce isKindOfClass:[NSString class]] && [replyNonce isEqualToString:nonce]) {
                NSDictionary *reply = [frame retain];
                if ([replyEvent isKindOfClass:[NSString class]] && [replyEvent isEqualToString:@"ERROR"]) {
                    id rawErrorData = [reply objectForKey:@"data"];
                    NSDictionary *errorData = [rawErrorData isKindOfClass:[NSDictionary class]] ? rawErrorData : [NSDictionary dictionary];
                    id errorCode = [errorData objectForKey:@"code"];
                    id errorMessage = [errorData objectForKey:@"message"];
                    WMLog([NSString stringWithFormat:@"RPC %@ rejected: code=%@ message=%@", command,
                        errorCode ? errorCode : @"unknown", errorMessage ? errorMessage : @"request failed"]);
                    [self _deliverStatus:[NSString stringWithFormat:@"Discord RPC error %@: %@",
                        errorCode ? errorCode : @"unknown", errorMessage ? errorMessage : @"request failed"]];
                    [reply release];
                    [pool drain];
                    return nil;
                }
                WMLog([NSString stringWithFormat:@"RPC <- %@ succeeded", command]);
                [pool drain];
                return [reply autorelease];
            }
            if ([replyEvent isKindOfClass:[NSString class]] && ![replyEvent isEqualToString:@"ERROR"] &&
                [frame objectForKey:@"data"]) {
                WMLog([NSString stringWithFormat:@"RPC event while waiting for %@: %@", command, replyEvent]);
                [self _processEvent:replyEvent data:[frame objectForKey:@"data"]];
            }
        }
        [pool drain];
    }
    return nil;
}

- (BOOL)_authenticateOnFD:(int)fd
{
    NSDictionary *stored = [WMOAuthStore loadToken];
    if ([stored isKindOfClass:[NSDictionary class]]) {
        NSNumber *expiry = [stored objectForKey:@"expires_at"];
        NSString *refresh = [stored objectForKey:@"refresh_token"];
        if ([expiry respondsToSelector:@selector(doubleValue)] &&
            [expiry doubleValue] < (double)time(NULL) + 90.0) {
            if ([refresh isKindOfClass:[NSString class]] && [_clientSecret length]) {
                NSError *refreshError = nil;
                NSDictionary *renewed = [WMOAuthStore refreshToken:refresh clientID:_applicationID
                    clientSecret:_clientSecret error:&refreshError];
                if (renewed) {
                    [WMOAuthStore saveTokenResponse:renewed error:NULL];
                    stored = renewed;
                } else {
                    WMLog([NSString stringWithFormat:@"OAuth refresh failed: %@", refreshError]);
                    [WMOAuthStore deleteToken];
                    stored = nil;
                }
            } else if ([expiry doubleValue] <= (double)time(NULL)) {
                [WMOAuthStore deleteToken];
                stored = nil;
            }
        }
    }

    NSString *accessToken = [stored objectForKey:@"access_token"];
    if ([accessToken isKindOfClass:[NSString class]] && [accessToken length]) {
        [self _deliverStatus:@"Authenticating with saved Discord authorization"];
        NSDictionary *reply = [self _request:@"AUTHENTICATE"
            arguments:[NSDictionary dictionaryWithObject:accessToken forKey:@"access_token"] event:nil fd:fd];
        id authEvent = [reply objectForKey:@"evt"];
        if (reply && !([authEvent isKindOfClass:[NSString class]] && [authEvent isEqualToString:@"ERROR"])) {
            NSDictionary *authData = [reply objectForKey:@"data"];
            id scopes = [authData isKindOfClass:[NSDictionary class]] ? [authData objectForKey:@"scopes"] : nil;
            if ([scopes isKindOfClass:[NSArray class]] && ![scopes containsObject:@"rpc.voice.read"]) {
                WMLog(@"Saved authorization is missing rpc.voice.read; requesting authorization again with the voice-read scope.");
                [WMOAuthStore deleteToken];
                return [self _authorizeOnFD:fd];
            }
            if (![scopes isKindOfClass:[NSArray class]])
                WMLog(@"RPC authenticated; Discord did not include a scopes array in the AUTHENTICATE response.");
            else
                WMLog([NSString stringWithFormat:@"RPC authenticated with scopes: %@", [scopes componentsJoinedByString:@", "]]);
            return YES;
        }
        [WMOAuthStore deleteToken];
        WMLog(@"Saved RPC authorization was rejected; asking Discord to authorize again.");
    }
    return [self _authorizeOnFD:fd];
}

- (BOOL)_authorizeOnFD:(int)fd
{
    if (![_clientSecret length] || ![_redirectURI length]) {
        [self _deliverStatus:@"Set WMDISCORD_CLIENT_SECRET and WMDISCORD_REDIRECT_URI"];
        WMLog(@"Set the application client secret and register a redirect URI in the Developer Portal. The URI is used for token exchange, not included in IPC AUTHORIZE.");
        return NO;
    }
    [self _deliverStatus:@"Waiting for Discord authorization approval"];
    /* Native IPC AUTHORIZE must not include redirect_uri. Register one in the
       Developer Portal; Discord selects that redirect for response_type=code.
       The same URI is supplied only when exchanging the returned code. */
    NSDictionary *arguments = [NSDictionary dictionaryWithObjectsAndKeys:
        _applicationID, @"client_id",
        @"code", @"response_type",
        [NSArray arrayWithObjects:@"rpc", @"identify", @"rpc.voice.read", nil], @"scopes", nil];
    WMLog(@"Requesting Discord RPC scopes: rpc, identify, rpc.voice.read (response_type=code; redirect URI omitted from IPC AUTHORIZE)");
    NSDictionary *reply = [self _request:@"AUTHORIZE" arguments:arguments event:nil fd:fd];
    if (!reply) {
        WMLog(@"Discord AUTHORIZE did not return a successful response. Check RPC tester approval and rpc.voice.read access.");
        return NO;
    }
    NSDictionary *data = [reply objectForKey:@"data"];
    NSString *code = [data isKindOfClass:[NSDictionary class]] ? [data objectForKey:@"code"] : nil;
    if (![code isKindOfClass:[NSString class]] || [code length] == 0) {
        WMLog([NSString stringWithFormat:@"Discord AUTHORIZE response did not contain a code (response keys: %@)",
            [[reply allKeys] componentsJoinedByString:@", "]]);
        return NO;
    }

    [self _deliverStatus:@"Exchanging Discord authorization code"];
    NSError *oauthError = nil;
    NSDictionary *token = [WMOAuthStore exchangeCode:code clientID:_applicationID
        clientSecret:_clientSecret redirectURI:_redirectURI error:&oauthError];
    if (!token) {
        [self _deliverStatus:[NSString stringWithFormat:@"OAuth exchange failed: %@",
            [oauthError localizedDescription] ? [oauthError localizedDescription] : @"unknown error"]];
        return NO;
    }
    if (![WMOAuthStore saveTokenResponse:token error:&oauthError]) {
        [self _deliverStatus:[NSString stringWithFormat:@"Could not save OAuth token: %@",
            [oauthError localizedDescription] ? [oauthError localizedDescription] : @"unknown error"]];
        return NO;
    }
    NSString *accessToken = [token objectForKey:@"access_token"];
    NSDictionary *authReply = [self _request:@"AUTHENTICATE"
        arguments:[NSDictionary dictionaryWithObject:accessToken forKey:@"access_token"] event:nil fd:fd];
    if (!authReply) {
        WMLog(@"Discord AUTHENTICATE failed after OAuth token exchange.");
        return NO;
    }
    NSDictionary *authData = [authReply objectForKey:@"data"];
    id grantedScopes = [authData isKindOfClass:[NSDictionary class]] ? [authData objectForKey:@"scopes"] : nil;
    if ([grantedScopes isKindOfClass:[NSArray class]]) {
        WMLog([NSString stringWithFormat:@"RPC authenticated with scopes: %@", [grantedScopes componentsJoinedByString:@", "]]);
        if (![grantedScopes containsObject:@"rpc.voice.read"]) {
            WMLog(@"Discord authenticated the app but did not grant rpc.voice.read. Voice roster/events will not be available.");
            [self _deliverStatus:@"Authorized, but Discord did not grant rpc.voice.read"];
            return NO;
        }
    } else {
        WMLog(@"RPC AUTHENTICATE succeeded; scopes were not present in response.");
    }
    return YES;
}

- (void)_subscribeChannel:(NSString *)channelID fd:(int)fd
{
    if (![channelID length]) return;
    NSArray *events = [NSArray arrayWithObjects:@"VOICE_STATE_CREATE", @"VOICE_STATE_UPDATE",
        @"VOICE_STATE_DELETE", @"SPEAKING_START", @"SPEAKING_STOP", nil];
    NSDictionary *arguments = [NSDictionary dictionaryWithObject:channelID forKey:@"channel_id"];
    for (NSString *name in events) {
        if (WMIsStopping(self)) return;
        (void)[self _request:@"SUBSCRIBE" arguments:arguments event:name fd:fd];
    }
}

- (void)_unsubscribeChannel:(NSString *)channelID fd:(int)fd
{
    if (![channelID length]) return;
    NSArray *events = [NSArray arrayWithObjects:@"VOICE_STATE_CREATE", @"VOICE_STATE_UPDATE",
        @"VOICE_STATE_DELETE", @"SPEAKING_START", @"SPEAKING_STOP", nil];
    NSDictionary *arguments = [NSDictionary dictionaryWithObject:channelID forKey:@"channel_id"];
    for (NSString *name in events) {
        if (WMIsStopping(self)) return;
        (void)[self _request:@"UNSUBSCRIBE" arguments:arguments event:name fd:fd];
    }
}

- (void)_refreshSelectedChannelOnFD:(int)fd
{
    NSDictionary *reply = [self _request:@"GET_SELECTED_VOICE_CHANNEL"
        arguments:[NSDictionary dictionary] event:nil fd:fd];
    if (!reply) {
        WMLog(@"Could not retrieve selected voice channel (check rpc.voice.read authorization).");
        return;
    }
    id channel = [reply objectForKey:@"data"];
    if (!channel || channel == (id)[NSNull null] || ![channel isKindOfClass:[NSDictionary class]]) {
        [self _unsubscribeChannel:_subscribedChannelID fd:fd];
        [_subscribedChannelID release]; _subscribedChannelID = nil;
        [self _deliverEvent:@"VOICE_CHANNEL_DATA"
            data:[NSDictionary dictionaryWithObject:[NSNull null] forKey:@"channel"]];
        [self _deliverStatus:@"Connected — not in a voice channel"];
        return;
    }
    NSString *newChannelID = [channel objectForKey:@"id"];
    if (![newChannelID isKindOfClass:[NSString class]]) newChannelID = @"";
    if (![_subscribedChannelID isEqualToString:newChannelID]) {
        [self _unsubscribeChannel:_subscribedChannelID fd:fd];
        [_subscribedChannelID release];
        _subscribedChannelID = [newChannelID copy];
        [self _subscribeChannel:_subscribedChannelID fd:fd];
    }
    id voiceStates = [channel objectForKey:@"voice_states"];
    NSUInteger voiceCount = [voiceStates isKindOfClass:[NSArray class]] ? [voiceStates count] : 0;
    WMLog([NSString stringWithFormat:@"Selected voice channel %@; snapshot contains %lu voice state(s)",
        newChannelID, (unsigned long)voiceCount]);
    [self _deliverEvent:@"VOICE_CHANNEL_DATA"
        data:[NSDictionary dictionaryWithObject:channel forKey:@"channel"]];
    NSString *name = [channel objectForKey:@"name"];
    [self _deliverStatus:[NSString stringWithFormat:@"Connected — %@", name ? name : @"voice channel"]];
}

- (void)_processEvent:(NSString *)event data:(NSDictionary *)data
{
    if (![event isKindOfClass:[NSString class]]) return;
    if (![data isKindOfClass:[NSDictionary class]]) data = [NSDictionary dictionary];
    [self _deliverEvent:event data:data];
    if ([event isEqualToString:@"VOICE_CHANNEL_SELECT"]) _needsChannelRefresh = YES;
}

- (void)_run
{
    while (!WMIsStopping(self)) {
        [self _deliverStatus:@"Looking for Discord IPC socket"];
        int fd = [self _connectToDiscord];
        if (fd < 0) {
            if (!WMIsStopping(self)) [self _deliverDisconnected:@"Discord IPC not found — retrying"];
            for (int i = 0; i < 8 && !WMIsStopping(self); i++) WMSleepMS(250);
            continue;
        }
        if (![self _installSocket:fd]) { close(fd); break; }

        NSDictionary *handshake = [NSDictionary dictionaryWithObjectsAndKeys:
            [NSNumber numberWithInt:1], @"v", _applicationID, @"client_id", nil];
        WMLog([NSString stringWithFormat:@"Sending RPC HANDSHAKE (version 1, application %@)", _applicationID]);
        BOOL alive = [self _sendOpcode:0 object:handshake fd:fd];
        if (!alive) WMLog(@"Could not send Discord RPC HANDSHAKE.");
        BOOL gotReady = NO;
        while (alive && !WMIsStopping(self) && !gotReady) {
            NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
            uint32_t opcode = 0;
            NSDictionary *frame = [self _readFrameFD:fd opcode:&opcode];
            if (!frame) alive = NO;
            else if (opcode == 1) {
                id event = [frame objectForKey:@"evt"];
                if ([event isKindOfClass:[NSString class]] && [event isEqualToString:@"READY"]) {
                    gotReady = YES;
                    WMLog(@"Discord RPC handshake succeeded: received READY.");
                } else if ([event isKindOfClass:[NSString class]] && [event isEqualToString:@"ERROR"]) {
                    NSDictionary *errorData = [frame objectForKey:@"data"];
                    WMLog([NSString stringWithFormat:@"Discord RPC handshake error: code=%@ message=%@",
                        [errorData objectForKey:@"code"] ? [errorData objectForKey:@"code"] : @"unknown",
                        [errorData objectForKey:@"message"] ? [errorData objectForKey:@"message"] : @"unknown"]);
                } else {
                    WMLog([NSString stringWithFormat:@"RPC handshake received frame (evt=%@, cmd=%@)",
                        event ? event : @"none", [frame objectForKey:@"cmd"] ? [frame objectForKey:@"cmd"] : @"none"]);
                }
            } else {
                WMLog([NSString stringWithFormat:@"RPC handshake received unexpected opcode %u", opcode]);
            }
            [pool drain];
        }

        if (!gotReady && !WMIsStopping(self))
            WMLog(@"Discord IPC closed or failed before sending READY; reconnecting.");

        if (alive && gotReady && !WMIsStopping(self)) {
            [self _deliverStatus:@"Discord IPC ready — authenticating"];
            if ([self _authenticateOnFD:fd] && !WMIsStopping(self)) {
                [self _deliverConnected];
                (void)[self _request:@"SUBSCRIBE" arguments:[NSDictionary dictionary]
                    event:@"VOICE_CHANNEL_SELECT" fd:fd];
                (void)[self _request:@"SUBSCRIBE" arguments:[NSDictionary dictionary]
                    event:@"VOICE_SETTINGS_UPDATE" fd:fd];
                (void)[self _request:@"SUBSCRIBE" arguments:[NSDictionary dictionary]
                    event:@"VOICE_CONNECTION_STATUS" fd:fd];
                [self _refreshSelectedChannelOnFD:fd];
                while (alive && !WMIsStopping(self)) {
                    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
                    uint32_t opcode = 0;
                    NSDictionary *frame = [self _readFrameFD:fd opcode:&opcode];
                    if (!frame) alive = NO;
                    else if (opcode == 1) {
                        NSString *event = [frame objectForKey:@"evt"];
                        NSDictionary *data = [frame objectForKey:@"data"];
                        if ([event isKindOfClass:[NSString class]] &&
                            ![event isEqualToString:@"ERROR"] && [data isKindOfClass:[NSDictionary class]])
                            [self _processEvent:event data:data];
                    }
                    [pool drain];
                    if (_needsChannelRefresh && alive && !WMIsStopping(self)) {
                        _needsChannelRefresh = NO;
                        [self _refreshSelectedChannelOnFD:fd];
                    }
                }
            } else {
                WMLog(@"RPC authentication/authorization did not complete; closing this session before retrying.");
                alive = NO;
            }
        }

        if (alive && !WMIsStopping(self)) [self _unsubscribeChannel:_subscribedChannelID fd:fd];
        [_subscribedChannelID release]; _subscribedChannelID = nil;
        pthread_mutex_lock(&_mutex);
        if (_socketFD == fd) _socketFD = -1;
        pthread_mutex_unlock(&_mutex);
        close(fd);
        if (!WMIsStopping(self)) {
            [self _deliverDisconnected:@"Discord IPC disconnected — reconnecting"];
            for (int i = 0; i < 8 && !WMIsStopping(self); i++) WMSleepMS(250);
        }
    }
}
@end

static BOOL WMIsStopping(WMRPCClient *client)
{
    return [client isStopping];
}

static void *WMWorkerEntry(void *opaque)
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    WMRPCClient *client = (WMRPCClient *)opaque;
    [client _run];
    [pool drain];
    return NULL;
}
