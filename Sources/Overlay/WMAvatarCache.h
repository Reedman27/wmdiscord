// SPDX-License-Identifier: GPL-2.0-only
#ifndef WM_AVATAR_CACHE_H
#define WM_AVATAR_CACHE_H

#import <AppKit/AppKit.h>
#include <pthread.h>

@protocol WMAvatarCacheDelegate <NSObject>
- (void)avatarCacheDidLoadAvatarForKey:(NSString *)key;
@end

/* Small asynchronous Discord CDN cache. All NSImage creation and drawing stays
   on the AppKit thread; the worker only downloads bytes and writes cache files. */
@interface WMAvatarCache : NSObject
{
@private
    id<WMAvatarCacheDelegate> _delegate; /* assign */
    NSMutableDictionary *_images;
    NSMutableArray *_jobs;
    NSMutableSet *_pendingKeys;
    NSString *_cacheDirectory;
    pthread_t _worker;
    pthread_mutex_t _mutex;
    pthread_cond_t _condition;
    BOOL _started;
    BOOL _stopping;
}
- (id)initWithDelegate:(id<WMAvatarCacheDelegate>)delegate;
- (NSImage *)imageForUserID:(NSString *)userID avatarHash:(NSString *)avatarHash;
- (void)stop;
@end

#endif
