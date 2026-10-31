// SPDX-License-Identifier: GPL-2.0-only
#ifndef WM_OAUTH_STORE_H
#define WM_OAUTH_STORE_H

#import <Foundation/Foundation.h>

/* Stores only OAuth tokens, never the Discord application client secret. */
@interface WMOAuthStore : NSObject
+ (NSDictionary *)loadToken;
+ (NSDictionary *)exchangeCode:(NSString *)code
                      clientID:(NSString *)clientID
                  clientSecret:(NSString *)clientSecret
                   redirectURI:(NSString *)redirectURI
                         error:(NSError **)error;
+ (NSDictionary *)refreshToken:(NSString *)refreshToken
                      clientID:(NSString *)clientID
                  clientSecret:(NSString *)clientSecret
                         error:(NSError **)error;
+ (BOOL)saveTokenResponse:(NSDictionary *)response error:(NSError **)error;
+ (void)deleteToken;
+ (NSString *)tokenPath;
@end

#endif
