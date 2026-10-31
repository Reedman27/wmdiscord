// SPDX-License-Identifier: GPL-2.0-only
#import "WMCurlRuntime.h"
#import <curl/curl.h>
#include <pthread.h>

static pthread_once_t gWMCurlOnce = PTHREAD_ONCE_INIT;
static void WMDoCurlGlobalInit(void)
{
    (void)curl_global_init(CURL_GLOBAL_DEFAULT);
}

void WMInitializeCurlRuntime(void)
{
    (void)pthread_once(&gWMCurlOnce, WMDoCurlGlobalInit);
}
