// SPDX-License-Identifier: GPL-2.0-only
#ifndef WM_CURL_RUNTIME_H
#define WM_CURL_RUNTIME_H

/* Shared one-time libcurl process initialization. Call before using any CURL
   easy handle; deliberately never call curl_global_cleanup during app lifetime. */
void WMInitializeCurlRuntime(void);

#endif
