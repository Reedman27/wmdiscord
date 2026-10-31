// SPDX-License-Identifier: GPL-2.0-only
#import "WMX11Hints.h"
#import <X11/Xlib.h>
#import <X11/Xatom.h>
#import <X11/keysym.h>
#import <X11/extensions/shape.h>
#include <pthread.h>
#include <poll.h>
#include <unistd.h>
#include <string.h>

static Window WMFindWindowByTitle(Display *display, Window parent, const char *wanted, unsigned int depth)
{
    if (depth > 7) return None;
    Window rootReturn = None, parentReturn = None, *children = NULL;
    unsigned int childCount = 0;
    if (!XQueryTree(display, parent, &rootReturn, &parentReturn, &children, &childCount)) return None;
    Window found = None;
    for (unsigned int index = 0; index < childCount && found == None; index++) {
        char *name = NULL;
        if (XFetchName(display, children[index], &name) && name) {
            if (strcmp(name, wanted) == 0) found = children[index];
            XFree(name);
        }
        if (found == None) found = WMFindWindowByTitle(display, children[index], wanted, depth + 1);
    }
    if (children) XFree(children);
    return found;
}

static Window WMResolveWindow(Display *display, NSString *title)
{
    if (!display || ![title isKindOfClass:[NSString class]] || [title length] == 0) return None;
    return WMFindWindowByTitle(display, DefaultRootWindow(display), [title UTF8String], 0);
}

static void WMRequestState(Display *display, Window root, Window target, Atom first, Atom second)
{
    XEvent event;
    memset(&event, 0, sizeof(event));
    event.xclient.type = ClientMessage;
    event.xclient.window = target;
    event.xclient.message_type = XInternAtom(display, "_NET_WM_STATE", False);
    event.xclient.format = 32;
    event.xclient.data.l[0] = 1; /* _NET_WM_STATE_ADD */
    event.xclient.data.l[1] = (long)first;
    event.xclient.data.l[2] = (long)second;
    event.xclient.data.l[3] = 1; /* normal application */
    XSendEvent(display, root, False, SubstructureRedirectMask | SubstructureNotifyMask, &event);
}

void WMApplyX11OverlayHints(NSWindow *window, NSString *windowTitle)
{
    (void)window;
    Display *display = XOpenDisplay(NULL);
    if (!display) return;
    Window root = DefaultRootWindow(display);
    Window target = WMResolveWindow(display, windowTitle);
    if (target != None) {
        /* This is a managed utility window, not a panel/dock.  Marking it as
           _DOCK can make some window managers bypass normal client handling,
           which breaks movement/workspaces and can leave the overlay unseen. */
        Atom type = XInternAtom(display, "_NET_WM_WINDOW_TYPE", False);
        Atom utility = XInternAtom(display, "_NET_WM_WINDOW_TYPE_UTILITY", False);
        XChangeProperty(display, target, type, XA_ATOM, 32, PropModeReplace, (unsigned char *)&utility, 1);

        Atom above = XInternAtom(display, "_NET_WM_STATE_ABOVE", False);
        Atom sticky = XInternAtom(display, "_NET_WM_STATE_STICKY", False);
        Atom skipTaskbar = XInternAtom(display, "_NET_WM_STATE_SKIP_TASKBAR", False);
        Atom skipPager = XInternAtom(display, "_NET_WM_STATE_SKIP_PAGER", False);
        WMRequestState(display, root, target, above, sticky);
        WMRequestState(display, root, target, skipTaskbar, skipPager);

        /* Request that a compositor keep compositing this utility window.
           A fullscreen game may otherwise ask the compositor to bypass itself. */
        Atom bypass = XInternAtom(display, "_NET_WM_BYPASS_COMPOSITOR", False);
        unsigned long value = 2;
        XChangeProperty(display, target, bypass, XA_CARDINAL, 32, PropModeReplace,
            (unsigned char *)&value, 1);
        XFlush(display);
    } else {
        NSLog(@"[WMDiscord] X11 could not find the WMDiscord window by title; keeping GNUstep window defaults.");
    }
    XCloseDisplay(display);
}

BOOL WMSetX11ClickThrough(NSString *windowTitle, BOOL enabled)
{
    Display *display = XOpenDisplay(NULL);
    if (!display) return NO;
    Window target = WMResolveWindow(display, windowTitle);
    BOOL success = NO;
    if (target != None) {
        int eventBase = 0, errorBase = 0, major = 0, minor = 0;
        if (XShapeQueryExtension(display, &eventBase, &errorBase) &&
            XShapeQueryVersion(display, &major, &minor) && (major > 1 || (major == 1 && minor >= 1))) {
            if (enabled) {
                /* Empty ShapeInput region: all pointer events go to the game below. */
                XShapeCombineRectangles(display, target, ShapeInput, 0, 0, NULL, 0, ShapeSet, Unsorted);
            } else {
                /* None restores the default rectangular input region. */
                XShapeCombineMask(display, target, ShapeInput, 0, 0, None, ShapeSet);
            }
            XFlush(display);
            success = YES;
        }
    }
    XCloseDisplay(display);
    return success;
}

static pthread_t gHotkeyThread;
static pthread_mutex_t gHotkeyMutex = PTHREAD_MUTEX_INITIALIZER;
static BOOL gHotkeyRunning = NO;
static BOOL gHotkeyStop = NO;
static WMX11HotkeyCallback gHotkeyCallback = NULL;
static void *gHotkeyContext = NULL;

static BOOL WMHotkeyShouldStop(void)
{
    pthread_mutex_lock(&gHotkeyMutex);
    BOOL stop = gHotkeyStop;
    pthread_mutex_unlock(&gHotkeyMutex);
    return stop;
}

static void *WMHotkeyThreadMain(void *unused)
{
    (void)unused;
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    Display *display = XOpenDisplay(NULL);
    if (!display) { [pool drain]; return NULL; }
    Window root = DefaultRootWindow(display);
    KeyCode keycode = XKeysymToKeycode(display, XK_o);
    XSelectInput(display, root, KeyPressMask);
    unsigned int modifiers = ControlMask | Mod1Mask;
    XGrabKey(display, keycode, modifiers, root, False, GrabModeAsync, GrabModeAsync);
    XGrabKey(display, keycode, modifiers | LockMask, root, False, GrabModeAsync, GrabModeAsync);
    XGrabKey(display, keycode, modifiers | Mod2Mask, root, False, GrabModeAsync, GrabModeAsync);
    XGrabKey(display, keycode, modifiers | LockMask | Mod2Mask, root, False, GrabModeAsync, GrabModeAsync);
    XSync(display, False);
    int fd = ConnectionNumber(display);
    while (!WMHotkeyShouldStop()) {
        struct pollfd pfd;
        pfd.fd = fd; pfd.events = POLLIN; pfd.revents = 0;
        int result = poll(&pfd, 1, 250);
        if (result <= 0 || !(pfd.revents & POLLIN)) continue;
        while (XPending(display)) {
            XEvent event;
            XNextEvent(display, &event);
            if (event.type == KeyPress && event.xkey.keycode == keycode &&
                (event.xkey.state & (ControlMask | Mod1Mask)) == modifiers) {
                pthread_mutex_lock(&gHotkeyMutex);
                WMX11HotkeyCallback callback = gHotkeyCallback;
                void *context = gHotkeyContext;
                pthread_mutex_unlock(&gHotkeyMutex);
                if (callback) callback(context);
            }
        }
    }
    XUngrabKey(display, AnyKey, AnyModifier, root);
    XCloseDisplay(display);
    [pool drain];
    return NULL;
}

BOOL WMStartX11HotkeyMonitor(WMX11HotkeyCallback callback, void *context)
{
    pthread_mutex_lock(&gHotkeyMutex);
    if (gHotkeyRunning) { pthread_mutex_unlock(&gHotkeyMutex); return YES; }
    gHotkeyCallback = callback;
    gHotkeyContext = context;
    gHotkeyStop = NO;
    if (pthread_create(&gHotkeyThread, NULL, WMHotkeyThreadMain, NULL) != 0) {
        pthread_mutex_unlock(&gHotkeyMutex);
        return NO;
    }
    gHotkeyRunning = YES;
    pthread_mutex_unlock(&gHotkeyMutex);
    return YES;
}

void WMStopX11HotkeyMonitor(void)
{
    pthread_mutex_lock(&gHotkeyMutex);
    BOOL running = gHotkeyRunning;
    gHotkeyStop = YES;
    pthread_mutex_unlock(&gHotkeyMutex);
    if (running) pthread_join(gHotkeyThread, NULL);
    pthread_mutex_lock(&gHotkeyMutex);
    gHotkeyRunning = NO;
    gHotkeyCallback = NULL;
    gHotkeyContext = NULL;
    pthread_mutex_unlock(&gHotkeyMutex);
}
