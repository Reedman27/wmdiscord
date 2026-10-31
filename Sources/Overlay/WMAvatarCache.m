// SPDX-License-Identifier: GPL-2.0-only
#import "WMAvatarCache.h"
#import "../Utilities/WMCurlRuntime.h"
#include <curl/curl.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>
#include <string.h>
#include <stdio.h>
#include <stdlib.h>

#define WM_AVATAR_MAX_BYTES (2U * 1024U * 1024U)

typedef struct {
    unsigned char *bytes;
    size_t length;
    size_t capacity;
    BOOL overflow;
} WMAvatarBuffer;

static size_t WMAvatarWriteCallback(char *ptr, size_t size, size_t count, void *userdata)
{
    WMAvatarBuffer *buffer = (WMAvatarBuffer *)userdata;
    size_t incoming = size * count;
    if (!buffer || incoming > WM_AVATAR_MAX_BYTES - buffer->length) {
        if (buffer) buffer->overflow = YES;
        return 0;
    }
    size_t required = buffer->length + incoming;
    if (required > buffer->capacity) {
        size_t capacity = buffer->capacity ? buffer->capacity : 16384;
        while (capacity < required) capacity *= 2;
        unsigned char *next = (unsigned char *)realloc(buffer->bytes, capacity);
        if (!next) return 0;
        buffer->bytes = next;
        buffer->capacity = capacity;
    }
    memcpy(buffer->bytes + buffer->length, ptr, incoming);
    buffer->length += incoming;
    return incoming;
}

static BOOL WMAvatarSafeComponent(NSString *value)
{
    if (![value isKindOfClass:[NSString class]] || [value length] == 0 || [value length] > 128) return NO;
    NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:
        @"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-"];
    return [value rangeOfCharacterFromSet:[allowed invertedSet]].location == NSNotFound;
}

static BOOL WMWriteAvatarFile(const char *path, const unsigned char *bytes, size_t length)
{
    size_t pathLength = strlen(path);
    char *temporary = (char *)malloc(pathLength + 16);
    if (!temporary) return NO;
    snprintf(temporary, pathLength + 16, "%s.tmp.XXXXXX", path);
    int fd = mkstemp(temporary);
    if (fd < 0) { free(temporary); return NO; }
    (void)fchmod(fd, S_IRUSR | S_IWUSR);
    size_t offset = 0;
    BOOL ok = YES;
    while (offset < length) {
        ssize_t wrote = write(fd, bytes + offset, length - offset);
        if (wrote < 0 && errno == EINTR) continue;
        if (wrote <= 0) { ok = NO; break; }
        offset += (size_t)wrote;
    }
    if (ok && fsync(fd) != 0) ok = NO;
    close(fd);
    if (ok && rename(temporary, path) != 0) ok = NO;
    if (!ok) unlink(temporary);
    free(temporary);
    return ok;
}

@interface WMAvatarCache (Private)
- (void)_workerMain;
- (BOOL)isStopping;
- (void)_avatarFinished:(NSString *)key;
- (NSString *)_pathForKey:(NSString *)key userID:(NSString *)userID avatarHash:(NSString *)hash;
@end

static void *WMAvatarWorkerEntry(void *context)
{
    WMAvatarCache *cache = (WMAvatarCache *)context;
    [cache _workerMain];
    return NULL;
}

@implementation WMAvatarCache
- (id)initWithDelegate:(id<WMAvatarCacheDelegate>)delegate
{
    self = [super init];
    if (self) {
        _delegate = delegate;
        _images = [[NSMutableDictionary alloc] init];
        _jobs = [[NSMutableArray alloc] init];
        _pendingKeys = [[NSMutableSet alloc] init];
        _cacheDirectory = [[NSHomeDirectory() stringByAppendingPathComponent:@".cache/wmdiscord/avatars"] copy];
        (void)[[NSFileManager defaultManager] createDirectoryAtPath:_cacheDirectory
            withIntermediateDirectories:YES attributes:nil error:NULL];
        pthread_mutex_init(&_mutex, NULL);
        pthread_cond_init(&_condition, NULL);
        if (pthread_create(&_worker, NULL, WMAvatarWorkerEntry, self) == 0) _started = YES;
    }
    return self;
}

- (void)dealloc
{
    [self stop];
    [_images release]; [_jobs release]; [_pendingKeys release]; [_cacheDirectory release];
    pthread_cond_destroy(&_condition);
    pthread_mutex_destroy(&_mutex);
    [super dealloc];
}

- (NSString *)_pathForKey:(NSString *)key userID:(NSString *)userID avatarHash:(NSString *)hash
{
    (void)key;
    NSString *extension = [hash hasPrefix:@"a_"] ? @"gif" : @"png";
    NSString *filename = [NSString stringWithFormat:@"%@-%@.%@", userID, hash, extension];
    return [_cacheDirectory stringByAppendingPathComponent:filename];
}

- (NSImage *)imageForUserID:(NSString *)userID avatarHash:(NSString *)avatarHash
{
    if (!WMAvatarSafeComponent(userID) || !WMAvatarSafeComponent(avatarHash)) return nil;
    NSString *key = [NSString stringWithFormat:@"%@|%@", userID, avatarHash];
    NSImage *cached = [_images objectForKey:key];
    if (cached) return cached;

    NSString *path = [self _pathForKey:key userID:userID avatarHash:avatarHash];
    if ([[NSFileManager defaultManager] fileExistsAtPath:path]) {
        NSImage *image = [[[NSImage alloc] initWithContentsOfFile:path] autorelease];
        if (image) { [_images setObject:image forKey:key]; return image; }
    }

    pthread_mutex_lock(&_mutex);
    if (!_stopping && ![_pendingKeys containsObject:key]) {
        NSDictionary *job = [NSDictionary dictionaryWithObjectsAndKeys:
            userID, @"user_id", avatarHash, @"avatar", key, @"key", path, @"path", nil];
        [_pendingKeys addObject:key];
        [_jobs addObject:job];
        pthread_cond_signal(&_condition);
    }
    pthread_mutex_unlock(&_mutex);
    return nil;
}

- (void)_workerMain
{
    NSAutoreleasePool *outerPool = [[NSAutoreleasePool alloc] init];
    WMInitializeCurlRuntime();
    for (;;) {
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        pthread_mutex_lock(&_mutex);
        while ([_jobs count] == 0 && !_stopping) pthread_cond_wait(&_condition, &_mutex);
        if (_stopping) {
            pthread_mutex_unlock(&_mutex);
            [pool drain];
            break;
        }
        NSDictionary *job = [[_jobs objectAtIndex:0] retain];
        [_jobs removeObjectAtIndex:0];
        pthread_mutex_unlock(&_mutex);

        NSString *userID = [job objectForKey:@"user_id"];
        NSString *hash = [job objectForKey:@"avatar"];
        NSString *key = [job objectForKey:@"key"];
        NSString *path = [job objectForKey:@"path"];
        NSString *extension = [hash hasPrefix:@"a_"] ? @"gif" : @"png";
        NSString *url = nil;
        if ([hash hasPrefix:@"default_"]) {
            NSString *index = [hash substringFromIndex:8];
            url = [NSString stringWithFormat:@"https://cdn.discordapp.com/embed/avatars/%@.png?size=64", index];
        } else {
            url = [NSString stringWithFormat:
                @"https://cdn.discordapp.com/avatars/%@/%@.%@?size=64", userID, hash, extension];
        }

        CURL *curl = curl_easy_init();
        WMAvatarBuffer buffer;
        memset(&buffer, 0, sizeof(buffer));
        BOOL success = NO;
        if (curl) {
            curl_easy_setopt(curl, CURLOPT_URL, [url UTF8String]);
            curl_easy_setopt(curl, CURLOPT_FOLLOWLOCATION, 0L);
            curl_easy_setopt(curl, CURLOPT_CONNECTTIMEOUT, 8L);
            curl_easy_setopt(curl, CURLOPT_TIMEOUT, 15L);
            curl_easy_setopt(curl, CURLOPT_USERAGENT, "WMDiscord/0.3.2 (GNUstep; X11)");
            curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, WMAvatarWriteCallback);
            curl_easy_setopt(curl, CURLOPT_WRITEDATA, &buffer);
            CURLcode result = curl_easy_perform(curl);
            long response = 0;
            char *contentType = NULL;
            curl_easy_getinfo(curl, CURLINFO_RESPONSE_CODE, &response);
            curl_easy_getinfo(curl, CURLINFO_CONTENT_TYPE, &contentType);
            if (result == CURLE_OK && response == 200 && contentType &&
                strncmp(contentType, "image/", 6) == 0 && !buffer.overflow && buffer.length > 0)
                success = WMWriteAvatarFile([path fileSystemRepresentation], buffer.bytes, buffer.length);
            curl_easy_cleanup(curl);
        }
        free(buffer.bytes);
        pthread_mutex_lock(&_mutex);
        [_pendingKeys removeObject:key];
        pthread_mutex_unlock(&_mutex);
        if (success && ![self isStopping])
            [self performSelectorOnMainThread:@selector(_avatarFinished:) withObject:key waitUntilDone:NO];
        [job release];
        [pool drain];
    }
    [outerPool drain];
}

- (BOOL)isStopping
{
    pthread_mutex_lock(&_mutex);
    BOOL stopping = _stopping;
    pthread_mutex_unlock(&_mutex);
    return stopping;
}

- (void)_avatarFinished:(NSString *)key
{
    if ([self isStopping]) return;
    NSArray *parts = [key componentsSeparatedByString:@"|"];
    if ([parts count] != 2) return;
    NSString *path = [self _pathForKey:key userID:[parts objectAtIndex:0] avatarHash:[parts objectAtIndex:1]];
    NSImage *image = [[[NSImage alloc] initWithContentsOfFile:path] autorelease];
    if (image) [_images setObject:image forKey:key];
    if ([_delegate respondsToSelector:@selector(avatarCacheDidLoadAvatarForKey:)])
        [_delegate avatarCacheDidLoadAvatarForKey:key];
}

- (void)stop
{
    if (!_started) return;
    pthread_mutex_lock(&_mutex);
    _stopping = YES;
    pthread_cond_broadcast(&_condition);
    pthread_mutex_unlock(&_mutex);
    pthread_join(_worker, NULL);
    _started = NO;
    _delegate = nil;
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
}
@end
