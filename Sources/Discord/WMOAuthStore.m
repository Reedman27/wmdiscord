// SPDX-License-Identifier: GPL-2.0-only
#import "WMOAuthStore.h"
#import "../Utilities/WMCurlRuntime.h"
#import <curl/curl.h>
#include <sys/stat.h>
#include <errno.h>
#include <string.h>
#include <stdlib.h>
#include <time.h>
#include <pthread.h>

static size_t WMCurlWrite(char *bytes, size_t size, size_t count, void *context)
{
    size_t length = size * count;
    NSMutableData *data = (NSMutableData *)context;
    [data appendBytes:bytes length:length];
    return length;
}

static NSString *WMFormEscape(CURL *curl, NSString *value)
{
    const char *utf8 = [value UTF8String];
    char *escaped = curl_easy_escape(curl, utf8 ? utf8 : "", 0);
    if (!escaped) return @"";
    NSString *result = [NSString stringWithUTF8String:escaped];
    curl_free(escaped);
    return result;
}

static NSString *WMFormBody(CURL *curl, NSDictionary *fields)
{
    NSMutableArray *parts = [NSMutableArray array];
    for (NSString *key in fields) {
        id raw = [fields objectForKey:key];
        NSString *value = [raw isKindOfClass:[NSString class]] ? raw : [raw description];
        [parts addObject:[NSString stringWithFormat:@"%@=%@", WMFormEscape(curl, key), WMFormEscape(curl, value)]];
    }
    return [parts componentsJoinedByString:@"&"];
}

@implementation WMOAuthStore

+ (NSString *)tokenPath
{
    const char *xdg = getenv("XDG_CONFIG_HOME");
    NSString *base = (xdg && xdg[0]) ? [NSString stringWithUTF8String:xdg] :
        [NSHomeDirectory() stringByAppendingPathComponent:@".config"];
    return [[base stringByAppendingPathComponent:@"wmdiscord"] stringByAppendingPathComponent:@"token.json"];
}

+ (NSDictionary *)loadToken
{
    NSString *path = [self tokenPath];
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (!data) return nil;
    (void)chmod([path fileSystemRepresentation], 0600);
    id value = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
    return [value isKindOfClass:[NSDictionary class]] ? value : nil;
}

+ (NSDictionary *)_postFields:(NSDictionary *)fields error:(NSError **)error
{
    WMInitializeCurlRuntime();
    CURL *curl = curl_easy_init();
    if (!curl) {
        if (error) *error = [NSError errorWithDomain:@"WMOAuthStore" code:1
            userInfo:[NSDictionary dictionaryWithObject:@"Could not initialize libcurl" forKey:NSLocalizedDescriptionKey]];
        return nil;
    }
    NSString *body = WMFormBody(curl, fields);
    NSMutableData *response = [NSMutableData data];
    char curlError[CURL_ERROR_SIZE];
    memset(curlError, 0, sizeof(curlError));
    curl_easy_setopt(curl, CURLOPT_URL, "https://discord.com/api/oauth2/token");
    curl_easy_setopt(curl, CURLOPT_POST, 1L);
    curl_easy_setopt(curl, CURLOPT_POSTFIELDS, [body UTF8String]);
    curl_easy_setopt(curl, CURLOPT_POSTFIELDSIZE, (long)strlen([body UTF8String]));
    curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, WMCurlWrite);
    curl_easy_setopt(curl, CURLOPT_WRITEDATA, response);
    curl_easy_setopt(curl, CURLOPT_ERRORBUFFER, curlError);
    curl_easy_setopt(curl, CURLOPT_CONNECTTIMEOUT, 15L);
    curl_easy_setopt(curl, CURLOPT_TIMEOUT, 30L);
    curl_easy_setopt(curl, CURLOPT_SSL_VERIFYPEER, 1L);
    curl_easy_setopt(curl, CURLOPT_SSL_VERIFYHOST, 2L);
    curl_easy_setopt(curl, CURLOPT_USERAGENT, "WMDiscord/0.3.2 GNUstep");
    struct curl_slist *headers = NULL;
    headers = curl_slist_append(headers, "Content-Type: application/x-www-form-urlencoded");
    curl_easy_setopt(curl, CURLOPT_HTTPHEADER, headers);

    CURLcode result = curl_easy_perform(curl);
    long status = 0;
    curl_easy_getinfo(curl, CURLINFO_RESPONSE_CODE, &status);
    curl_slist_free_all(headers);
    curl_easy_cleanup(curl);

    if (result != CURLE_OK || status < 200 || status >= 300) {
        NSString *description = (result != CURLE_OK) ?
            [NSString stringWithUTF8String:(curlError[0] ? curlError : curl_easy_strerror(result))] :
            [NSString stringWithFormat:@"Discord OAuth endpoint returned HTTP %ld", status];
        if (error) *error = [NSError errorWithDomain:@"WMOAuthStore" code:(NSInteger)status
            userInfo:[NSDictionary dictionaryWithObject:description forKey:NSLocalizedDescriptionKey]];
        return nil;
    }
    id parsed = [NSJSONSerialization JSONObjectWithData:response options:0 error:error];
    if (![parsed isKindOfClass:[NSDictionary class]]) return nil;
    return parsed;
}

+ (NSDictionary *)exchangeCode:(NSString *)code clientID:(NSString *)clientID
                  clientSecret:(NSString *)clientSecret redirectURI:(NSString *)redirectURI
                         error:(NSError **)error
{
    if (![code length] || ![clientID length] || ![clientSecret length] || ![redirectURI length]) return nil;
    /* The redirect is deliberately used here, not in the native IPC AUTHORIZE frame. */
    NSDictionary *fields = [NSDictionary dictionaryWithObjectsAndKeys:
        clientID, @"client_id", clientSecret, @"client_secret",
        @"authorization_code", @"grant_type", code, @"code", redirectURI, @"redirect_uri", nil];
    return [self _postFields:fields error:error];
}

+ (NSDictionary *)refreshToken:(NSString *)refreshToken clientID:(NSString *)clientID
                  clientSecret:(NSString *)clientSecret error:(NSError **)error
{
    if (![refreshToken length] || ![clientID length] || ![clientSecret length]) return nil;
    NSDictionary *fields = [NSDictionary dictionaryWithObjectsAndKeys:
        clientID, @"client_id", clientSecret, @"client_secret",
        @"refresh_token", @"grant_type", refreshToken, @"refresh_token", nil];
    return [self _postFields:fields error:error];
}

+ (BOOL)saveTokenResponse:(NSDictionary *)response error:(NSError **)error
{
    NSString *access = [response objectForKey:@"access_token"];
    if (![access isKindOfClass:[NSString class]] || [access length] == 0) return NO;
    NSMutableDictionary *saved = [NSMutableDictionary dictionaryWithDictionary:response];
    id expires = [response objectForKey:@"expires_in"];
    if ([expires respondsToSelector:@selector(doubleValue)])
        [saved setObject:[NSNumber numberWithDouble:time(NULL) + [expires doubleValue]] forKey:@"expires_at"];
    NSString *path = [self tokenPath];
    NSString *directory = [path stringByDeletingLastPathComponent];
    NSDictionary *attributes = [NSDictionary dictionaryWithObject:[NSNumber numberWithUnsignedShort:0700]
        forKey:NSFilePosixPermissions];
    if (![[NSFileManager defaultManager] createDirectoryAtPath:directory
        withIntermediateDirectories:YES attributes:attributes error:error]) return NO;
    NSData *data = [NSJSONSerialization dataWithJSONObject:saved options:NSJSONWritingPrettyPrinted error:error];
    if (!data || ![data writeToFile:path options:NSDataWritingAtomic error:error]) return NO;
    if (chmod([path fileSystemRepresentation], 0600) != 0) {
        if (error) *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:nil];
        return NO;
    }
    (void)chmod([directory fileSystemRepresentation], 0700);
    return YES;
}

+ (void)deleteToken
{
    [[NSFileManager defaultManager] removeItemAtPath:[self tokenPath] error:NULL];
}
@end
