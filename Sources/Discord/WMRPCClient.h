// SPDX-License-Identifier: GPL-2.0-only
#ifndef WM_RPC_CLIENT_H
#define WM_RPC_CLIENT_H

#import <Foundation/Foundation.h>
#include <pthread.h>

@protocol WMRPCClientDelegate <NSObject>
- (void)rpcClientDidChangeStatus:(NSString *)status;
- (void)rpcClientDidConnect;
- (void)rpcClientDidDisconnectWithReason:(NSString *)reason;
- (void)rpcClientDeliverEvent:(NSDictionary *)envelope;
@end

/* Discord's documented local Unix-socket RPC transport. All socket work runs
   on one joinable POSIX worker; AppKit callbacks are marshalled to the main thread. */
@interface WMRPCClient : NSObject
{
@private
    id<WMRPCClientDelegate> _delegate; /* assign; AppDelegate owns the client */
    NSString *_applicationID;
    NSString *_clientSecret;
    NSString *_redirectURI;
    NSString *_subscribedChannelID;
    pthread_t _worker;
    pthread_mutex_t _mutex;
    int _socketFD;
    BOOL _started;
    BOOL _stopping;
    BOOL _needsChannelRefresh;
}
- (id)initWithApplicationID:(NSString *)applicationID
               clientSecret:(NSString *)clientSecret
                redirectURI:(NSString *)redirectURI
                   delegate:(id<WMRPCClientDelegate>)delegate;
- (BOOL)start;
- (void)stop;
- (BOOL)isStopping;
@end

#endif
