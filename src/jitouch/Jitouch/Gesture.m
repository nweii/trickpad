//
//  Gesture.m
//  Jitouch
//
//  Copyright 2021 Supasorn Suwajanakorn and Sukolsak Sakshuwong. All rights reserved.
//  Modified work Copyright 2021 Aaron Kollasch. All rights reserved.
//  Modified work Copyright 2026 Nathan Cheng. All rights reserved.
//

#import "Gesture.h"
#import <math.h>
#import <CoreFoundation/CoreFoundation.h>
#import <ApplicationServices/ApplicationServices.h>
#import <AudioToolbox/AudioServices.h>
#import <AVFAudio/AVFAudio.h>
#import <Foundation/Foundation.h>

#import "Settings.h"
#import "JitouchAppDelegate.h"
#import "CursorWindow.h"
#import "CursorView.h"
#import "GestureWindow.h"
#import "SizeHistory.h"
#import "KeyUtility.h"
#import "ApplicationScopeCache.h"
#import "Config.h"
#import "ContactTapRecognizer.h"
#import "DeferredGestureDispatcher.h"
#import "GestureSequence.h"
#import "MouseClickInteraction.h"
#import "MouseContactFilter.h"
#import "MultitouchDeviceLifecycle.h"
#import "ContactOnsetTracker.h"
#import "ScriptRunner.h"
#import "SequenceDispatcher.h"
#import "TraceRecorder.h"
#import "TrackpadInteraction.h"

#define TRACKPAD 0
#define MAGICMOUSE 1
#define CHARRECOGNITION 2
static const NSString* deviceTypeName[] = {@"trackpad", @"magicmouse", @"charrec"};

#define px normalized.pos.x
#define py normalized.pos.y
#define HS(a)  ((a * 7907 + 7883) % 4493)
#define CFSafeRelease(a) if (a)CFRelease(a);

#define MIDDLEBUTTONDOWN 1
#define LEFTBUTTONDOWN 2
#define RIGHTBUTTONDOWN 3
#define COMMANDANDLEFTBUTTONDOWN 4
//#define COMMANDDOWN 5
#define IGNOREMOUSE 6
#define IGNOREKEY 7

#define PI 3.1415926535897932384626433832795028841971

// to suppress "'CGPostKeyboardEvent' is deprecated" warnings
#pragma GCC diagnostic ignored "-Wdeprecated-declarations"

#ifndef DEBUG
#define DEBUG FALSE
#endif

@implementation Gesture

// Based on the code at http://steike.com/code/multitouch
typedef struct { float x, y; } MTPoint;
typedef struct { MTPoint pos, vel; } MTReadout;

enum {
    MTTouchStateNotTracking = 0,
    MTTouchStateStartInRange = 1,
    MTTouchStateHoverInRange = 2,
    MTTouchStateMakeTouch = 3,
    MTTouchStateTouching = 4,
    MTTouchStateBreakTouch = 5,
    MTTouchStateLingerInRange = 6,
    MTTouchStateOutOfRange = 7
};

typedef uint32_t MTTouchState;

struct MGMultitouchContact {
    int frame;
    double timestamp;
    int identifier;
    MTTouchState state;
    int fingerId, handId;
    MTReadout normalized;
    float size;
    int zero1;
    float angle, majorAxis, minorAxis; // ellipsoid
    MTReadout mm;
    int zero2[2];
    float zDensity;
};
typedef MGMultitouchContact Finger;

// The Dock's private notification entry point. It takes a second argument on
// current macOS, and a call missing it is silently ignored, so Mission Control
// and its kin do nothing. scripts/debug/dock-notification-probe.m re-tests this
// when a macOS release moves the private interface again.
void CoreDockSendNotification(NSString *notificationName, int unused);

static AXUIElementRef systemWideElement = NULL;


static CFMachPortRef eventTap;
static BOOL recreatingEventTap;

static int quickTabSwitching;

static int middleClickFlag, magicMouseTwoFingerFlag, magicMouseThreeFingerFlag;
static int trackpadNFingers, trackpadClicked;
static MGTrackpadInteraction trackpadInteraction = {0};
static MGMouseClickInteraction magicMouseClickInteraction = {0};
static MGContactOnsetTracker magicMouseContactOnsets = {0};
static int lastLoggedMagicMouseClickContactCount = -1;
static BOOL trackpadRewritingSecondaryClick = NO;
static CGEventRef pendingMagicMousePrimaryDown = NULL;
static NSString *pendingMagicMouseClickGesture = nil;
static MGGestureSequence magicMouseSequence = {0};
static int autoScrollFlag;
static int moveResizeFlag, shouldExitMoveResize;

// suppress four-finger tap if pinky-to-index or index-to-pinky gestures were triggered
static BOOL trackpadTab4Triggered = FALSE;
static int trackpadTab4Step[2] = {0, 0};
static BOOL fourFingerTapTriggered = FALSE;

static int trigger = 0;

// Candidate clicks may wait for one touch frame to finish filtering. Ordinary
// one-contact clicks never take this path.
static const useconds_t kMagicMouseClickClassificationWaitMicroseconds = 20000;
static const useconds_t kMagicMouseClickClassificationPollMicroseconds = 500;
static const int64_t kTrickpadReplayedMouseEvent = 0x545249434b504144;

static void clearPendingMagicMouseClick(void) {
    if (pendingMagicMousePrimaryDown != NULL) {
        CFRelease(pendingMagicMousePrimaryDown);
        pendingMagicMousePrimaryDown = NULL;
    }
    [pendingMagicMouseClickGesture release];
    pendingMagicMouseClickGesture = nil;
}

static void replayPendingMagicMousePrimaryDown(void) {
    if (pendingMagicMousePrimaryDown == NULL) return;
    CGEventSetIntegerValueField(pendingMagicMousePrimaryDown,
                               kCGEventSourceUserData,
                               kTrickpadReplayedMouseEvent);
    CGEventPost(kCGSessionEventTap, pendingMagicMousePrimaryDown);
    clearPendingMagicMouseClick();
}

// A configured trackpad physical click replaces the native click: the
// suppressed mouse-down is held here so a drag can restore the native
// sequence, mirroring the Magic Mouse pending click above.
static CGEventRef pendingTrackpadPrimaryDown = NULL;

static void clearPendingTrackpadClick(void) {
    if (pendingTrackpadPrimaryDown != NULL) {
        CFRelease(pendingTrackpadPrimaryDown);
        pendingTrackpadPrimaryDown = NULL;
    }
}

// The area gesture recognized at a single-contact trackpad mouse-down, held
// until its mouse-up dispatches it or a drag keeps the click native.
static NSString *pendingTrackpadAreaClickGesture = nil;

static void replayPendingTrackpadPrimaryDown(void) {
    if (pendingTrackpadPrimaryDown == NULL) return;
    CGEventSetIntegerValueField(pendingTrackpadPrimaryDown,
                               kCGEventSourceUserData,
                               kTrickpadReplayedMouseEvent);
    CGEventPost(kCGSessionEventTap, pendingTrackpadPrimaryDown);
    clearPendingTrackpadClick();
}

enum {
    kGestureOwnerPhysicalClick = 1,
    kGestureOwnerTwoFingerTap,
    kGestureOwnerThreeFingerTap,
    kGestureOwnerFourFingerTap,
    kGestureOwnerFiveFingerTap,
    kGestureOwnerHoldTap,
    kGestureOwnerHoldSlide,
    kGestureOwnerTwoFixedOneSlide,
    kGestureOwnerThreeFingerSwipe,
    kGestureOwnerFourFingerSwipe,
    kGestureOwnerSequentialFourFingerTap,
    kGestureOwnerOneFingerTap,
    kGestureOwnerFrontRightTap,
    kGestureOwnerOneFingerSwipe,
    kGestureOwnerTwoFingerSwipe,
    kGestureOwnerOneFixedTwoSlide,
    kGestureOwnerThreeFingerPinch,
    kGestureOwnerTwoFixedOneDoubleTap,
    kGestureOwnerTwoFingerPinch,
    kGestureOwnerThumb,
};

static NSString *gestureOwnerName(NSUInteger owner) {
    switch (owner) {
        case kGestureOwnerPhysicalClick: return @"physical-click";
        case kGestureOwnerTwoFingerTap: return @"two-finger-tap";
        case kGestureOwnerThreeFingerTap: return @"three-finger-tap";
        case kGestureOwnerHoldTap: return @"hold-tap";
        case kGestureOwnerHoldSlide: return @"hold-slide";
        case kGestureOwnerTwoFixedOneSlide: return @"two-fixed-one-slide";
        case kGestureOwnerThreeFingerSwipe: return @"three-finger-swipe";
        case kGestureOwnerOneFingerTap: return @"one-finger-tap";
        case kGestureOwnerFrontRightTap: return @"front-right-tap";
        case kGestureOwnerOneFingerSwipe: return @"one-finger-swipe";
        case kGestureOwnerTwoFingerSwipe: return @"two-finger-swipe";
        case kGestureOwnerTwoFingerPinch: return @"two-finger-pinch";
        case kGestureOwnerThumb: return @"thumb";
        case 0: return @"none";
        default: return [NSString stringWithFormat:@"owner-%lu", (unsigned long)owner];
    }
}

static int disableHorizontalScroll;
static CFAbsoluteTime customMagicMouseScrollSuppressionUntil = 0;
static CFAbsoluteTime customMagicMouseTapSuppressionUntil = 0;
// Set when a physical click begins or ends, and cleared only by a full lift.
static BOOL magicMouseTapsSuppressedUntilLift = NO;
static CFAbsoluteTime customMagicMousePrimaryTapSuppressionUntil = 0;
static const float kMagicMousePrimaryTapStartMinY = 0.58f;
static const float kMagicMousePrimaryTapKeepMinY = 0.54f;
static const double kMagicMousePrimaryTapMaxDuration = 0.14;
static const double kMagicMousePrimaryTapMaxMove = 0.00035;
static const double kMagicMouseTapSuppressionAfterScroll = 0.14;
static const double kMagicMouseTwoFingerTapMaxDuration = 0.36;
static const double kMagicMouseTwoFingerTapMaxMove = 0.006;
static const double kMagicMouseTwoFingerTapLiftGraceDuration = 0.10;
static const double kMagicMouseTwoFingerTapMaximumOnsetSpread = 0.12;
static const double kMagicMouseThreeFingerTapMaxDuration = 0.36;
static const double kMagicMouseThreeFingerTapMaxMove = 0.006;
static const double kMagicMouseThreeFingerTapLiftGraceDuration = 0.10;
static const float kMagicMouseRightFrontTapStartMinX = 0.74f;
static const float kMagicMouseRightFrontTapStartMinY = 0.78f;
static const float kMagicMouseRightFrontTapKeepMinX = 0.70f;
static const float kMagicMouseRightFrontTapKeepMinY = 0.74f;
static const double kMagicMouseRightFrontTapMaxDuration = 0.21;
static const double kMagicMouseRightFrontTapMaxMove = 0.00075;
static const double kTrackpadSimultaneousTapMaximumOnsetSpread = 0.05;

static BOOL trackpadContactsArrivedTogether(const Finger *data, int contactCount,
                                            double maximumSpread) {
    int identifiers[16];
    int limitedCount = MIN(contactCount, 16);
    for (int i = 0; i < limitedCount; i++)
        identifiers[i] = data[i].identifier;
    return MGTrackpadInteractionContactsArrivedWithin(
        &trackpadInteraction, identifiers, limitedCount, maximumSpread);
}

static GestureWindow *gestureWindow;

static Gesture *me;

static int simulating, simulatingByDevice;

static NSMutableDictionary *sizeHistoryDict;

static KeyUtility *keyUtil;

/* Character Recognizer Begin */
typedef struct {
    float deg, span;
    int type;
} DegreeSpan;
typedef struct {
    DegreeSpan ds[10];
    const char *ch;
    int step;
    float score;
} Character;
static Character chars[100];
static int nChars;

static float normPdf[201];
static float normIPdf[201];
static void trackpadRecognizerTwo(const Finger *data, int nFingers, double timestamp);
static void trackpadRecognizerOne(const Finger *data, int nFingers, double timestamp);
static int mouseRecognizer(float x, float y, int step);
static void initChars(void);
static void initNormPdf(void);
static int isTrackpadRecognizing, isMouseRecognizing;
static int cancelRecognition;
/* Character Recognizer End */


static double lenSqr(double x1, double y1, double x2, double y2) {
    return (x1 - x2) * (x1 - x2) + (y1 - y2) * (y1 - y2);
}

static BOOL magicMousePointIsRightFrontTapRegion(float x, float y) {
    return x >= kMagicMouseRightFrontTapKeepMinX && y >= kMagicMouseRightFrontTapKeepMinY;
}

static MGSequenceDispatcher *sequenceDispatcher(void);

static double lenSqrF(const Finger *data, int a, int b) {
    return lenSqr(data[a].px, data[a].py, data[b].px, data[b].py);
}

static float cosineBetweenVectors(float v0x, float v0y, float v1x, float v1y) {
    return (v0x*v1x + v0y*v1y) / sqrtf((v0x*v0x + v0y*v0y) * (v1x*v1x + v1y*v1y));
}

static void turnOffTrackpad() {
    trackpadNFingers = 0;
    MGTrackpadInteractionInitialize(&trackpadInteraction);
    clearPendingTrackpadClick();
    [pendingTrackpadAreaClickGesture release];
    pendingTrackpadAreaClickGesture = nil;
}

static void turnOffMagicMouse() {
    middleClickFlag = 0;
    magicMouseTwoFingerFlag = 0;
    magicMouseThreeFingerFlag = 0;
    simulating = 0;
    disableHorizontalScroll = 0;
    quickTabSwitching = 0;
    MGGestureSequenceInitialize(&magicMouseSequence);
    MGMouseClickInteractionInitialize(&magicMouseClickInteraction);
    magicMouseContactOnsets = (MGContactOnsetTracker){0};
    clearPendingMagicMouseClick();
    [cursorWindow orderOut:nil];
}

static void multitouchDeviceWasRemoved(BOOL wasMagicMouse) {
    trigger = 0;
    if (wasMagicMouse)
        turnOffMagicMouse();
}

static void turnOffCharacters() {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    [gestureWindow clear];
    [gestureWindow orderOut:nil];
    [pool release];
    isTrackpadRecognizing = 0;
    isMouseRecognizing = 0;
}

void turnOffGestures() {
    cancelPendingGestureSequences();
    turnOffTrackpad();
    turnOffMagicMouse();
    turnOffCharacters();
}

static void mouseClick(int a, CGFloat x, CGFloat y) {
    CGPoint location = CGPointMake(x, y);

    if (a & 4) {
        CGEventRef eventRef = CGEventCreateMouseEvent(NULL, kCGEventLeftMouseDragged, location, kCGMouseButtonLeft);
        CGEventPost(kCGSessionEventTap, eventRef);
        CFRelease(eventRef);
    }
    if (a & 8) {
        CGEventRef eventRef = CGEventCreateMouseEvent(NULL, kCGEventMouseMoved, location, kCGMouseButtonLeft);
        CGEventPost(kCGSessionEventTap, eventRef);
        CFRelease(eventRef);
    }
    if (a & 1) {
        CGEventRef eventRef = CGEventCreateMouseEvent(NULL, kCGEventLeftMouseDown, location, kCGMouseButtonLeft);
        CGEventPost(kCGSessionEventTap, eventRef);
        CFRelease(eventRef);
    }
    if (a & 2) {
        CGEventRef eventRef = CGEventCreateMouseEvent(NULL, kCGEventLeftMouseUp, location, kCGMouseButtonLeft);
        CGEventPost(kCGSessionEventTap, eventRef);
        CFRelease(eventRef);
    }
}

static void postSyntheticMouseMove(CGPoint location, CGEventTapLocation tapLocation) {
    CGEventSourceRef source = CGEventSourceCreate(kCGEventSourceStateCombinedSessionState);
    CGEventRef moveEvent = CGEventCreateMouseEvent(source, kCGEventMouseMoved, location, kCGMouseButtonLeft);
    if (moveEvent) {
        CGEventPost(tapLocation, moveEvent);
        CFRelease(moveEvent);
    }
    if (source) {
        CFRelease(source);
    }
}

static void postSyntheticMouseClickWithFlags(CGEventType downType,
                                             CGEventType upType,
                                             CGMouseButton button,
                                             int64_t buttonNumber,
                                             CGPoint location,
                                             CGEventTapLocation tapLocation,
                                             CGEventFlags flags) {
    CGEventSourceRef source = CGEventSourceCreate(kCGEventSourceStateCombinedSessionState);

    CGEventRef downEvent = CGEventCreateMouseEvent(source, downType, location, button);
    if (downEvent) {
        CGEventSetIntegerValueField(downEvent, kCGMouseEventButtonNumber, buttonNumber);
        CGEventSetIntegerValueField(downEvent, kCGMouseEventClickState, 1);
        if (flags != 0) {
            CGEventSetFlags(downEvent, flags);
        }
        CGEventPost(tapLocation, downEvent);
        CFRelease(downEvent);
    }

    // A short gap makes the synthetic click behave more like a real click for context menus.
    usleep(12000);

    CGEventRef upEvent = CGEventCreateMouseEvent(source, upType, location, button);
    if (upEvent) {
        CGEventSetIntegerValueField(upEvent, kCGMouseEventButtonNumber, buttonNumber);
        CGEventSetIntegerValueField(upEvent, kCGMouseEventClickState, 1);
        if (flags != 0) {
            CGEventSetFlags(upEvent, flags);
        }
        CGEventPost(tapLocation, upEvent);
        CFRelease(upEvent);
    }

    if (source) {
        CFRelease(source);
    }
}

static void postSyntheticMouseClick(CGEventType downType,
                                    CGEventType upType,
                                    CGMouseButton button,
                                    int64_t buttonNumber,
                                    CGPoint location,
                                    CGEventTapLocation tapLocation) {
    postSyntheticMouseClickWithFlags(downType, upType, button, buttonNumber, location, tapLocation, 0);
}

static void getMousePosition(CGFloat *x, CGFloat *y) {
    CGEventRef ourEvent = CGEventCreate(NULL);
    CGPoint ourLoc = CGEventGetLocation(ourEvent);
    CFRelease(ourEvent);
    *x = ourLoc.x;
    *y = ourLoc.y;
}

static CFTypeRef getForemostApp() {
    CFTypeRef focusedAppRef;
    if (systemWideElement && AXUIElementCopyAttributeValue(systemWideElement, kAXFocusedApplicationAttribute, &focusedAppRef) != kAXErrorSuccess) {
        NSRunningApplication *frontmostApplication = [[NSWorkspace sharedWorkspace] frontmostApplication];
        focusedAppRef = AXUIElementCreateApplication([frontmostApplication processIdentifier]);
        if (focusedAppRef == NULL) {
            return NULL;
        }
    }
    CFTypeRef focusedWindowRef;

    // does this code belong here?
    CFTypeRef titleRef;
    if (AXUIElementCopyAttributeValue(focusedAppRef, kAXTitleAttribute, &titleRef) == kAXErrorSuccess) {
        if (
            [(NSString*)titleRef isEqualToString:@"Notification Center"] ||
            [(NSString*)titleRef isEqualToString:@"Control Center"]
        ) {
            CFRelease(titleRef);
            return NULL;
        }
        CFRelease(titleRef);
    }

    if (AXUIElementCopyAttributeValue(focusedAppRef, kAXFocusedWindowAttribute, &focusedWindowRef) == kAXErrorSuccess) {
        CFRelease(focusedAppRef);
        return focusedWindowRef;
    }
    CFRelease(focusedAppRef);
    return NULL;
}

static void getWindowPos(CFTypeRef winRef, CGFloat *x, CGFloat *y) {
    CFTypeRef positionRef;
    if (winRef && AXUIElementCopyAttributeValue(winRef, kAXPositionAttribute, &positionRef) == kAXErrorSuccess) {
        CGPoint pos;
        AXValueGetValue((AXValueRef)positionRef, kAXValueCGPointType, &pos);
        *x = pos.x;
        *y = pos.y;
        CFRelease(positionRef);
    }
}

static void getWindowSize(CFTypeRef winRef, CGFloat *w, CGFloat *h) {
    CFTypeRef sizeRef;
    if (winRef && AXUIElementCopyAttributeValue(winRef, kAXSizeAttribute, &sizeRef) == kAXErrorSuccess) {
        CGSize size;
        AXValueGetValue((AXValueRef)sizeRef, kAXValueCGSizeType, &size);
        *w = size.width;
        *h = size.height;
        CFRelease(sizeRef);
    }
}

static void setWindowPos(CFTypeRef window, CGFloat x, CGFloat y) {
    CGPoint t1 = CGPointMake(x, y);
    CFTypeRef newLocRef = AXValueCreate(kAXValueCGPointType, (void *)&t1);
    if (newLocRef) {
        if (window)
            AXUIElementSetAttributeValue(window, kAXPositionAttribute, newLocRef);
        CFRelease(newLocRef);
    }
}

static int setWindowSize(CFTypeRef window, CGFloat w, CGFloat h) {
    CGSize t2 = CGSizeMake(w, h);
    CFTypeRef newSizeRef = AXValueCreate(kAXValueCGSizeType, (void *)&t2);
    if (newSizeRef) {
        if (window && AXUIElementSetAttributeValue(window, kAXSizeAttribute, newSizeRef) != kAXErrorSuccess) {
            CFRelease(newSizeRef);
            return 0;
        }
        CFRelease(newSizeRef);
    }
    return 1;
}
static void setWindowPos2(CFTypeRef window, CGFloat x, CGFloat y, CGFloat baseX, CGFloat baseY, CGFloat appX, CGFloat appY) {
    setWindowPos(window, appX+x-baseX, appY+y-baseY);
}
static int setWindowSize2(CFTypeRef window, CGFloat x, CGFloat y, CGFloat baseX, CGFloat baseY) {
    CGFloat appW, appH;
    getWindowSize(window, &appW, &appH);
    return setWindowSize(window, appW+x-baseX, appH+y-baseY);
}
static void maximizeForemostWindow() {
    CFTypeRef winRef = getForemostApp();
    if (winRef) {
        CFTypeRef zoomButton;
        if (AXUIElementCopyAttributeValue(winRef, kAXZoomButtonAttribute, &zoomButton) == kAXErrorSuccess) {
            AXUIElementPerformAction(zoomButton, kAXPressAction);
            CFRelease(zoomButton);
        }
        CFRelease(winRef);
    }
}
static void minimizeForemostWindow() {
    CFTypeRef winRef = getForemostApp();
    if (winRef) {
        CFTypeRef minButton;
        if (AXUIElementCopyAttributeValue(winRef, kAXMinimizeButtonAttribute, &minButton) == kAXErrorSuccess) {
            AXUIElementPerformAction(minButton, kAXPressAction);
            CFRelease(minButton);
        }
        CFRelease(winRef);
    }
}
static void maximizeWindow(CFTypeRef window, int pos) {
    if (!window) return;

    NSArray *screens = [NSScreen screens];
    CGEventRef ourEvent = CGEventCreate(NULL);
    CGPoint location = CGEventGetUnflippedLocation(ourEvent);
    CFRelease(ourEvent);

    NSUInteger isIn = 0;
    for (NSUInteger i = 0; i < [screens count]; i++) {
        NSRect scr = [[screens objectAtIndex:i] frame];
        NSPoint origin = scr.origin;
        NSSize size = scr.size;

        if (location.x >= origin.x && location.x <= origin.x + size.width &&
           location.y >= origin.y && location.y <= origin.y + size.height) {
            isIn = i;
            break;
        }
    }
    NSRect scr = [[screens objectAtIndex:isIn] visibleFrame];
    NSPoint origin = scr.origin;
    NSSize size = scr.size;

    CGFloat appW, appH, appX, appY;
    getWindowSize(window, &appW, &appH);
    getWindowPos(window, &appX, &appY);
    SizeHistoryKey *key = [[SizeHistoryKey alloc] initWithKey:window];
    SizeHistory *sh = [sizeHistoryDict objectForKey:key];
    if (pos == 0) {
        if (sh) {
            if (appX == sh.curRect.origin.x && appY == sh.curRect.origin.y && appW == sh.curRect.size.width && appH == sh.curRect.size.height) {
                setWindowPos(window, sh.savRect.origin.x, sh.savRect.origin.y);
                setWindowSize(window, sh.savRect.size.width, sh.savRect.size.height);
            }
            [sizeHistoryDict removeObjectForKey:key];
        }
    } else {
        if (pos == 1) {
            setWindowPos(window, origin.x, [[screens objectAtIndex:0] frame].size.height - origin.y - size.height);
            setWindowSize(window, size.width, size.height);
        } else if (pos == 2) {
            setWindowPos(window, origin.x, [[screens objectAtIndex:0] frame].size.height - origin.y - size.height);
            setWindowSize(window, size.width / 2, size.height);
        }  else if (pos == 3) {
            setWindowPos(window, origin.x + size.width / 2, [[screens objectAtIndex:0] frame].size.height - origin.y - size.height);
            setWindowSize(window, size.width / 2, size.height);
         }
        CGFloat appW2, appH2, appX2, appY2;
        getWindowSize(window, &appW2, &appH2);
        getWindowPos(window, &appX2, &appY2);

        if (!sh || sh.curRect.size.width != appW || sh.curRect.size.height != appH || sh.curRect.origin.x != appX || sh.curRect.origin.y != appY) {
            SizeHistory *newSH = [[SizeHistory alloc] initWithCurRect:NSMakeRect(appX2, appY2, appW2, appH2) SaveRect:NSMakeRect(appX, appY, appW, appH)];
            [sizeHistoryDict setObject:(id)newSH forKey:key];
            [newSH release];
        } else if (sh) {
            SizeHistory *newSH = [[SizeHistory alloc] initWithCurRect:NSMakeRect(appX2, appY2, appW2, appH2) SaveRect:sh.savRect];
            [sizeHistoryDict setObject:(id)newSH forKey:key];
            [newSH release];
        }
    }
    [key release];
}

static NSString* nameOfAxui(CFTypeRef ref) {
    pid_t theTgtAppPID = 0;
    ProcessSerialNumber theTgtAppPSN = {0, 0};
    CFStringRef processName = NULL;
    if (AXUIElementGetPid(ref, &theTgtAppPID) == kAXErrorSuccess &&
        GetProcessForPID(theTgtAppPID, &theTgtAppPSN) == noErr) {
        CopyProcessName(&theTgtAppPSN, &processName);
    }
    return (NSString *)processName;
}

static NSString *copyNormalizedApplicationName(NSString *application) {
    if (application == nil || [application length] == 0) {
        return nil;
    }

    NSString *normalized = application;
    if ([application hasPrefix:@"Google Chrome Helper"]) {
        normalized = @"Google Chrome";
    } else if ([application hasPrefix:@"Chromium Helper"]) {
        normalized = @"Chromium";
    } else if ([application hasPrefix:@"Brave Browser Helper"]) {
        normalized = @"Brave Browser";
    } else if ([application hasPrefix:@"Microsoft Edge Helper"]) {
        normalized = @"Microsoft Edge";
    } else if ([application hasPrefix:@"Arc Helper"]) {
        normalized = @"Arc";
    } else if ([application hasPrefix:@"Opera Helper"]) {
        normalized = @"Opera";
    }

    if ([normalized isEqualToString:@"Control Center"] ||
        [normalized isEqualToString:@"Notification Center"] ||
        [normalized isEqualToString:@"Dock"]) {
        return nil;
    }

    return [normalized copy];
}

static void addApplicationCandidate(NSMutableArray *applications, NSString *application) {
    if (application == nil || [application length] == 0) {
        return;
    }

    if (![applications containsObject:application]) {
        [applications addObject:application];
    }
}

static NSString *copyBundleIdentifierOfAxui(CFTypeRef ref) {
    pid_t pid = 0;
    if (ref == nil || AXUIElementGetPid(ref, &pid) != kAXErrorSuccess)
        return nil;
    NSRunningApplication *application =
        [NSRunningApplication runningApplicationWithProcessIdentifier:pid];
    return [[application bundleIdentifier] copy];
}

static NSArray *resolveApplicationCandidates(void) {
    NSMutableArray *applications = [NSMutableArray array];

    CFTypeRef underMouseAxui = axuiUnderMouse();
    NSString *underMouseRawName = nameOfAxui(underMouseAxui);
    NSString *underMouseName = copyNormalizedApplicationName(underMouseRawName);
    addApplicationCandidate(applications, underMouseName);
    NSString *underMouseBundleID = copyBundleIdentifierOfAxui(underMouseAxui);
    addApplicationCandidate(applications, underMouseBundleID);
    [underMouseName release];
    [underMouseBundleID release];
    CFSafeRelease(underMouseRawName);
    CFSafeRelease(underMouseAxui);

    CFTypeRef frontmostWindow = getForemostApp();
    NSString *frontmostRawName = nameOfAxui(frontmostWindow);
    NSString *frontmostName = copyNormalizedApplicationName(frontmostRawName);
    addApplicationCandidate(applications, frontmostName);
    NSString *frontmostBundleID = copyBundleIdentifierOfAxui(frontmostWindow);
    addApplicationCandidate(applications, frontmostBundleID);
    [frontmostName release];
    [frontmostBundleID release];
    CFSafeRelease(frontmostRawName);
    CFSafeRelease(frontmostWindow);

    return applications;
}

// Every binding lookup goes through the cache, since a touch frame asks for
// this several times over and the resolution above is all Accessibility calls.
static NSArray *applicationCandidatesForGestureLookup(void) {
    return MGApplicationScopeCacheCandidates();
}

// declared reports whether any configuration entry named the gesture at all,
// so a caller can tell an explicit "off" apart from an absent binding.
static NSDictionary *resolvedBindingForGesture(NSString *gesture,
                                               NSDictionary *commandMap,
                                               NSArray *applications,
                                               BOOL includeUnassigned,
                                               NSString **matchedApplication,
                                               BOOL *declared) {
    for (NSString *application in applications) {
        NSDictionary *applicationBindings = [commandMap objectForKey:application];
        NSDictionary *binding = [applicationBindings objectForKey:gesture];
        if (binding != nil) {
            if (matchedApplication != NULL)
                *matchedApplication = application;
            if (declared != NULL)
                *declared = YES;
            return [[binding objectForKey:@"Enable"] boolValue] ? binding : nil;
        }
        if (includeUnassigned) {
            binding = [applicationBindings objectForKey:@"All Unassigned Gestures"];
            if (binding != nil) {
                if (matchedApplication != NULL)
                    *matchedApplication = application;
                if (declared != NULL)
                    *declared = YES;
                return [[binding objectForKey:@"Enable"] boolValue] ? binding : nil;
            }
        }
    }

    NSDictionary *binding = [[commandMap objectForKey:@"All Applications"] objectForKey:gesture];
    if (binding != nil && matchedApplication != NULL)
        *matchedApplication = @"All Applications";
    if (binding != nil && declared != NULL)
        *declared = YES;
    return binding && [[binding objectForKey:@"Enable"] boolValue] ? binding : nil;
}

static CFTypeRef activateWindowAtPosition(CGFloat x, CGFloat y) {
    AXUIElementRef focusedElement;
    CFTypeRef windowRef, tmp;
    pid_t theTgtAppPID = 0;
    ProcessSerialNumber theTgtAppPSN = {0, 0};

    if (systemWideElement && AXUIElementCopyElementAtPosition(systemWideElement, x, y, &focusedElement) == kAXErrorSuccess) {
        // Catch app such as TextMate that doesn't provide accessibilty interface
        if (AXUIElementCopyAttributeValue(focusedElement, kAXRoleAttribute, &tmp) != kAXErrorSuccess) {
            if (AXUIElementGetPid(focusedElement, &theTgtAppPID) == kAXErrorSuccess &&
                GetProcessForPID(theTgtAppPID, &theTgtAppPSN) == noErr &&
                SetFrontProcess(&theTgtAppPSN) == noErr) {
                CFRelease(focusedElement);
                AXUIElementCopyAttributeValue(systemWideElement, kAXFocusedApplicationAttribute, &tmp);
                if (tmp && AXUIElementCopyAttributeValue(tmp, kAXFocusedWindowAttribute, &windowRef) == kAXErrorSuccess) {
                    CFRelease(tmp);
                    return windowRef;
                }
                CFSafeRelease(tmp);
                return NULL;
            }
            CFRelease(focusedElement);
        } else {
            CFRelease(tmp);
            if (AXUIElementCopyAttributeValue(focusedElement, kAXWindowAttribute, &windowRef) != kAXErrorSuccess) {
                windowRef = focusedElement;
            }
            AXUIElementPerformAction(windowRef, kAXRaiseAction);
            if (AXUIElementGetPid(windowRef, &theTgtAppPID) == kAXErrorSuccess &&
                GetProcessForPID(theTgtAppPID, &theTgtAppPSN) == noErr &&
                SetFrontProcessWithOptions(&theTgtAppPSN, kSetFrontProcessFrontWindowOnly) == noErr) {
            }
            if (windowRef != focusedElement)
                CFRelease(focusedElement);
            return windowRef;
        }
    }
    return nil;
}

static CGFloat findTabGroup_lx;
static void findTabGroup2(CFTypeRef windowRef, float cx, float cy) {
    CFTypeRef tmp, tmp2;
    float tabY = 0.0;
    int flag = 1;

    // windowRef = AXWindow of Safari
    if (windowRef && AXUIElementCopyAttributeValue(windowRef, kAXChildrenAttribute, &tmp) == kAXErrorSuccess) {
        CFIndex nCh = CFArrayGetCount((CFArrayRef)tmp);
        for (CFIndex i = 0; i < nCh && flag; i++) {
            CFTypeRef menuTitle = nil;
            CFTypeRef theMenu = (CFStringRef)CFArrayGetValueAtIndex(tmp, i);
            if (theMenu && AXUIElementCopyAttributeValue((AXUIElementRef)theMenu, kAXRoleAttribute, (CFTypeRef *)&menuTitle) == kAXErrorSuccess
               && menuTitle && ((CFStringCompare(menuTitle, CFSTR("AXTabGroup"), 0) == kCFCompareEqualTo))) {

                // Now theMenu = AXGroup
                if (AXUIElementCopyAttributeValue(theMenu, kAXTabsAttribute, &tmp2) == kAXErrorSuccess) {
                    CFIndex nCh = CFArrayGetCount((CFArrayRef)tmp2);
                    for (CFIndex i = 0; i < nCh && flag; i++) {
                        CFTypeRef theMenu = (CFStringRef)CFArrayGetValueAtIndex(tmp2, i);

                        CGFloat x, y, w, h;
                        getWindowPos(theMenu, &x, &y);
                        getWindowSize(theMenu, &w, &h);
                        tabY = y;
                        if (cx >= x && cx < x+w) {
                            if (fabs(findTabGroup_lx - x) > 10) {
                                AXUIElementPerformAction(theMenu, kAXPressAction);
                                flag = 0;
                            }
                            findTabGroup_lx = x;
                        }
                    }
                    CFRelease(tmp2);
                }
            }
            CFSafeRelease(menuTitle);
        }
        CFRelease(tmp);
    }
    NSRect scr = [[NSScreen mainScreen] frame];
    [cursorWindow setFrameOrigin:NSMakePoint(cx - 31, scr.size.height - tabY - 20)];
}

static int selectSafariTab() {
    CGFloat x, y;
    int ret = 0;
    getMousePosition(&x, &y);
    AXUIElementRef focusedElement;
    CFTypeRef windowRef = NULL;
    pid_t theTgtAppPID = 0;
    ProcessSerialNumber theTgtAppPSN = {0, 0};

    if (systemWideElement && AXUIElementCopyElementAtPosition(systemWideElement, x, y, &focusedElement) == kAXErrorSuccess) {
        if (AXUIElementGetPid(focusedElement, &theTgtAppPID) == kAXErrorSuccess &&
            GetProcessForPID(theTgtAppPID, &theTgtAppPSN) == noErr) {

            CFStringRef processName = NULL;
            CopyProcessName(&theTgtAppPSN, &processName);
            if (CFStringCompare(processName, CFSTR("Safari"), 0) == kCFCompareEqualTo) {

                if (focusedElement && AXUIElementCopyAttributeValue(focusedElement, kAXWindowAttribute, &windowRef) != kAXErrorSuccess)
                    windowRef = focusedElement;
                findTabGroup2(windowRef, x, y);
                ret = 1;
                if (windowRef != focusedElement)
                    CFSafeRelease(windowRef);
            }
            CFSafeRelease(processName);
        }
        CFRelease(focusedElement);
    }
    return ret;
}

static CFTypeRef axuiUnderMouse() {
    CGFloat x, y;
    AXUIElementRef focusedElement = nil;
    getMousePosition(&x, &y);
    if (systemWideElement)
        AXUIElementCopyElementAtPosition(systemWideElement, x, y, &focusedElement);
    return focusedElement;
}

static BOOL axuiSupportsAction(AXUIElementRef element, CFStringRef action) {
    if (!element || !action) {
        return NO;
    }

    CFArrayRef actionNames = nil;
    BOOL supported = NO;
    if (AXUIElementCopyActionNames(element, &actionNames) == kAXErrorSuccess && actionNames) {
        supported = CFArrayContainsValue(actionNames,
                                         CFRangeMake(0, CFArrayGetCount(actionNames)),
                                         action);
        CFRelease(actionNames);
    }
    return supported;
}

static BOOL showContextMenuForAxuiOrAncestor(AXUIElementRef element) {
    AXUIElementRef current = element;
    if (current) {
        CFRetain(current);
    }

    for (int depth = 0; current && depth < 6; depth++) {
        if (axuiSupportsAction(current, kAXShowMenuAction)) {
            AXError error = AXUIElementPerformAction(current, kAXShowMenuAction);
            CFRelease(current);
            return error == kAXErrorSuccess;
        }

        AXUIElementRef parent = nil;
        if (AXUIElementCopyAttributeValue(current, kAXParentAttribute, (CFTypeRef *)&parent) != kAXErrorSuccess) {
            parent = nil;
        }
        CFRelease(current);
        current = parent;
    }

    return NO;
}

static BOOL showContextMenuUnderMouse(void) {
    CFTypeRef axui = axuiUnderMouse();
    BOOL shown = showContextMenuForAxuiOrAncestor((AXUIElementRef)axui);
    CFSafeRelease(axui);
    return shown;
}

static BOOL isMouseOnEmptySpace() {
    BOOL ret = NO;
    CFTypeRef axui = axuiUnderMouse();
    NSString *application = nameOfAxui(axui);
    if ([application isEqualToString:@"Finder"]) {
        CFTypeRef windowRef = nil;
        CFStringRef roleRef = nil;
        if (axui && AXUIElementCopyAttributeValue(axui, kAXWindowAttribute, &windowRef) == kAXErrorSuccess) {
            if (windowRef && AXUIElementCopyAttributeValue((AXUIElementRef)windowRef, kAXRoleAttribute, (CFTypeRef*)&roleRef) == kAXErrorSuccess &&
                roleRef && ((CFStringCompare(roleRef, CFSTR("AXScrollArea"), 0) == kCFCompareEqualTo))) {
                ret = YES;
            }
        }
        CFSafeRelease(roleRef);
        CFSafeRelease(windowRef);
        [application release];
    }
    CFSafeRelease(axui);
    return ret;
}

// The most specific bound name wins: a directional swipe binding, wherever it
// is scoped, takes its direction before the bare family binding is consulted.
// An explicit "off" on the directional name also stops the family fallback.
static NSDictionary *bindingForGestureWithMatch(NSString *gesture, int device,
                                                NSString **matchedApplication) {
    NSArray *applications = applicationCandidatesForGestureLookup();
    NSDictionary *commandMap = device == TRACKPAD ? trackpadMap :
        device == MAGICMOUSE ? magicMouseMap : recognitionMap;
    BOOL declared = NO;
    NSDictionary *binding = resolvedBindingForGesture(gesture, commandMap, applications, NO,
                                                      matchedApplication, &declared);
    if (binding != nil || declared)
        return binding;
    NSString *family = [Config directionlessGestureName:gesture];
    if (family == nil)
        return nil;
    return resolvedBindingForGesture(family, commandMap, applications, NO,
                                     matchedApplication, NULL);
}

static NSDictionary *bindingForGesture(NSString *gesture, int device) {
    return bindingForGestureWithMatch(gesture, device, NULL);
}

static NSString* commandForGesture(NSString *gesture, int device) {
    return [bindingForGesture(gesture, device) objectForKey:@"Command"];
}

static MGDeferredGestureDispatcher *deferredGestureDispatcher(void) {
    static MGDeferredGestureDispatcher *dispatcher = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        dispatcher = [[MGDeferredGestureDispatcher alloc] initWithScheduler:
            ^(NSTimeInterval delay, dispatch_block_t block) {
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)),
                               dispatch_get_global_queue(QOS_CLASS_USER_INTERACTIVE, 0), block);
            }];
    });
    return dispatcher;
}

static MGSequenceDispatcher *sequenceDispatcher(void) {
    static MGSequenceDispatcher *dispatcher = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        dispatcher = [[MGSequenceDispatcher alloc] initWithScheduler:
            ^(NSTimeInterval delay, dispatch_block_t block) {
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)),
                               dispatch_get_global_queue(QOS_CLASS_USER_INTERACTIVE, 0), block);
            }];
    });
    return dispatcher;
}

void cancelPendingGestureSequences(void) {
    [sequenceDispatcher() cancelAll];
}

// One shared instance per sound name, restarted when a gesture fires during
// its own tail, so a repeat is always audible.
static void playSystemSound(NSString *name) {
    if ([name length] == 0)
        return;
    dispatch_async(dispatch_get_main_queue(), ^{
        NSSound *sound = [NSSound soundNamed:name];
        if (sound == nil) {
            NSLog(@"Could not play configured sound \"%@\"", name);
            return;
        }
        if ([sound isPlaying])
            [sound stop];
        [sound play];
    });
}

// One shared synthesizer, interrupted the way a sound restarts, so a repeat is
// heard as its own utterance rather than swallowed by the previous one. When a
// sound plays on the same dispatch, the words wait for it through the
// utterance's own pre-delay, so interrupting the speech also drops the wait.
static void speakText(NSString *text, NSString *precedingSoundName) {
    if ([text length] == 0)
        return;
    dispatch_async(dispatch_get_main_queue(), ^{
        static AVSpeechSynthesizer *synthesizer = nil;
        static AVSpeechSynthesisVoice *voice = nil;
        if (synthesizer == nil) {
            synthesizer = [[AVSpeechSynthesizer alloc] init];
            // An utterance with no voice falls back to the compact default,
            // which sounds far worse than the voices already installed.
            NSString *language = [AVSpeechSynthesisVoice currentLanguageCode];
            for (AVSpeechSynthesisVoice *candidate in [AVSpeechSynthesisVoice speechVoices]) {
                if (![[candidate language] isEqualToString:language])
                    continue;
                if (voice == nil || [candidate quality] > [voice quality])
                    voice = [candidate retain];
            }
        }
        if ([synthesizer isSpeaking])
            [synthesizer stopSpeakingAtBoundary:AVSpeechBoundaryImmediate];
        AVSpeechUtterance *utterance = [[[AVSpeechUtterance alloc]
            initWithString:text] autorelease];
        if (voice != nil)
            [utterance setVoice:voice];
        if ([precedingSoundName length] > 0) {
            NSSound *preceding = [NSSound soundNamed:precedingSoundName];
            // A long sound tail reads as lag once the attack has confirmed
            // the gesture, so the wait is bounded rather than literal.
            if (preceding != nil)
                [utterance setPreUtteranceDelay:MIN([preceding duration], 1.5)];
        }
        [synthesizer speakUtterance:utterance];
    });
}

// A Magic Mouse has no haptic actuator, so a configured sound or phrase is the
// only confirmation channel available on that device. Both start immediately
// and never delay the action they accompany.
static void confirmBindingDispatch(NSDictionary *binding, int device) {
    playSystemSound([binding objectForKey:@"ConfirmSound"]);
    speakText([binding objectForKey:@"ConfirmSpeech"],
              [binding objectForKey:@"ConfirmSound"]);
}

// AppKit chooses the available actuator and may suppress feedback when the
// trackpad is no longer being touched. The main queue keeps AppKit access on
// its owning thread while requesting feedback as close to recognition as able.
static void requestHapticFeedbackForBinding(NSDictionary *binding, int device) {
    NSNumber *bindingPreference = [binding objectForKey:@"HapticFeedback"];
    BOOL enabled = bindingPreference != nil ? [bindingPreference boolValue] : hapticFeedback;
    if (!(enabled && device == TRACKPAD))
        return;
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSHapticFeedbackManager defaultPerformer]
            performFeedbackPattern:NSHapticFeedbackPatternGeneric
                    performanceTime:NSHapticFeedbackPerformanceTimeNow];
    });
}

static void playInternalGestureDispatchTone(void) {
    static SystemSoundID soundID = 0;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSURL *url = [NSURL fileURLWithPath:@"/System/Library/Sounds/Glass.aiff"];
        AudioServicesCreateSystemSoundID((CFURLRef)url, &soundID);
    });
    if (soundID != 0)
        AudioServicesPlaySystemSound(soundID);
}

static void doCommand(NSString *gesture, int device, NSDictionary *commandDict,
                      NSString *matchedApplication);

// The work one binding performs, without the feedback that confirms it. A
// deferred binding raises its own feedback here, when the wait ends rather than
// when the gesture was recognized.
static dispatch_block_t bindingAction(NSString *gesture, int device, NSDictionary *binding,
                                      NSString *matchedApplication, BOOL confirmsWhenRun) {
    return [[^{
        if (confirmsWhenRun) {
            requestHapticFeedbackForBinding(binding, device);
            confirmBindingDispatch(binding, device);
        }
        if ([[NSUserDefaults standardUserDefaults] boolForKey:@"InternalGestureDispatchTone"])
            playInternalGestureDispatchTone();
        NSDate *start = [NSDate date];
        doCommand(gesture, device, binding, matchedApplication);
        NSTimeInterval timeInterval = -[start timeIntervalSinceNow];
        if (device >= 0 && device < sizeof(deviceTypeName) / sizeof(deviceTypeName[0]) && logLevel >= LOG_LEVEL_INFO) NSLog(@"Gesture \"%@\" for %@ took %f s", gesture, deviceTypeName[device], timeInterval);
    } copy] autorelease];
}

// Confirms and runs a binding at once, with the feedback raised on the calling
// thread so it stays as close to recognition as able.
static void dispatchBindingNow(NSString *gesture, int device, NSDictionary *binding,
                               NSString *matchedApplication) {
    requestHapticFeedbackForBinding(binding, device);
    confirmBindingDispatch(binding, device);
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INTERACTIVE, 0),
                   bindingAction(gesture, device, binding, matchedApplication, NO));
}

static void dispatchCommand(NSString *gesture, int device) {
    NSString *matchedApplication = nil;
    NSDictionary *binding = bindingForGestureWithMatch(gesture, device, &matchedApplication);
    // A double tap is reached only by repeating its single tap, so the single
    // tap's dispatch resolves both bindings and decides between them.
    NSString *doubleGesture = [Config doubleTapGestureName:gesture];
    NSString *doubleApplication = nil;
    NSDictionary *doubleBinding = doubleGesture == nil ? nil
        : bindingForGestureWithMatch(doubleGesture, device, &doubleApplication);
    if (binding == nil && doubleBinding == nil)
        return;
    if (device == MAGICMOUSE && MGTraceSuppressesActions()) {
        NSDictionary *traced = binding ?: doubleBinding;
        NSString *scope = [(binding != nil ? matchedApplication : doubleApplication)
                           isEqualToString:@"All Applications"] ? @"global" : @"application";
        NSString *kind = ![[traced objectForKey:@"Enable"] boolValue] ? @"off" :
            [traced objectForKey:@"Sequence"] != nil ? @"sequence" :
            [traced objectForKey:@"ScriptPath"] != nil ? @"script" :
            [traced objectForKey:@"OpenURL"] != nil ? @"url" :
            [traced objectForKey:@"PlaySound"] != nil ? @"sound" :
            [traced objectForKey:@"SpeakText"] != nil ? @"speech" :
            [[traced objectForKey:@"IsAction"] boolValue] ? @"built-in" : @"keystroke";
        MGTraceRecordDispatch(binding != nil ? gesture : doubleGesture,
                              scope, kind, @"suppressed-for-trace");
        return;
    }
    BOOL deferred = [[binding objectForKey:@"Defer"] boolValue];
    NSString *gestureKey = [NSString stringWithFormat:@"%d:%@", device, gesture];

    // One pending window per gesture serves both purposes. A deferred single
    // tap waits inside it, and a repeat inside it dispatches the double tap.
    // With only the double tap bound the window delays nothing, so the gesture
    // that is not configured costs no latency.
    if (deferred || doubleBinding != nil) {
        dispatch_block_t pending = deferred
            ? bindingAction(gesture, device, binding, matchedApplication, YES) : nil;
        dispatch_block_t repeated = doubleBinding == nil ? nil : ^{
            dispatchBindingNow(doubleGesture, device, doubleBinding, doubleApplication);
        };
        [deferredGestureDispatcher() handleGestureKey:gestureKey
                                                delay:[NSEvent doubleClickInterval]
                                               action:pending
                                               repeat:repeated];
        if (!deferred && binding != nil)
            dispatchBindingNow(gesture, device, binding, matchedApplication);
        return;
    }

    [deferredGestureDispatcher() cancelGestureKey:gestureKey];
    dispatchBindingNow(gesture, device, binding, matchedApplication);
}

// A tap whose only binding is its double tap is still worth recognizing: the
// double tap is reached by repeating the single tap and has no recognizer of
// its own.
static BOOL gestureIsBound(NSString *gesture, int device) {
    if (bindingForGesture(gesture, device) != nil)
        return YES;
    NSString *doubleGesture = [Config doubleTapGestureName:gesture];
    return doubleGesture != nil && bindingForGesture(doubleGesture, device) != nil;
}

// A bound recognizer owns its device's contact sequence before dispatch. The
// same recognizer may repeat, while competing gestures wait for a full lift.
static BOOL dispatchExclusiveCommand(NSString *gesture, int device, NSUInteger owner) {
    if (device == MAGICMOUSE && MGTraceAuditsGestureCatalog()) {
        MGTraceRecordCandidate(gesture, @"shadow-recognized", @"catalog-audit");
        return NO;
    }
    if (!gestureIsBound(gesture, device)) {
        if (device == MAGICMOUSE) MGTraceRecordCandidate(gesture, @"canceled", @"unconfigured");
        return NO;
    }
    NSUInteger previous = device == MAGICMOUSE ? magicMouseSequence.owner : trackpadInteraction.sequence.owner;
    BOOL claimed = device == TRACKPAD
        ? MGTrackpadInteractionClaimGesture(&trackpadInteraction, owner)
        : MGGestureSequenceTryClaim(&magicMouseSequence, owner);
    if (device == MAGICMOUSE) {
        MGTraceRecordCandidate(gesture, claimed ? @"recognized" : @"canceled",
                               claimed ? @"eligible" : @"owned-by-other-recognizer");
        MGTraceRecordOwnership(gestureOwnerName(owner), gestureOwnerName(previous),
                               gestureOwnerName(magicMouseSequence.owner), claimed);
    }
    if (claimed)
        dispatchCommand(gesture, device);
    return claimed;
}

static BOOL dispatchExclusiveTapCommand(NSString *gesture, int device, NSUInteger owner) {
    if (device == MAGICMOUSE && MGTraceAuditsGestureCatalog()) {
        MGTraceRecordCandidate(gesture, @"shadow-recognized", @"catalog-audit");
        return NO;
    }
    if (!gestureIsBound(gesture, device)) {
        if (device == MAGICMOUSE) MGTraceRecordCandidate(gesture, @"canceled", @"unconfigured");
        return NO;
    }
    NSUInteger previous = device == MAGICMOUSE ? magicMouseSequence.owner : trackpadInteraction.sequence.owner;
    BOOL claimed = device == TRACKPAD
        ? MGTrackpadInteractionClaimTap(&trackpadInteraction, owner)
        : MGGestureSequenceTryClaim(&magicMouseSequence, owner);
    if (device == MAGICMOUSE) {
        MGTraceRecordCandidate(gesture, claimed ? @"recognized" : @"canceled",
                               claimed ? @"eligible" : @"owned-by-other-recognizer");
        MGTraceRecordOwnership(gestureOwnerName(owner), gestureOwnerName(previous),
                               gestureOwnerName(magicMouseSequence.owner), claimed);
    }
    if (claimed)
        dispatchCommand(gesture, device);
    return claimed;
}

static BOOL dispatchExclusivePalmSafeCommand(NSString *gesture, int device, NSUInteger owner) {
    if (!gestureIsBound(gesture, device))
        return NO;
    BOOL claimed = device == TRACKPAD
        ? MGTrackpadInteractionClaimPalmSafeGesture(&trackpadInteraction, owner)
        : MGGestureSequenceTryClaim(&magicMouseSequence, owner);
    if (claimed)
        dispatchCommand(gesture, device);
    return claimed;
}

// A swipe family overlaps the device's own scrolling once it uses at least as
// many fingers as scrolling does, so every count at or above that one arms
// suppression rather than three alone. A directional lookup also answers for a
// bare family binding, which resolves through the same call.
static BOOL hasSwipeBindingForCount(NSString *countWord, int device) {
    for (NSString *direction in @[@"Left", @"Right", @"Up", @"Down"]) {
        NSString *gesture = [NSString stringWithFormat:@"%@-Swipe-%@", countWord, direction];
        if (commandForGesture(gesture, device) != nil)
            return YES;
    }
    return NO;
}

static BOOL hasThreeFingerSwipeBinding(int device) {
    return hasSwipeBindingForCount(@"Three", device);
}

// Arms scroll suppression for every swipe count this device recognizes that
// could be mistaken for its scrolling. A trackpad scrolls with two fingers, so
// three and four qualify; a Magic Mouse scrolls with one, so two and three do.
// One-finger mouse swipes keep their own suppression in their recognizer.
// Each family passes a resolver rather than a resolved answer, so the
// window-server round trip happens only on the frame where that family's
// contact count is actually present.
static void observeBoundSwipeFamilies(int device, int activeContactCount) {
    NSArray *counts = device == TRACKPAD ? @[@"Three", @"Four"] : @[@"Two", @"Three"];
    int required[2] = {device == TRACKPAD ? 3 : 2, device == TRACKPAD ? 4 : 3};
    // The count is logged on every change, not only when a family resolves. A
    // count that never reaches a family's requirement is precisely the case
    // that leaves the resolver silent, so it has to be visible on its own.
    static int lastObservedCount[2] = {-1, -1};
    if (logLevel >= LOG_LEVEL_DEBUG && device >= 0 && device < 2 &&
        activeContactCount != lastObservedCount[device]) {
        lastObservedCount[device] = activeContactCount;
        NSLog(@"Swipe family observation for %@: %d contacts (families need %d or %d)",
              deviceTypeName[device], activeContactCount, required[0], required[1]);
    }
    for (NSUInteger i = 0; i < [counts count]; i++) {
        NSString *count = counts[i];
        __block BOOL resolvedBound = NO;
        __block BOOL resolverRan = NO;
        BOOL (^resolveBinding)(void) = ^BOOL{
            resolverRan = YES;
            resolvedBound = hasSwipeBindingForCount(count, device);
            return resolvedBound;
        };
        if (device == TRACKPAD)
            MGTrackpadInteractionObserveBoundScrollFamily(&trackpadInteraction,
                activeContactCount, required[i], resolveBinding);
        else
            MGGestureSequenceObserveBoundScrollFamily(&magicMouseSequence,
                activeContactCount, required[i], resolveBinding);
        // The resolver runs only on the frame that decides a family, so its
        // having run is the signal worth reporting, and a bound one is the one
        // that armed suppression.
        if (logLevel >= LOG_LEVEL_DEBUG && resolverRan)
            NSLog(@"Swipe family %@ for %@ resolved at %d contacts: bound=%d",
                  count, deviceTypeName[device], activeContactCount, resolvedBound);
    }
}

static void dispatchMagicMousePhysicalClickForContactCount(int contactCount) {
    NSString *gesture = nil;
    if (contactCount == 2 && (MGTraceObservesUnconfiguredGesture(@"Two-Finger Click") ||
        bindingForGesture(@"Two-Finger Click", MAGICMOUSE) != nil))
        gesture = @"Two-Finger Click";
    else if (contactCount == 3 && (MGTraceObservesUnconfiguredGesture(@"Three-Finger Click") ||
        bindingForGesture(@"Three-Finger Click", MAGICMOUSE) != nil))
        gesture = @"Three-Finger Click";
    if (gesture != nil) {
        if (MGTraceAuditsGestureCatalog()) {
            MGTraceRecordCandidate(gesture, @"shadow-recognized", @"catalog-audit");
            return;
        }
        NSUInteger previous = magicMouseSequence.owner;
        BOOL claimed = MGGestureSequenceTryClaim(
            &magicMouseSequence, kGestureOwnerPhysicalClick);
        MGTraceRecordCandidate(gesture, claimed ? @"recognized" : @"canceled",
            claimed ? @"correlated-physical-click" : @"owned-by-other-recognizer");
        MGTraceRecordOwnership(@"physical-click", gestureOwnerName(previous),
            gestureOwnerName(magicMouseSequence.owner), claimed);
        if (!claimed) return;
        if (bindingForGesture(gesture, MAGICMOUSE) != nil)
            dispatchCommand(gesture, MAGICMOUSE);
        else
            MGTraceRecordDispatch(gesture, @"none", @"none", @"suppressed-for-trace");
    } else if (contactCount > 0) {
        MGTraceRecordCandidate(@"physical-click", @"canceled", @"unconfigured-contact-count");
    }
}


static void doCommand(NSString *gesture, int device, NSDictionary *commandDict,
                      NSString *matchedApplication) {
    CFTypeRef axui;
    NSArray *applications;
    if (device == CHARRECOGNITION) {
        axui = getForemostApp();
        applications = applicationCandidatesForGestureLookup();
    } else {
        axui = axuiUnderMouse();
        applications = applicationCandidatesForGestureLookup();
    }
    NSString *application = [applications count] > 0 ? [applications objectAtIndex:0] : nil;

    if (commandDict && [[commandDict objectForKey:@"Enable"] boolValue]) {
        NSString *resolvedCommand = [commandDict objectForKey:@"Command"];
        if (logLevel >= LOG_LEVEL_INFO) {
            NSLog(@"Resolved gesture \"%@\" for %@ candidates=%@ matched=%@ command=%@",
                  gesture,
                  deviceTypeName[device],
                  applications,
                  matchedApplication,
                  resolvedCommand);
        }
    }

    if (commandDict && [[commandDict objectForKey:@"Enable"] boolValue]) {
        CGFloat x, y;
        getMousePosition(&x, &y);
        if ([[commandDict objectForKey:@"IsAction"] boolValue]) {
            //action
            NSString *command = [commandDict objectForKey:@"Command"];
            if (logLevel >= LOG_LEVEL_DEBUG) NSLog(@"Command \"%@\" for application \"%@\"", command, application);

            NSArray *sequence = [commandDict objectForKey:@"Sequence"];
            if (sequence != nil) {
                [sequenceDispatcher() dispatchSequence:sequence
                                            stepHandler:^(NSDictionary *step) {
                    doCommand(gesture, device, step, matchedApplication);
                }];
            } else if ([command isEqualToString:@"-"]) {

            } else if ([command isEqualToString:@"Next Tab"]) {
                [keyUtil simulateKey:@"Tab" ShftDown:NO CtrlDown:YES AltDown:NO CmdDown:NO];
                //[keyUtil simulateKey:@"]" ShftDown:YES CtrlDown:NO AltDown:NO CmdDown:YES];
            } else if ([command isEqualToString:@"Previous Tab"]) {
                [keyUtil simulateKey:@"Tab" ShftDown:YES CtrlDown:YES AltDown:NO CmdDown:NO];
                //[keyUtil simulateKey:@"[" ShftDown:YES CtrlDown:NO AltDown:NO CmdDown:YES];
            } else if ([command isEqualToString:@"Open Link in New Tab"]) {
                CGEventRef ourEvent = CGEventCreate(NULL);
                CGPoint ourLoc = CGEventGetLocation(ourEvent);
                CFRelease(ourEvent);

                CGEventRef ev = CGEventCreateMouseEvent(NULL, kCGEventLeftMouseDown, ourLoc, kCGMouseButtonLeft);
                CGEventSetFlags(ev, kCGEventFlagMaskCommand);
                CGEventPost(kCGSessionEventTap, ev);
                CFRelease(ev);
                ev = CGEventCreateMouseEvent(NULL, kCGEventLeftMouseUp, ourLoc, kCGMouseButtonLeft);
                CGEventSetFlags(ev, kCGEventFlagMaskCommand);
                CGEventPost(kCGSessionEventTap, ev);
                CFRelease(ev);
            } else if ([command isEqualToString:@"Select Tab Above Cursor"]) {
                findTabGroup_lx = -99999;
                selectSafariTab();
            } else if ([command isEqualToString:@"Full Screen"]) {
                CFTypeRef tmpRef = nil;
                if (device != CHARRECOGNITION)
                    tmpRef = activateWindowAtPosition(x, y);
                if ([application isEqualToString:@"Terminal"]) {
                    [keyUtil simulateKey:@"F" ShftDown:NO CtrlDown:NO AltDown:YES CmdDown:YES];
                } else if ([application isEqualToString:@"Finder"]) {
                } else {
                    [keyUtil simulateKey:@"F" ShftDown:NO CtrlDown:YES AltDown:NO CmdDown:YES];
                }
                CFSafeRelease(tmpRef);
            } else if ([command isEqualToString:@"Open Recently Closed Tab"]) {
                if (![application isEqualToString:@"Safari"]) {
                    [keyUtil simulateKey:@"T" ShftDown:YES CtrlDown:NO AltDown:NO CmdDown:YES];
                } else {
                    [keyUtil simulateKey:@"Z" ShftDown:NO CtrlDown:NO AltDown:NO CmdDown:YES];
                }
            } else if ([command isEqualToString:@"Close / Close Tab"]) {
                CFTypeRef tmpRef = nil;
                if (device != CHARRECOGNITION)
                    tmpRef = activateWindowAtPosition(x, y);
                [keyUtil simulateKey:@"W" ShftDown:NO CtrlDown:NO AltDown:NO CmdDown:YES];
                CFSafeRelease(tmpRef);
            } else if ([command isEqualToString:@"Quit"]) {
                //if the user's using VMware/RDC, should we send cmd+q or alt+f4 ?
                if (![application isEqualToString:@"Finder"]) {
                    CFTypeRef tmpRef = nil;
                    if (device != CHARRECOGNITION)
                        tmpRef = activateWindowAtPosition(x, y);
                    [keyUtil simulateKey:@"Q" ShftDown:NO CtrlDown:NO AltDown:NO CmdDown:YES];
                    CFSafeRelease(tmpRef);
                } else {
                    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
                    NSDictionary *errorInfo;
                    NSAppleScript *appleScript = [[NSAppleScript alloc] initWithSource:@"tell application \"Finder\" to close every window"];
                    [appleScript executeAndReturnError:&errorInfo];
                    [appleScript release];
                    [pool release];
                }
            } else if ([command isEqualToString:@"Hide"]) {
                CFTypeRef tmpRef = nil;
                if (device != CHARRECOGNITION)
                    tmpRef = activateWindowAtPosition(x, y);
                [keyUtil simulateKey:@"H" ShftDown:NO CtrlDown:NO AltDown:NO CmdDown:YES];
                CFSafeRelease(tmpRef);
            } else if ([command isEqualToString:@"Minimize"]) {
                CFTypeRef tmpRef = nil;
                if (device != CHARRECOGNITION)
                    tmpRef = activateWindowAtPosition(x, y);
                minimizeForemostWindow();
                CFSafeRelease(tmpRef);
            } else if ([command isEqualToString:@"Zoom"]) {
                CFTypeRef tmpRef = nil;
                if (device != CHARRECOGNITION)
                    tmpRef = activateWindowAtPosition(x, y);
                maximizeForemostWindow();
                CFSafeRelease(tmpRef);
            } else if ([command isEqualToString:@"Un-Maximize"]) {
                CFTypeRef tmpRef = getForemostApp();
                maximizeWindow(tmpRef, 0);
                CFSafeRelease(tmpRef);
            } else if ([command isEqualToString:@"Maximize"]) {
                CFTypeRef tmpRef = getForemostApp();
                maximizeWindow(tmpRef, 1);
                CFSafeRelease(tmpRef);
            } else if ([command isEqualToString:@"Maximize Left"]) {
                CFTypeRef tmpRef = getForemostApp();
                maximizeWindow(tmpRef, 2);
                CFSafeRelease(tmpRef);
            } else if ([command isEqualToString:@"Maximize Right"]) {
                CFTypeRef tmpRef = getForemostApp();
                maximizeWindow(tmpRef, 3);
                CFSafeRelease(tmpRef);
            } else if ([command isEqualToString:@"Copy"]) {
                [keyUtil simulateKey:@"C" ShftDown:NO CtrlDown:NO AltDown:NO CmdDown:YES];
            } else if ([command isEqualToString:@"Paste"]) {
                [keyUtil simulateKey:@"V" ShftDown:NO CtrlDown:NO AltDown:NO CmdDown:YES];
            } else if ([command isEqualToString:@"New"]) {
                [keyUtil simulateKey:@"N" ShftDown:NO CtrlDown:NO AltDown:NO CmdDown:YES];
            } else if ([command isEqualToString:@"New Tab"]) {
                [keyUtil simulateKey:@"T" ShftDown:NO CtrlDown:NO AltDown:NO CmdDown:YES];
            } else if ([command isEqualToString:@"Open"]) {
                [keyUtil simulateKey:@"O" ShftDown:NO CtrlDown:NO AltDown:NO CmdDown:YES];
            } else if ([command isEqualToString:@"Save"]) {
                [keyUtil simulateKey:@"S" ShftDown:NO CtrlDown:NO AltDown:NO CmdDown:YES];
            } else if ([command isEqualToString:@"Launch Finder"]) {
                NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
                [[NSWorkspace sharedWorkspace] launchApplication:@"Finder"];
                [pool release];
            } else if ([command isEqualToString:@"Launch Browser"]) {
                NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
                CFStringRef tmp = LSCopyDefaultHandlerForURLScheme(CFSTR("http"));
                if (tmp) {
                    NSString *defaultBrowser = (NSString*)tmp;
                    if (![[NSWorkspace sharedWorkspace] launchAppWithBundleIdentifier:defaultBrowser
                                                                              options:NSWorkspaceLaunchDefault
                                                       additionalEventParamDescriptor:nil
                                                                     launchIdentifier:NULL]) {
                        [[NSWorkspace sharedWorkspace] launchApplication:@"Safari"];
                    }
                    CFRelease(tmp);
                } else {
                    [[NSWorkspace sharedWorkspace] launchApplication:@"Safari"];
                }
                [pool release];
            } else if ([command isEqualToString:@"Middle Click"]) {
                CGEventRef eventRef;

                CGEventRef ourEvent = CGEventCreate(NULL);
                CGPoint location = CGEventGetLocation(ourEvent);
                CFRelease(ourEvent);

                eventRef = CGEventCreateMouseEvent(NULL, kCGEventOtherMouseDown, location, kCGMouseButtonCenter);
                CGEventSetIntegerValueField(eventRef, kCGMouseEventButtonNumber, 2);
                CGEventPost(kCGSessionEventTap, eventRef);
                CFRelease(eventRef);

                eventRef = CGEventCreateMouseEvent(NULL, kCGEventOtherMouseUp, location, kCGMouseButtonCenter);
                //CGEventSetIntegerValueField(eventRef, kCGMouseEventButtonNumber, 2);
                CGEventPost(kCGSessionEventTap, eventRef);
                CFRelease(eventRef);
            } else if ([command isEqualToString:@"Show Desktop"]) {
                CoreDockSendNotification(@"com.apple.showdesktop.awake", 0);
            } /*else if ([command isEqualToString:@"Spaces"]) {
                CoreDockSendNotification(@"com.apple.workspaces.awake", 0);
            } */
            else if ([command isEqualToString:@"Application Windows"]) {
                CoreDockSendNotification(@"com.apple.expose.front.awake", 0);
            } else if ([command isEqualToString:@"Mission Control"]) {
                CoreDockSendNotification(@"com.apple.expose.awake", 0);
            } else if ([command isEqualToString:@"Launchpad"]) {
                CoreDockSendNotification(@"com.apple.launchpad.toggle", 0);
            } else if ([command isEqualToString:@"Dashboard"]) {
                NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
                [[NSWorkspace sharedWorkspace] launchApplication:@"Dashboard"];
                [pool release];
            } else if ([command isEqualToString:@"Left Click"]) {
                CGEventRef ourEvent = CGEventCreate(NULL);
                CGPoint location = CGEventGetLocation(ourEvent);
                CFRelease(ourEvent);
                postSyntheticMouseClick(kCGEventLeftMouseDown,
                                        kCGEventLeftMouseUp,
                                        kCGMouseButtonLeft,
                                        0,
                                        location,
                                        kCGSessionEventTap);
            } else if ([command isEqualToString:@"Right Click"]) {
                CGEventRef ourEvent = CGEventCreate(NULL);
                CGPoint location = CGEventGetLocation(ourEvent);
                CFRelease(ourEvent);
                BOOL handledByAX = showContextMenuUnderMouse();
                if (logLevel >= LOG_LEVEL_INFO) {
                    NSLog(@"Right Click handledByAX=%d", handledByAX ? 1 : 0);
                }
                if (!handledByAX) {
                    CFTypeRef tmpRef = nil;
                    if (device != CHARRECOGNITION) {
                        tmpRef = activateWindowAtPosition(x, y);
                    }
                    // Control-click maps to the native contextual-menu path in
                    // Finder, Chrome, and most AppKit views more reliably than
                    // an injected secondary-button event.
                    postSyntheticMouseMove(location, kCGHIDEventTap);
                    usleep(6000);
                    postSyntheticMouseClickWithFlags(kCGEventLeftMouseDown,
                                                     kCGEventLeftMouseUp,
                                                     kCGMouseButtonLeft,
                                                     0,
                                                     location,
                                                     kCGHIDEventTap,
                                                     kCGEventFlagMaskControl);
                    if (logLevel >= LOG_LEVEL_INFO) {
                        NSLog(@"Right Click fallback=ControlLeftClick");
                    }
                    CFSafeRelease(tmpRef);
                }
            } else if ([command isEqualToString:@"Refresh"]) {
                CFTypeRef tmpRef = nil;
                if (device != CHARRECOGNITION)
                    tmpRef = activateWindowAtPosition(x, y);
                if ([application isEqualToString:@"Mail"]) {
                    [keyUtil simulateKey:@"N" ShftDown:YES CtrlDown:NO AltDown:NO CmdDown:YES];
                } else if ([application isEqualToString:@"Preview"] || [application isEqualToString:@"iChat"]) {
                } else {
                    [keyUtil simulateKey:@"R" ShftDown:NO CtrlDown:NO AltDown:NO CmdDown:YES];
                }
                CFSafeRelease(tmpRef);
            } else if ([command isEqualToString:@"Scroll to Top"]) {
                CFTypeRef tmpRef = nil;
                if (device != CHARRECOGNITION)
                    tmpRef = activateWindowAtPosition(x, y);
                if ([application isEqualToString:@"Microsoft Word"])
                    [keyUtil simulateKey:@"Home" ShftDown:NO CtrlDown:NO AltDown:NO CmdDown:YES];
                else
                    [keyUtil simulateKey:@"Home" ShftDown:NO CtrlDown:NO AltDown:NO CmdDown:NO];
                CFSafeRelease(tmpRef);
            } else if ([command isEqualToString:@"Scroll to Bottom"]) {
                CFTypeRef tmpRef = nil;
                if (device != CHARRECOGNITION)
                    tmpRef = activateWindowAtPosition(x, y);
                if ([application isEqualToString:@"Microsoft Word"])
                    [keyUtil simulateKey:@"End" ShftDown:NO CtrlDown:NO AltDown:NO CmdDown:YES];
                else
                    [keyUtil simulateKey:@"End" ShftDown:NO CtrlDown:NO AltDown:NO CmdDown:NO];
                CFSafeRelease(tmpRef);
            } else if ([command isEqualToString:@"Application Switcher"]) {
                CoreDockSendNotification(@"com.apple.appswitcher.awake", 0);
            } else if ([command isEqualToString:@"Play / Pause"]) {
                [keyUtil simulateSpecialKey:NX_KEYTYPE_PLAY];
            } else if ([command isEqualToString:@"Next"]) {
                [keyUtil simulateSpecialKey:NX_KEYTYPE_NEXT];
            } else if ([command isEqualToString:@"Previous"]) {
                [keyUtil simulateSpecialKey:NX_KEYTYPE_PREVIOUS];
            } else if ([command isEqualToString:@"Volume Up"]) {
                [keyUtil simulateSpecialKey:NX_KEYTYPE_SOUND_UP];
            } else if ([command isEqualToString:@"Volume Down"]) {
                [keyUtil simulateSpecialKey:NX_KEYTYPE_SOUND_DOWN];
            } else if ([command isEqualToString:@"Brightness Up"]) {
                [keyUtil simulateSpecialKey:NX_KEYTYPE_BRIGHTNESS_UP];
            } else if ([command isEqualToString:@"Brightness Down"]) {
                [keyUtil simulateSpecialKey:NX_KEYTYPE_BRIGHTNESS_DOWN];
            } else {
                if ([commandDict objectForKey:@"OpenFilePath"]) {
                    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
                    NSString *openFilePath = [commandDict objectForKey:@"OpenFilePath"];
                    if ([[NSFileManager defaultManager] fileExistsAtPath:openFilePath]) {
                        NSString *extension = [openFilePath pathExtension];
                        if ([extension isEqualToString:@"scpt"] || [extension isEqualToString:@"scptd"]) {
                            NSString *script = [NSString stringWithFormat:@"osascript \"%@\"", [openFilePath stringByStandardizingPath]];
                            NSArray *shArgs = [NSArray arrayWithObjects:@"-c", script, @"", nil];
                            [NSTask launchedTaskWithLaunchPath:@"/bin/sh" arguments:shArgs];
                        } else {
                               [[NSWorkspace sharedWorkspace] openFile:openFilePath];
                           }
                    } else {
                        NSAlert *alert = [[NSAlert alloc] init];
                        [alert setMessageText:[NSString stringWithFormat:@"Can't open the file \"%@\"", openFilePath]];
                        //[alert setInformativeText:@""];
                        [alert setAlertStyle:NSWarningAlertStyle];
                        [NSApp activateIgnoringOtherApps:YES];
                        //[alert runModal];
                        [alert beginSheetModalForWindow:[(JitouchAppDelegate*)[NSApp delegate] window] completionHandler:nil]; //use non-modal
                        [alert release];
                    }
                    [pool release];
                } else if ([commandDict objectForKey:@"ScriptPath"]) {
                    NSString *scriptPath = [commandDict objectForKey:@"ScriptPath"];
                    NSError *error = nil;
                    if (![ScriptRunner launchScriptAtPath:scriptPath
                                                    error:&error
                                       terminationHandler:nil])
                        NSLog(@"Could not launch configured script \"%@\": %@",
                              scriptPath, [error localizedDescription]);
                } else if ([commandDict objectForKey:@"PlaySound"]) {
                    // NSSound is AppKit, and playback must not hold the
                    // dispatch thread, so the main queue starts it and returns.
                    playSystemSound([commandDict objectForKey:@"PlaySound"]);
                } else if ([commandDict objectForKey:@"SpeakText"]) {
                    speakText([commandDict objectForKey:@"SpeakText"], nil);
                } else if ([commandDict objectForKey:@"OpenURL"]) {
                    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
                    NSString *configuredURL = [commandDict objectForKey:@"OpenURL"];
                    NSString *clipboard = [[NSPasteboard generalPasteboard] stringForType:NSPasteboardTypeString];
                    NSString *problem = nil;
                    NSString *urlString = [Config URLByResolvingSubstitutions:configuredURL
                                                                    clipboard:clipboard
                                                                         date:[NSDate date]
                                                                      problem:&problem];
                    if (urlString == nil) {
                        // The expanded value may contain private clipboard text,
                        // so log only the configured URL binding and its problem.
                        NSLog(@"Could not resolve configured URL \"%@\": %@", configuredURL, problem);
                    } else if (![[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:urlString]]) {
                        NSLog(@"Could not open configured URL \"%@\": no application accepted it", configuredURL);
                    }
                    [pool release];
                }
            }
        } else {
            // shortcut
            CFTypeRef tmpRef = nil;
            if (device != CHARRECOGNITION)
                tmpRef = activateWindowAtPosition(x, y);

            NSUInteger modifierFlags = [[commandDict objectForKey:@"ModifierFlags"] unsignedIntegerValue];
            if (logLevel >= LOG_LEVEL_DEBUG) NSLog(@"Key \"%@%@%@%@%@\" for application \"%@\"",
                                                   (modifierFlags & kCGEventFlagMaskShift)? @"⇧" : @"",
                                                   (modifierFlags & kCGEventFlagMaskControl)? @"⌃" : @"",
                                                   (modifierFlags & kCGEventFlagMaskAlternate)? @"⌥ " : @"",
                                                   (modifierFlags & kCGEventFlagMaskCommand)? @"⌘ " : @"",
                                                   [KeyUtility codeToChar:(CGKeyCode)[[commandDict objectForKey:@"KeyCode"] unsignedIntValue]],
                                                   application);
            [keyUtil simulateKeyCode:[[commandDict objectForKey:@"KeyCode"] unsignedShortValue]
                       ModifierFlags:modifierFlags];
            CFSafeRelease(tmpRef);

        }
    }

    CFSafeRelease(axui);
}

static void setCursorWindowAtMouse() {
    CGEventRef ourEvent = CGEventCreate(NULL);
    CGPoint location = CGEventGetUnflippedLocation(ourEvent);
    CFRelease(ourEvent);
    [cursorWindow setFrameOrigin:NSMakePoint(location.x - 31, location.y - 29)];
}


#pragma mark - Trackpad

static void gestureTrackpadChangeSpace(const Finger *data, int nFingers) {
    static int step = 0;
    static float fing[3][2];
    // Min id
    static int mini;
    static int move = 0;
    static float last[2];
    if (step == 0 && nFingers == 2) {
        if (lenSqrF(data, 0, 1) < 0.1) {
            step = 1;
        }
    } else if (step == 1) {
        if (nFingers == 2 && lenSqrF(data, 0, 1) >= 0.1) {
            step = 0;
        } else if (nFingers == 3) {
            mini = 0;
            for (int i = 0; i < 3; i++) {
                fing[i][0] = data[i].px;
                fing[i][1] = data[i].py;
                if (fing[i][0] + fing[i][1] < fing[mini][0] + fing[mini][1]) {
                    mini = i;
                }
            }
            step = 2;
            move = 0;
        }
    } else if (step == 2) {
        if (nFingers != 3) {
            step = 0;
        } else {
            for (int i = 0; i < 3; i++) {
                if (i != mini && lenSqr(data[i].px, data[i].py, fing[i][0], fing[i][1]) > 0.001) {
                    step = 0;
                }
            }
            if (!move) {
                if (lenSqr(data[mini].px, data[mini].py, fing[mini][0], fing[mini][1]) > 0.001) {
                    move = 1;
                    last[0] = fing[mini][0];
                    last[1] = fing[mini][1];
                }
            } else {

                if (
                    (
                     lenSqr(data[mini].px, data[mini].py, last[0], last[1]) < 0.000001 ||
                     data[mini].state == MTTouchStateBreakTouch
                    ) &&
                    (
                     fabs(data[mini].px - fing[mini][0]) >= 0.07 * charRegIndexRingDistance / 0.33 ||
                     fabs(data[mini].py - fing[mini][1]) >= 0.08 * charRegIndexRingDistance / 0.33
                    )
                ) {
                    float dx = fabs(fing[mini][0] - data[mini].px), dy = fabs(fing[mini][1] - data[mini].py);
                    if (dx > dy) {
                        if (fing[mini][0] < data[mini].px)
                            dispatchExclusiveCommand(@"Two-Fix One-Slide-Right", TRACKPAD, kGestureOwnerTwoFixedOneSlide);
                        else
                            dispatchExclusiveCommand(@"Two-Fix One-Slide-Left", TRACKPAD, kGestureOwnerTwoFixedOneSlide);
                    } else {
                        if (fing[mini][1] < data[mini].py)
                            dispatchExclusiveCommand(@"Two-Fix One-Slide-Up", TRACKPAD, kGestureOwnerTwoFixedOneSlide);
                        else
                            dispatchExclusiveCommand(@"Two-Fix One-Slide-Down", TRACKPAD, kGestureOwnerTwoFixedOneSlide);
                    }
                    move = 0;
                    fing[mini][0] = data[mini].px;
                    fing[mini][1] = data[mini].py;
                }
                last[0] = data[mini].px;
                last[1] = data[mini].py;
            }

        }
    }
}


static void gestureTrackpadTab4(const Finger *data, int nFingers, double timestamp, int dir) {
    static double sttime[2] = {-1, -1};
    static int lastNFingers[2] = {0};
    static float avgX[2], avgY[2];
    float avgX2, avgY2;
    static int step[2];
    if (fourFingerTapTriggered)
        step[dir] = 0;
    if (step[dir] == 0) {
        if (nFingers == 1) {
            sttime[dir] = timestamp;
            step[dir] = 1;
            avgX[dir] = data[0].px;
            avgY[dir] = data[0].py;
            lastNFingers[dir] = 1;
        }
    } else if (step[dir] == 4) {
        if (timestamp - sttime[dir] > clickSpeed)
            step[dir] = 0;
        if (nFingers == 4) {
            avgX2 = avgY2 = 0;
            for (int i = 0; i < nFingers; i++) {
                avgX2 += data[i].px;
                avgY2 += data[i].py;
            }
            avgX2 /= nFingers;
            avgY2 /= nFingers;
            if (fabs(avgX2+avgY2 - avgX[dir] - avgY[dir]) > 0.1)
                step[dir] = 0;
        } else if (nFingers > 4)
            step[dir] = 0;
        else if (nFingers == 0) {
            trackpadTab4Triggered = TRUE;
            if (dir == 1) {
                dispatchExclusiveTapCommand(@"Pinky-To-Index", TRACKPAD, kGestureOwnerSequentialFourFingerTap);
            } else{
                dispatchExclusiveTapCommand(@"Index-To-Pinky", TRACKPAD, kGestureOwnerSequentialFourFingerTap);
            }
            step[dir] = 0;
        }

    } else if (step[dir] >= 1) {
        if (timestamp - sttime[dir] > clickSpeed) // decreased
            step[dir] = 0;
        if (nFingers == lastNFingers[dir] + 1) {
            avgX2 = avgY2 = 0;
            for (int i = 0; i < nFingers; i++) {
                avgX2 += data[i].px;
                avgY2 += data[i].py;
            }
            avgX2 /= nFingers;
            avgY2 /= nFingers;
            if (dir ^ (avgX2 + avgY2 > avgX[dir] + avgY[dir])) {
                step[dir]++;
                avgX[dir] = avgX2;
                avgY[dir] = avgY2;
                sttime[dir] = timestamp;
            }
        } else if (nFingers < lastNFingers[dir])
            step[dir] = 0;
        lastNFingers[dir] = nFingers;
    }
    trackpadTab4Step[dir] = step[dir];
}


static void gestureTrackpadFourFingerTap(const Finger *data, int nFingers, double timestamp) {
    static double sttime = -1;
    static int step = 0;
    static double fing[4][2];
    static double fourFingerTapTime;
    fourFingerTapTriggered = FALSE;
    if (nFingers > 4)
        step = 2;
    else if (trackpadTab4Triggered) {
        step = 0;
        sttime = -1;
    }
    else if (step == 0 && nFingers == 4) {
        if (!trackpadContactsArrivedTogether(
                data, 4, kTrackpadSimultaneousTapMaximumOnsetSpread)) {
            step = 2;
            return;
        }
        if (sttime == -1) {
            sttime = timestamp;
            step = 1;
            trackpadClicked = 0;
            for (int i = 0; i < 4; i++) {
                fing[i][0] = data[i].px;
                fing[i][1] = data[i].py;
            }
        }
    } else if (step == 1) {
        if (nFingers <= 1) {
            if (sttime != -1 && timestamp-sttime <= clickSpeed) {
                if (trackpadTab4Step[0] == 4 || trackpadTab4Step[1] == 4) {
                    // dispatch only if TrackpadTab4 is not triggered from the same gesture
                    fourFingerTapTime = timestamp;
                    step = 3;
                }
                else if (!trackpadClicked) {
                    dispatchExclusiveTapCommand(@"Four-Finger Tap", TRACKPAD, kGestureOwnerFourFingerTap);
                    step = 0;
                    sttime = -1;
                }
            } else {
                step = 0;
                sttime = -1;
            }
        } else if (nFingers == 4) {
            if (lenSqr(fing[0][0], fing[0][1], data[0].px, data[0].py) > 0.001 ||
               lenSqr(fing[1][0], fing[1][1], data[1].px, data[1].py) > 0.001 ||
               lenSqr(fing[2][0], fing[2][1], data[2].px, data[2].py) > 0.001 ||
               lenSqr(fing[3][0], fing[3][1], data[3].px, data[3].py) > 0.001 ) {
                step = 2;
            }
        }
    } else if (step == 2 && nFingers <= 1) {
        step = 0;
        sttime  = -1;
    } else if (step == 3) {
        if ((trackpadTab4Step[0] != 4 && trackpadTab4Step[1] != 4) ||
            timestamp-fourFingerTapTime > clickSpeed/2) {
            if (!trackpadClicked)
                dispatchExclusiveTapCommand(@"Four-Finger Tap", TRACKPAD, kGestureOwnerFourFingerTap);
            fourFingerTapTriggered = TRUE;
            step = 0;
            sttime = -1;
        }
    }
}

static void gestureTrackpadFiveFingerTap(const Finger *data, int nFingers,
                                         BOOL eligible, double timestamp) {
    static MGContactTapRecognizer recognizer = {0};
    if (recognizer.targetCount == 0)
        MGContactTapRecognizerInitialize(&recognizer, 5);

    float centroidX = 0;
    float centroidY = 0;
    for (int i = 0; i < nFingers; i++) {
        centroidX += data[i].px;
        centroidY += data[i].py;
    }
    if (nFingers > 0) {
        centroidX /= nFingers;
        centroidY /= nFingers;
    }

    if (MGContactTapRecognizerUpdate(&recognizer, nFingers, centroidX, centroidY,
                                     eligible, timestamp))
        dispatchExclusiveTapCommand(@"Five-Finger Tap", TRACKPAD, kGestureOwnerFiveFingerTap);
}


// TODO: clicking (not just tapping) should return to the normal mode
static int gestureTrackpadMoveResize(const Finger *data, int nFingers, double timestamp) {
    static int step = 0, step2, min;
    static float fing[2][2], fing2[2][2];
    static double sttime = -1;
    static int type = 0;
    static CFTypeRef cWindow = nil;
    static CGFloat baseX, baseY, appX, appY;
    static char firstTime;

    if (type) {
        if (step2 == 0) {
            if (firstTime) {
                getMousePosition(&baseX, &baseY);
                dispatch_async(dispatch_get_main_queue(), ^{
                    @autoreleasepool {
                        [cursorWindow orderOut:nil];
                    }
                });
                if (cWindow == nil)
                    cWindow = activateWindowAtPosition(baseX, baseY);

                if (cWindow == NULL) {
                    type = 0;
                } else {
                    getWindowPos(cWindow, &appX, &appY);

                    cursorImageType = type - 1;
                    dispatch_async(dispatch_get_main_queue(), ^{
                        @autoreleasepool {
                            [cursorWindow display];
                            [[cursorWindow contentView] setNeedsDisplay:YES];
                            setCursorWindowAtMouse();
                            [cursorWindow setLevel:NSScreenSaverWindowLevel];
                            [cursorWindow makeKeyAndOrderFront:nil];
                        }
                    });

                    moveResizeFlag = 1;
                }
            }
            firstTime = 0;
            if (nFingers == 1) {
                sttime = -1;
                step2 = 1;
            }
        } else if (step2 == 1) {
            if (nFingers == 1 && !shouldExitMoveResize) {
                CGFloat x, y;
                getMousePosition(&x, &y);
                dispatch_async(dispatch_get_main_queue(), ^{
                    @autoreleasepool {
                        setCursorWindowAtMouse();
                    }
                });
                if (type == 1) {
                    setWindowPos2(cWindow, x, y, baseX, baseY, appX, appY);
                } else if (type == 2) {
                    if (!setWindowSize2(cWindow, x, y, baseX, baseY)) {
                        type = 0;
                        dispatch_async(dispatch_get_main_queue(), ^{
                            @autoreleasepool {
                                [cursorWindow orderOut:nil];
                            }
                        });
                        CFSafeRelease(cWindow);
                        cWindow = nil;

                        moveResizeFlag = 0;
                        //CGEventTapEnable(eventClick, false);
                    } else {
                        float nx = x, ny = y;
                        if (x >= appX + 3)
                            baseX = x;
                        else
                            nx = appX + 3;
                        if (y >= appY + 3)
                            baseY = y;
                        else
                            ny = appY + 3;
                        if (nx != x || ny != y) {
                            mouseClick(8, nx, ny);
                        }
                    }
                }
                if (sttime == -1) {
                    sttime = timestamp;
                    fing[0][0] = data[0].px;
                    fing[0][1] = data[0].py;
                }
                if (fing[0][0] != -1 && lenSqr(fing[0][0], fing[0][1], data[0].px, data[0].py) >= 0.001)
                    sttime = 0;

            } else if (nFingers == 2 && data[0].size >= 0.1 && data[1].size >= 0.1) {
                sttime = timestamp;
                step2 = 2;
                fing2[0][0] = data[0].px;
                fing2[0][1] = data[0].py;
                fing2[1][0] = data[1].px;
                fing2[1][1] = data[1].py;

            } else if ((nFingers == 0 && timestamp-sttime <= clickSpeed) || shouldExitMoveResize) { // tap or click to exit
                type = 0;
                CFSafeRelease(cWindow);
                cWindow = nil;
                dispatch_async(dispatch_get_main_queue(), ^{
                    @autoreleasepool {
                        [cursorWindow orderOut:nil];
                    }
                });

                moveResizeFlag = 0;
                //CGEventTapEnable(eventClick, false);

                shouldExitMoveResize = 0;
            } else if (nFingers == 0)
                sttime = -1;
        } else if (step2 == 2) {
            if (nFingers >= 3 ||
               timestamp - sttime > clickSpeed ||
               lenSqr(fing2[0][0], fing2[0][1], data[0].px, data[0].py) > 0.001 ||
               lenSqr(fing2[1][0], fing2[1][1], data[1].px, data[1].py) > 0.001
               ) {
                step2 = 3;
            }
            if (nFingers == 1) {
                firstTime = 1;
                step2 = 0;
                type = (type == 1) ? 2 : 1;
            }
        } else if (step2 == 3 && nFingers == 1) {
            step2 = 0;
        }
    }
    if (step == 0 && nFingers == 1) {
        step = 1;
    } else if (step == 1) {
        if (nFingers == 2) {
            if (lenSqr(data[0].px, data[0].py, data[1].px, data[1].py) > 0.2)
                step = 0;
            else {
                min = 0;
                if (data[1].px+data[1].py<data[min].px+data[min].py)
                    min = 1;
                fing[0][0] = data[min].px;
                fing[0][1] = data[min].py;
                fing[1][0] = data[!min].px;
                fing[1][1] = data[!min].py;
                step = 2;
                sttime = timestamp;
            }
        } else if (nFingers == 3)
            step = 0;
    } else if (step == 2) {
        if (nFingers != 2 || timestamp- sttime > clickSpeed * 2)
            step = 0;
        else {
            if (lenSqr(fing[0][0], fing[0][1], data[min].px, data[min].py) > 0.0001
               || CGEventSourceButtonState(kCGEventSourceStateHIDSystemState, kCGMouseButtonLeft)) {
                step = 0;
            }

            if (data[!min].px > data[min].px && lenSqr(data[!min].px, data[!min].py, fing[1][0], fing[1][1]) >= 0.012) {

                // Intensive calculation - please keep to minimum :p
                float v[3][2], tmp;

                v[1][0] = data[!min].px - fing[1][0];
                v[1][1] = data[!min].py - fing[1][1];
                tmp = sqrt(v[1][0]*v[1][0] + v[1][1]*v[1][1]);
                if (tmp == 0) tmp = 1e-10;
                v[1][0] /= tmp;
                v[1][1] /= tmp;

                v[2][0] = data[!min].px - fing[0][0];
                v[2][1] = data[!min].py - fing[0][1];
                tmp = sqrt(v[2][0]*v[2][0] + v[2][1]*v[2][1]);
                if (tmp == 0) tmp = 1e-10;
                v[2][0] /= tmp;
                v[2][1] /= tmp;

                // Dot product
                if (fabs(v[2][0]*v[1][0] + v[2][1]*v[1][1]) <= 0.8) {
                    sttime = timestamp;
                    step2 = step = 0;
                    firstTime = 1;

                    if (type) {
                        type = 0;
                        CFSafeRelease(cWindow);
                        cWindow = nil;
                        dispatch_async(dispatch_get_main_queue(), ^{
                            @autoreleasepool {
                                [cursorWindow orderOut:nil];
                            }
                        });

                        moveResizeFlag = 0;
                    } else if (data[!min].py < fing[1][1]) {
                        if ([commandForGesture(@"One-Fix One-Slide", TRACKPAD) isEqualToString:@"Move / Resize"] && !isMouseOnEmptySpace())
                            type = 1;
                    } else {
                        if ([commandForGesture(@"One-Fix One-Slide", TRACKPAD) isEqualToString:@"Move / Resize"] && !isMouseOnEmptySpace())
                            type = 2;
                    }
                } else
                    step = 0;
            }
        }
    }

    return type || step >= 3;
}


static void gestureTrackpadOneFixTwoSlide(const Finger *data, int nFingers, double timestamp) {
    static int ena = 0, min;
    static int find[3], findc;
    static float avgy, avgx;
    static double waitFor4;
    static int reset = 0;
    static int lastNFingers;
    static CGFloat fixX, fixY;
    static float fing[3][2];
    if (!reset && (nFingers >= 3 && nFingers <= 4)) {
        if (lastNFingers != nFingers)
            ena = 0;
        if (!ena) {
            min = 0;
            for (int i = 0; i < nFingers; i++) {
                if (data[i].px+data[i].py<data[min].px+data[min].py)
                    min = i;
            }
            fixX = data[min].px;
            fixY = data[min].py;
            findc = 0;
            avgy = 0;
            avgx = 0;
            for (int i = 0; i < nFingers; i++)
                if (min != i) {
                    fing[findc][0] = data[i].px;
                    fing[findc][1] = data[i].py;
                    find[findc++] = i;
                    avgx += data[i].px;
                    avgy += data[i].py;
                }
            avgx /= findc;
            avgy /= findc;
            if (nFingers == 3) {
                if (fabs(fixX - avgx) >= 0.35)
                    waitFor4 = timestamp;
                else
                    waitFor4 = -1;
            } else if (nFingers == 4) {
                if (fabs(fixX - avgx) >= 0.45)
                    reset = 1;
                else
                    waitFor4 = -1;
            }
            ena = 1;
        } else {
            if (waitFor4 != -1 && timestamp - waitFor4 > clickSpeed)
                reset = 1;
            double avgx2 = 0, avgy2 = 0;
            for (int i = 0; i < findc; i++) {
                avgx2 += data[find[i]].px;
                avgy2 += data[find[i]].py;
            }
            avgx2 /= findc;
            avgy2 /= findc;

            if (lenSqr(fixX, fixY, data[min].px, data[min].py) > 0.001) {
                reset = 1;
            } else {
                // Reuse variables
                if (nFingers == 3 && waitFor4 == -1 &&
                   lenSqr(avgx, avgy, avgx2, avgy2) >= 0.018 &&
                   lenSqr(data[find[0]].px, data[find[0]].py, fing[0][0], fing[0][1]) >= 0.01 &&
                   lenSqr(data[find[1]].px, data[find[1]].py, fing[1][0], fing[1][1]) >= 0.01) {
                    getMousePosition(&fixX, &fixY);
                    CFTypeRef tmpRef = activateWindowAtPosition(fixX, fixY);
                    CFSafeRelease(tmpRef);

                    if (CGEventSourceButtonState(kCGEventSourceStateHIDSystemState, kCGMouseButtonLeft)) {
                        if (avgy2 > avgy) { //one fix two slide up
                            dispatchExclusivePalmSafeCommand(@"One-Fix-Press Two-Slide-Up", TRACKPAD, kGestureOwnerOneFixedTwoSlide);
                        } else { //one fix two slide down
                            dispatchExclusivePalmSafeCommand(@"One-Fix-Press Two-Slide-Down", TRACKPAD, kGestureOwnerOneFixedTwoSlide);
                        }

                        CGEventRef eventRef;

                        CGEventRef ourEvent = CGEventCreate(NULL);
                        CGPoint location = CGEventGetLocation(ourEvent);
                        CFRelease(ourEvent);

                        eventRef = CGEventCreateMouseEvent(NULL, kCGEventLeftMouseUp, location, kCGMouseButtonLeft);
                        CGEventSetIntegerValueField(eventRef, kCGMouseEventButtonNumber, 0);
                        CGEventPost(kCGSessionEventTap, eventRef);
                        CFRelease(eventRef);
                    } else {
                        if (avgy2 > avgy) { //one fix two slide up
                            dispatchExclusivePalmSafeCommand(@"One-Fix Two-Slide-Up", TRACKPAD, kGestureOwnerOneFixedTwoSlide);
                        } else { //one fix two slide down
                            dispatchExclusivePalmSafeCommand(@"One-Fix Two-Slide-Down", TRACKPAD, kGestureOwnerOneFixedTwoSlide);
                        }
                    }

                    reset = 1;
                }

                //No longer works in Snow Leopard
                /*
                if (nFingers == 4 && //one fix three slide
                   lenSqr(avgx, avgy, avgx2, avgy2) >= 0.013) {
                    dispatchCommand(@"One-Fix Three-Slide", TRACKPAD);
                    reset = 1;
                }
                 */
            }
        }
        lastNFingers = nFingers;
    } else if (nFingers <= 1 || nFingers > 4) {
        ena = 0;
        reset = 0;
        lastNFingers = nFingers;
    }
}

static void gestureTrackpadThreeFingerTap(const Finger *data, int nFingers,
                                           BOOL contactsFormTapGroup,
                                           double timestamp) {
    static double sttime = -1;
    static int step = 0;
    static double fing[3][2];
    static double maxMovementSquared = 0;
    static int idf[3];
    if (nFingers > 3)
        step = 2;
    else if (step == 0 && nFingers == 3) {
        if (!contactsFormTapGroup) {
            step = 2;
            return;
        }
        if (!trackpadContactsArrivedTogether(
                data, 3, kTrackpadSimultaneousTapMaximumOnsetSpread)) {
            step = 2;
            return;
        }
        if (sttime == -1) {
            sttime = timestamp;
            step = 1;
            trackpadClicked = 0;
            maxMovementSquared = 0;
            for (int i = 0; i < 3; i++) {
                fing[i][0] = data[i].px;
                fing[i][1] = data[i].py;
            }
            idf[0] = 0;
            idf[2] = 2;
            for (int i = 0; i < 3; i++) {
                if (data[i].px + data[i].py < data[idf[0]].px + data[idf[0]].py)
                    idf[0] = i;
                if (data[i].px + data[i].py > data[idf[2]].px + data[idf[2]].py)
                    idf[2] = i;
            }
            idf[1] = 3 - idf[0] - idf[2];
            for (int i = 0; i < 3; i++)
                idf[i] = data[idf[i]].identifier;
        }
    } else if (step == 1) {
        if (nFingers <= 1) {
            if (sttime != -1 && timestamp-sttime <= clickSpeed) {
                if (!trackpadClicked)
                    dispatchExclusiveTapCommand(@"Three-Finger Tap", TRACKPAD, kGestureOwnerThreeFingerTap);
            }
            step = 0;
            sttime = -1;
        } else if (nFingers == 3) {
            for (int i = 0; i < 3; i++) {
                double movementSquared = lenSqr(fing[i][0], fing[i][1], data[i].px, data[i].py);
                if (movementSquared > maxMovementSquared)
                    maxMovementSquared = movementSquared;
            }
            if (maxMovementSquared > 0.001) {
                step = 2;
            }
        }
    } else if (step == 2 && nFingers <= 1) {
        step = 0;
        sttime  = -1;
    }
}

static void gestureTrackpadTwoFingerTap(const Finger *data, int nFingers,
                                         BOOL contactsFormTapGroup,
                                         double timestamp) {
    enum {
        kTrackpadTwoFingerTapIdle = 0,
        kTrackpadTwoFingerTapTracking = 1,
        kTrackpadTwoFingerTapWaitingForLift = 2,
        kTrackpadTwoFingerTapRejectedUntilLift = 3,
    };
    static int step = 0;
    static double startTime = -1;
    static int fingerIds[2];
    static float startx[2];
    static float starty[2];

    if (CGEventSourceButtonState(kCGEventSourceStateHIDSystemState, kCGMouseButtonLeft)) {
        step = kTrackpadTwoFingerTapRejectedUntilLift;
        startTime = -1;
        return;
    }

    if (nFingers >= 3 || (nFingers == 2 &&
                          (!contactsFormTapGroup ||
                           !trackpadContactsArrivedTogether(
                               data, 2, kTrackpadSimultaneousTapMaximumOnsetSpread)))) {
        step = kTrackpadTwoFingerTapRejectedUntilLift;
        startTime = -1;
    } else if (step == kTrackpadTwoFingerTapRejectedUntilLift) {
        if (nFingers == 0)
            step = kTrackpadTwoFingerTapIdle;
    } else if (step == kTrackpadTwoFingerTapIdle && nFingers == 2) {
        step = kTrackpadTwoFingerTapTracking;
        startTime = timestamp;
        for (int i = 0; i < 2; i++) {
            fingerIds[i] = data[i].identifier;
            startx[i] = data[i].px;
            starty[i] = data[i].py;
        }
    } else if (step == kTrackpadTwoFingerTapTracking || step == kTrackpadTwoFingerTapWaitingForLift) {
        BOOL valid = timestamp - startTime <= clickSpeed + 0.10;
        for (int i = 0; valid && i < nFingers; i++) {
            int matched = 0;
            for (int j = 0; j < 2; j++) {
                if (data[i].identifier == fingerIds[j]) {
                    if (lenSqr(data[i].px, data[i].py, startx[j], starty[j]) > 0.001)
                        valid = NO;
                    matched = 1;
                    break;
                }
            }
            if (!matched)
                valid = NO;
        }

        if (!valid) {
            step = kTrackpadTwoFingerTapRejectedUntilLift;
            startTime = -1;
        } else if (nFingers == 0) {
            dispatchExclusiveTapCommand(@"Two-Finger Tap", TRACKPAD, kGestureOwnerTwoFingerTap);
            step = kTrackpadTwoFingerTapIdle;
            startTime = -1;
        } else if (nFingers < 2) {
            step = kTrackpadTwoFingerTapWaitingForLift;
        } else if (timestamp - startTime > clickSpeed) {
            step = kTrackpadTwoFingerTapRejectedUntilLift;
            startTime = -1;
        }
    }
}

static void gestureTrackpadHoldSlide(const Finger *data, int nFingers) {
    enum {
        kTrackpadHoldSlideIdle = 0,
        kTrackpadHoldSlideHasAnchor = 1,
        kTrackpadHoldSlideTracking = 2,
        kTrackpadHoldSlideTriggeredUntilLift = 3,
    };
    static int step = 0;
    static int anchorId = -1;
    static int movingId = -1;
    static float anchorStartX = 0;
    static float anchorStartY = 0;
    static float movingStartX = 0;
    static float movingStartY = 0;

    if (nFingers == 0) {
        step = kTrackpadHoldSlideIdle;
        anchorId = -1;
        movingId = -1;
        return;
    }

    if (step == kTrackpadHoldSlideIdle && nFingers == 1) {
        step = kTrackpadHoldSlideHasAnchor;
        anchorId = data[0].identifier;
        anchorStartX = data[0].px;
        anchorStartY = data[0].py;
    } else if (step == kTrackpadHoldSlideHasAnchor && nFingers == 1) {
        if (data[0].identifier != anchorId ||
            lenSqr(data[0].px, data[0].py, anchorStartX, anchorStartY) > 0.001) {
            anchorId = data[0].identifier;
            anchorStartX = data[0].px;
            anchorStartY = data[0].py;
        }
    } else if (step == kTrackpadHoldSlideHasAnchor && nFingers == 2) {
        int anchorIndex = data[0].identifier == anchorId ? 0 :
                          data[1].identifier == anchorId ? 1 : -1;
        if (anchorIndex < 0) {
            step = kTrackpadHoldSlideIdle;
            return;
        }
        int movingIndex = 1 - anchorIndex;
        step = kTrackpadHoldSlideTracking;
        anchorStartX = data[anchorIndex].px;
        anchorStartY = data[anchorIndex].py;
        movingId = data[movingIndex].identifier;
        movingStartX = data[movingIndex].px;
        movingStartY = data[movingIndex].py;
    } else if (step == kTrackpadHoldSlideTracking && nFingers == 2) {
        int anchorIndex = data[0].identifier == anchorId ? 0 :
                          data[1].identifier == anchorId ? 1 : -1;
        int movingIndex = data[0].identifier == movingId ? 0 :
                          data[1].identifier == movingId ? 1 : -1;
        if (anchorIndex < 0 || movingIndex < 0 ||
            lenSqr(data[anchorIndex].px, data[anchorIndex].py, anchorStartX, anchorStartY) > 0.001) {
            step = kTrackpadHoldSlideTriggeredUntilLift;
            return;
        }
        if (lenSqr(data[movingIndex].px, data[movingIndex].py, movingStartX, movingStartY) >= 0.012) {
            dispatchExclusiveCommand(@"One-Fix One-Slide", TRACKPAD, kGestureOwnerHoldSlide);
            step = kTrackpadHoldSlideTriggeredUntilLift;
        }
    } else if (step == kTrackpadHoldSlideTracking && nFingers == 1) {
        step = kTrackpadHoldSlideHasAnchor;
        anchorId = data[0].identifier;
        anchorStartX = data[0].px;
        anchorStartY = data[0].py;
        movingId = -1;
    } else if (step != kTrackpadHoldSlideTriggeredUntilLift) {
        step = kTrackpadHoldSlideIdle;
    }
}

static void gestureTrackpadOneFixOneTap(const Finger *data, int nFingers, double timestamp) {
    static double sttime = -1;
    static float fing[2][2];
    static int step = 0;
    static double restTime = -1;
    static int fixId;
    static float avgx, avgy;
    static BOOL isLeftTap;

    if (nFingers == 0) {
        restTime = -1;
    }

    if (step == 0 && nFingers == 1) {
        step = 1;
        fixId = data[0].identifier;
        sttime = -1;
        if (restTime < 0)
            restTime = timestamp;
    } else if (step == 1) {
        if (nFingers == 2) {
            if (timestamp - restTime >= 0.06 &&
                (!enCharRegTP || fabs(data[0].px - data[1].px) <= charRegIndexRingDistance) &&
                MGTrackpadInteractionContactsFormHoldTapPair(
                    data[0].px, data[0].py, data[1].px, data[1].py)) {
                if (sttime < 0)
                    sttime = timestamp;
                if ((data[0].identifier == fixId || data[0].size > stvt / 10) &&
                   (data[1].identifier == fixId || data[1].size > stvt / 10)) {
                    step = 2;
                    avgx = (data[0].px + data[1].px) / 2;
                    avgy = (data[0].py + data[1].py) / 2;
                    fing[0][0] = data[0].px;
                    fing[0][1] = data[0].py;
                    fing[1][0] = data[1].px;
                    fing[1][1] = data[1].py;
                    int anchorIndex = data[0].identifier == fixId ? 0 : 1;
                    isLeftTap = enHanded ^ (avgy - data[anchorIndex].py < data[anchorIndex].px - avgx);
                }
            } else
                step = 0;
        } else if (nFingers == 1) {
            sttime = -1;
            fixId = data[0].identifier;
        } else
            step = 0;
    } else if (step == 2) {
        if (nFingers <= 1) {
            if (timestamp - sttime > clickSpeed) {
                step = 0;
            } else {
                BOOL anchorRemained = nFingers == 1 && data[0].identifier == fixId;
                if (anchorRemained) {
                    if (isLeftTap)
                        dispatchExclusiveTapCommand(@"One-Fix Left-Tap", TRACKPAD, kGestureOwnerHoldTap);
                    else
                        dispatchExclusiveTapCommand(@"One-Fix Right-Tap", TRACKPAD, kGestureOwnerHoldTap);
                }
            }
            step = 0;
        } else if (nFingers == 2) {
            if (lenSqr(data[0].px, data[0].py, fing[0][0], fing[0][1]) > 0.001 || lenSqr(data[1].px, data[1].py, fing[1][0], fing[1][1]) > 0.001)
                step = 0;
        } else {
            step = 0;
        }
    }
}


static void gestureTrackpadSwipeThreeFingers(const Finger *data, int nFingers) {
    static float startx[3], starty[3];
    static int lastNFingers;
    int step = 0;
    static int type = 0;
    static int l, r;

    if (lastNFingers != 3 && nFingers == 3) {
        step = 1;
    } else if (lastNFingers == 3 && nFingers == 3) {
        step = 2;
    } else if (lastNFingers == 3 && nFingers != 3) {
        step = 3;
    }

    if (step == 1) { //start three fingers
        l = 0; r = 0;
        for (int i = 0; i < nFingers; i++) {
            startx[i] = data[i].px;
            starty[i] = data[i].py;
            if (data[i].px+data[i].py < data[l].px+data[l].py) {
                l = i;
            } else if (data[i].px+data[i].py > data[r].px+data[r].py) {
                r = i;
            }
        }
        type = 0;
    } else if (step == 2) { //continue three fingers
        float sumx = 0.0f;
        float sumy = 0.0f;
        int moveDown = 0;
        int moveUp = 0;
        int moveLeft = 0;
        int moveRight = 0;
        for (int i = 0; i < nFingers; i++) {
            sumx += data[i].px - startx[i];
            sumy += data[i].py - starty[i];
            if (data[i].py - starty[i] < -0.08) moveDown++;
            else if (data[i].py - starty[i] > 0.08) moveUp++;
            if (data[i].px - startx[i] < -0.06) moveLeft++;
            else if (data[i].px - startx[i] > 0.06) moveRight++;
        }


        if (moveDown == 3 && type != 1) {
            if (sumy < -0.35) {
                type = 1;
                dispatchExclusiveCommand(@"Three-Swipe-Down", TRACKPAD, kGestureOwnerThreeFingerSwipe);
                for (int i = 0; i < nFingers; i++) {
                    startx[i] = data[i].px;
                    starty[i] = data[i].py;
                }
            }
        } else if (moveUp == 3 && type != 2) {
            if (sumy > 0.35) {
                type = 2;
                dispatchExclusiveCommand(@"Three-Swipe-Up", TRACKPAD, kGestureOwnerThreeFingerSwipe);
                for (int i = 0; i < nFingers; i++) {
                    startx[i] = data[i].px;
                    starty[i] = data[i].py;
                }
            }
        } else if (moveLeft == 3 && type != 3) {
            if (sumx < -0.30) {
                type = 3;
                // TODO: should check if the ACTIVE app is Safari or Firefox and,
                // if so, check if the mouse cursor is on its active WINDOW
                // that is, is it able to receive multi-touch events?
                CFTypeRef axui = axuiUnderMouse();
                NSString *application = nameOfAxui(axui);
                if (![application isEqualToString:@"Safari"] && ![application isEqualToString:@"Firefox"]) {
                    dispatchExclusiveCommand(@"Three-Swipe-Left", TRACKPAD, kGestureOwnerThreeFingerSwipe);
                    for (int i = 0; i < nFingers; i++) {
                        startx[i] = data[i].px;
                        starty[i] = data[i].py;
                    }
                }
            }
        } else if (moveRight == 3 && type != 4) {
            if (sumx > 0.30) {
                type = 4;
                CFTypeRef axui = axuiUnderMouse();
                NSString *application = nameOfAxui(axui);
                if (![application isEqualToString:@"Safari"] && ![application isEqualToString:@"Firefox"]) {
                    dispatchExclusiveCommand(@"Three-Swipe-Right", TRACKPAD, kGestureOwnerThreeFingerSwipe);
                    for (int i = 0; i < nFingers; i++) {
                        startx[i] = data[i].px;
                        starty[i] = data[i].py;
                    }
                }
            }
        } else {
            //3 finger pinch
            float deltalx = startx[l]-data[l].px;
            float deltaly = starty[l]-data[l].py;
            float deltarx = startx[r]-data[r].px;
            float deltary = starty[r]-data[r].py;

            float lenl = deltalx*deltalx + deltaly*deltaly;
            float lenr = deltarx*deltarx + deltary*deltary;

            float startlen = lenSqr(startx[l], starty[l], startx[r], starty[r]);
            float curlen = lenSqr(data[l].px, data[l].py, data[r].px, data[r].py);

            float deltacosine = cosineBetweenVectors(
                                                     startx[l] - data[l].px,
                                                     starty[l] - data[l].py,
                                                     startx[r] - data[r].px,
                                                     starty[r] - data[r].py
                                                     );
            if (deltacosine < 0.1 && lenl > 0.005 && lenr > 0.003) { //ring finger is harder to move
                if (curlen-startlen > 0.455 * charRegIndexRingDistance && type != 5) {
                    dispatchExclusivePalmSafeCommand(@"Three-Finger Pinch-Out", TRACKPAD, kGestureOwnerThreeFingerPinch);
                    type = 5;

                    l = 0; r = 0;
                    for (int i = 0; i < nFingers; i++) {
                        startx[i] = data[i].px;
                        starty[i] = data[i].py;
                        if (data[i].px + data[i].py < data[l].px + data[l].py) {
                            l = i;
                        } else if (data[i].px + data[i].py > data[r].px + data[r].py) {
                            r = i;
                        }
                    }
                } else if (curlen-startlen < -0.455 * charRegIndexRingDistance && type != 6) {
                    dispatchExclusivePalmSafeCommand(@"Three-Finger Pinch-In", TRACKPAD, kGestureOwnerThreeFingerPinch);
                    type = 6;

                    l = 0; r = 0;
                    for (int i = 0; i < nFingers; i++) {
                        startx[i] = data[i].px;
                        starty[i] = data[i].py;
                        if (data[i].px+data[i].py < data[l].px+data[l].py) {
                            l = i;
                        } else if (data[i].px+data[i].py > data[r].px+data[r].py) {
                            r = i;
                        }
                    }
                }
            }
        }

    } else if (step == 3) { //end three fingers
        type = 0;
    }

    lastNFingers = nFingers;
}


static void gestureTrackpadSwipeFourFingers(const Finger *data, int nFingers) {
    static float startx[4], starty[4];
    static int lastNFingers;
    int step = 0;
    static int type = 0;

    if (lastNFingers != 4 && nFingers == 4) {
        step = 1;
    } else if (lastNFingers == 4 && nFingers == 4) {
        step = 2;
    } else if (lastNFingers == 4 && nFingers != 4) {
        step = 3;
    }

    if (step == 1) { //start four fingers
        for (int i = 0; i < nFingers; i++) {
            startx[i] = data[i].px;
            starty[i] = data[i].py;
        }
        type = 0;
    } else if (step == 2) { //continue four fingers
        float sumx = 0.0f;
        float sumy = 0.0f;
        int moveDown = 0;
        int moveUp = 0;
        int moveLeft = 0;
        int moveRight = 0;
        for (int i = 0; i < nFingers; i++) {
            sumx += data[i].px - startx[i];
            sumy += data[i].py - starty[i];
            if (data[i].py - starty[i] < -0.08) moveDown++;
            else if (data[i].py - starty[i] > 0.08) moveUp++;
            if (data[i].px - startx[i] < -0.07) moveLeft++;
            else if (data[i].px - startx[i] > 0.07) moveRight++;
        }

        if (moveDown == 4) {
            if (sumy < -0.46 && type != 1) {
                type = 1;
                dispatchExclusiveCommand(@"Four-Swipe-Down", TRACKPAD, kGestureOwnerFourFingerSwipe);
                for (int i = 0; i < nFingers; i++) {
                    startx[i] = data[i].px;
                    starty[i] = data[i].py;
                }
            }
        } else if (moveUp == 4 && type != 2) {
            if (sumy > 0.46) {
                type = 2;
                dispatchExclusiveCommand(@"Four-Swipe-Up", TRACKPAD, kGestureOwnerFourFingerSwipe);
                for (int i = 0; i < nFingers; i++) {
                    startx[i] = data[i].px;
                    starty[i] = data[i].py;
                }
            }
        } else if (moveLeft == 4 && type != 3) {
            if (sumx < -0.40) {
                type = 3;
                dispatchExclusiveCommand(@"Four-Swipe-Left", TRACKPAD, kGestureOwnerFourFingerSwipe);
                for (int i = 0; i < nFingers; i++) {
                    startx[i] = data[i].px;
                    starty[i] = data[i].py;
                }
            }
        } else if (moveRight == 4 && type != 4) {
            if (sumx > 0.40) {
                type = 4;
                dispatchExclusiveCommand(@"Four-Swipe-Right", TRACKPAD, kGestureOwnerFourFingerSwipe);
                for (int i = 0; i < nFingers; i++) {
                    startx[i] = data[i].px;
                    starty[i] = data[i].py;
                }
            }
        }

    } else if (step == 3) { //end four fingers
        type = 0;
    }

    lastNFingers = nFingers;
}


static void gestureTrackpadTwoFixOneDoubleTap(const Finger *data, int nFingers, double timestamp) {
    static int step = 0;
    static double sttime;
    static float fing[3][2];
    static int idf[3];
    int i, j;
    if (nFingers <= 1 || nFingers > 3)
    	  step = 0;
    if (step == 0 && nFingers == 2) {
        step = 1;
    } else if (step == 1 && nFingers == 3 && data[0].size > 0.15 && data[1].size > 0.15 && data[2].size > 0.15) {
        for (i = 0; i < 3; i++) {
            fing[i][0] = data[i].px;
            fing[i][1] = data[i].py;
        }
        idf[0] = 0;
        idf[2] = 2;
        for (i = 0; i < 3; i++) {
            if (data[i].px+data[i].py < data[idf[0]].px+data[idf[0]].py)
                idf[0] = i;
            if (data[i].px+data[i].py > data[idf[2]].px+data[idf[2]].py)
                idf[2] = i;
        }
        idf[1] = 3 - idf[0] - idf[2];
        for (i = 0; i < 3; i++)
            idf[i] = data[idf[i]].identifier;

        sttime = timestamp;
        step = 2;
    } else if (step == 2 || step == 4) {
        if (timestamp - sttime > clickSpeed)
            step = 0;
        if (nFingers == 2) {
            if (step == 2) {
                sttime = timestamp;
                step = 3;
            } else if (step == 4) {
                for (i = 0; i < 3; i++) {
                    for (j = 0; j < 2; j++)
                        if (data[j].identifier == idf[i])
                            break;
                    if (j == 2) {
                        if (i == 0)
                            dispatchExclusiveTapCommand(@"Two-Fix Index-Double-Tap", TRACKPAD, kGestureOwnerTwoFixedOneDoubleTap);
                        else if (i == 1)
                            dispatchExclusiveTapCommand(@"Two-Fix Middle-Double-Tap", TRACKPAD, kGestureOwnerTwoFixedOneDoubleTap);
                        else
                            dispatchExclusiveTapCommand(@"Two-Fix Ring-Double-Tap", TRACKPAD, kGestureOwnerTwoFixedOneDoubleTap);
                        break;
                    }
                }

                step = 0;
            }
        }
    } else if (step == 3) {
        if (timestamp - sttime > clickSpeed)
            step = 0;
        if (nFingers == 3 && data[0].size > 0.15 && data[1].size > 0.15 && data[2].size > 0.15) {
            for (i = 0; i < 3; i++) {
                for (j = 0; j < 3; j++) {
                    if (lenSqr(fing[j][0], fing[j][1], data[i].px, data[i].py) < 0.001)
                        break;
                }
                if (j == 3) break;
            }
            if (i < 3)
                step = 0;
            else {
                step = 4;
                sttime = timestamp;
            }
        }
    }
}


static void gestureTrackpadAutoScroll(const Finger *data, int nFingers, double timestamp) {
    static double sttime;
    static int step = 0;
    static float midY;
    float x[2] = {data[0].px, data[1].px};
    static int startAlready = 0;
    static int shouldCheck = 1, chk[2];
    if (enHanded) {
        x[0] = 1 - x[0];
        x[1] = 1 - x[1];
    }

    if (step == 0) {
        if (nFingers == 2) {
            if (((x[0] < x[1]) ? x[0] : x[1]) < 0.08 || ((x[0] > x[1]) ? x[0] : x[1]) > 0.92) {
                if (shouldCheck) {
                    chk[0] = [commandForGesture(@"Left-Side Scroll", TRACKPAD) isEqualToString:@"Auto Scroll"];
                    chk[1] = [commandForGesture(@"Right-Side Scroll", TRACKPAD) isEqualToString:@"Auto Scroll"];
                    shouldCheck = 0;
                }
                if (
                   (chk[0] && ((x[0] < x[1]) ? x[0] : x[1]) < 0.08) ||
                   (chk[1] && ((x[0] > x[1]) ? x[0] : x[1]) > 0.92)
                   ) {
                    step = 1;
                    startAlready = 0;
                    midY = (data[0].py + data[1].py) / 2;
                }
            }
        } else if (nFingers == 1) {
            shouldCheck = 1;
        }
    } else if (step == 1) {
        if (timestamp > sttime) {
            float avgY = (data[0].py + data[1].py) / 2;
            float speedf = -((midY - avgY) * (midY - avgY) * (midY - avgY) * 50 * 8);
            if (!startAlready && fabs(speedf) < 0.1)
                speedf = 0;
            else
                startAlready = 1;

            int speed = (int)(speedf < 0 ? floorf(speedf) : ceilf(speedf));
            autoScrollFlag = speed == 0 ? 0 : (speed > 0 ? 1 : -1);
            CGEventRef eventRef = CGEventCreateScrollWheelEvent(NULL, kCGScrollEventUnitPixel, 1, speed);
            if (eventRef) {
                CGEventPost(kCGHIDEventTap, eventRef);
                CFRelease(eventRef);
            }
            sttime = timestamp + 0.01;
        }
        if (nFingers != 2) {
            step = 0;
            autoScrollFlag = 0;
        }
    }
}


static int trackpadCallback(MGMultitouchDeviceRef device, Finger *data, int nFingers, double timestamp, int frame) {
    if (DEBUG && logLevel >= LOG_LEVEL_TRACE) NSLog(@"TrackpadCallback %p", device);
    trackpadNFingers = nFingers;
    int activeTrackpadContactCount = nFingers;

    // Raw trackpad frames feed candidate-gesture trace sessions. Nothing here
    // recognizes or suppresses; the recorder ignores frames when idle.
    if (MGTraceIsActive()) {
        MGTraceContact traceContacts[16];
        int traceCount = MIN(nFingers, 16);
        for (int i = 0; i < traceCount; i++) {
            traceContacts[i] = (MGTraceContact){data[i].identifier, data[i].state,
                data[i].px, data[i].py, data[i].size, data[i].majorAxis,
                data[i].minorAxis, data[i].zDensity};
        }
        MGTraceRecordTrackpadFrame(device, timestamp, frame, traceContacts, traceCount);
    }

    static int thumbId = -1;
    Finger *dataUnnormalized = (Finger *)malloc(sizeof(Finger) * nFingers);
    for (int i = 0; i < nFingers; i++) {
        dataUnnormalized[i] = data[i];
        dataUnnormalized[i].px /= 1;
        dataUnnormalized[i].py /= 1;
    }

    if (nFingers == 0) {
        thumbId = -1;
    }

    if (enAll && enTPAll) {
        if (enCharRegTP) {
            // IMPORTANT : DO NOT CHANGE ORDER
            if (enTwoDrawing)
                trackpadRecognizerTwo(dataUnnormalized, nFingers, timestamp);
            if (enOneDrawing)
                trackpadRecognizerOne(data, nFingers, timestamp);
        }

        // remove hovering and other touch events
        for (int i = 0; i < nFingers; i++) {
            if (
                ! (
                    data[i].state == MTTouchStateMakeTouch ||
                    data[i].state == MTTouchStateTouching ||
                    data[i].state == MTTouchStateBreakTouch
                  )
                ) {
                if (logLevel >= LOG_LEVEL_TRACE) NSLog(@"Filtered trackpad contact id=%d state=%d x=%f y=%f major=%f minor=%f size=%f", data[i].identifier, data[i].state, data[i].px, data[i].py, data[i].majorAxis, data[i].minorAxis, data[i].size);
                data[i--] = data[--nFingers];
            }
        }
        activeTrackpadContactCount = nFingers;

        float rawContactMajorAxes[16], rawContactYs[16];
        MGTrackpadContact rawInteractionContacts[16];
        int rawContactCount = MIN(nFingers, 16);
        for (int i = 0; i < rawContactCount; i++) {
            if (logLevel >= LOG_LEVEL_TRACE) NSLog(@"MTTouch raw id=%d state=%d x=%f y=%f major=%f minor=%f size=%f", data[i].identifier, data[i].state, data[i].px, data[i].py, data[i].majorAxis, data[i].minorAxis, data[i].size);
            rawContactMajorAxes[i] = data[i].majorAxis;
            rawContactYs[i] = data[i].py;
            rawInteractionContacts[i] = (MGTrackpadContact){
                data[i].identifier,
                data[i].px,
                data[i].py,
                data[i].majorAxis,
            };
        }
        MGTrackpadInteractionObserveRawContacts(&trackpadInteraction,
                                                rawInteractionContacts,
                                                rawContactCount, timestamp);
        gestureTrackpadFiveFingerTap(
            data, nFingers,
            MGTrackpadInteractionFiveFingerContactsAreEligible(
                rawContactMajorAxes, rawContactYs, rawContactCount) &&
            (nFingers != 5 || trackpadContactsArrivedTogether(
                data, 5, kTrackpadSimultaneousTapMaximumOnsetSpread)),
            timestamp);

        // detect thumb & palm resting
        int cl, cli, tl, tli;
        float mY, mX;
        cl = 0;
        tl = 0;
        mY = 1;

        mX = 1 - enHanded;
        for (int i = 0; i < nFingers; i++) {
            if (enHanded) {
                if (data[i].px > 1 - 0.1) {
                    tl++;
                    tli = i;
                } else if (data[i].px > mX) {
                    mX = data[i].px;
                }
            } else {
                if (data[i].px < 0.1) {
                    tl++;
                    tli = i;
                } else if (data[i].px < mX) {
                    mX = data[i].px;
                }
            }
        }
        if (tl == 1 && nFingers > 1 && fabs(mX - data[tli].px) >= 0.25) {
            if (logLevel >= LOG_LEVEL_TRACE) NSLog(@"Filtered trackpad edge contact id=%d state=%d x=%f y=%f major=%f minor=%f size=%f", data[tli].identifier, data[tli].state, data[tli].px, data[tli].py, data[tli].majorAxis, data[tli].minorAxis, data[tli].size);
            data[tli] = data[--nFingers];
        }

        if (thumbId != -1) {
            int tmp = 1;
            for (int i = 0; i < nFingers; i++) {
                if (data[i].identifier == thumbId) {
                    if (logLevel >= LOG_LEVEL_TRACE) NSLog(@"Filtered trackpad thumb id=%d state=%d x=%f y=%f major=%f minor=%f size=%f", data[i].identifier, data[i].state, data[i].px, data[i].py, data[i].majorAxis, data[i].minorAxis, data[i].size);
                    data[i] = data[--nFingers];
                    tmp = 0;
                    break;
                }
            }
            if (tmp) {
                thumbId = -1;
            }
        } else {
            for (int i = 0; i < nFingers; i++) {
                if (data[i].py < 0.1 || data[i].majorAxis - data[i].minorAxis >= 5.5) {
                    cl++;
                    cli = i;
                } else if (data[i].py<mY)
                    mY = data[i].py;
            }
            if (cl == 1 && nFingers > 1 && mY-data[cli].py >= 0.4) {
                thumbId = data[cli].identifier;
                if (logLevel >= LOG_LEVEL_TRACE) NSLog(@"Filtered trackpad thumb candidate id=%d state=%d x=%f y=%f major=%f minor=%f size=%f", data[cli].identifier, data[cli].state, data[cli].px, data[cli].py, data[cli].majorAxis, data[cli].minorAxis, data[cli].size);
                data[cli] = data[--nFingers];
            }
        }

        if (logLevel >= LOG_LEVEL_TRACE) {
            for (int i = 0; i < nFingers; i++) {
                NSLog(@"MTTouch filtered id=%d state=%d x=%f y=%f major=%f minor=%f size=%f", data[i].identifier, data[i].state, data[i].px, data[i].py, data[i].majorAxis, data[i].minorAxis, data[i].size);
            }
        }

        MGTrackpadContact interactionContacts[16];
        int interactionContactCount = MIN(nFingers, 16);
        for (int i = 0; i < interactionContactCount; i++) {
            interactionContacts[i] = (MGTrackpadContact){
                data[i].identifier,
                data[i].px,
                data[i].py,
                data[i].majorAxis,
            };
        }
        MGTrackpadInteractionObserveContacts(&trackpadInteraction, interactionContacts,
                                             interactionContactCount, timestamp);
        // A resting palm reaches this callback as an ordinary contact, so the
        // swipe family counts fingertip-scale contacts: two fingers plus a
        // palm heel must scroll, not arm three-finger scroll suppression.
        observeBoundSwipeFamilies(TRACKPAD,
            MGTrackpadInteractionFingertipScaleContactCount(interactionContacts,
                                                            interactionContactCount));
        BOOL contactsFormTapGroup = MGTrackpadInteractionContactsFormTapGroup(
            interactionContacts, interactionContactCount);

        if (enHanded)
            for (int i = 0; i < nFingers; i++)
                data[i].px = 1 - data[i].px;

        if (!gestureTrackpadMoveResize(data, nFingers, timestamp)) {
            if (!isTrackpadRecognizing) {
                gestureTrackpadAutoScroll(data, nFingers, timestamp);

                gestureTrackpadOneFixOneTap(data, nFingers, timestamp);

                gestureTrackpadTwoFingerTap(data, nFingers, contactsFormTapGroup, timestamp);
                gestureTrackpadHoldSlide(data, nFingers);
                gestureTrackpadThreeFingerTap(data, nFingers, contactsFormTapGroup, timestamp);

                gestureTrackpadOneFixTwoSlide(data, nFingers, timestamp);
                gestureTrackpadChangeSpace(data, nFingers);

                gestureTrackpadTab4(data, nFingers, timestamp, 0);
                gestureTrackpadTab4(data, nFingers, timestamp, 1);
                gestureTrackpadFourFingerTap(data, nFingers, timestamp);
                trackpadTab4Triggered = FALSE;

                gestureTrackpadSwipeThreeFingers(data, nFingers);
                gestureTrackpadSwipeFourFingers(data, nFingers);
            }
            gestureTrackpadTwoFixOneDoubleTap(data, nFingers, timestamp);
        }
    }

    MGTrackpadInteractionFinishFrame(&trackpadInteraction, activeTrackpadContactCount);
    MGTrackpadInteractionExpireStalePhysicalClick(&trackpadInteraction, timestamp);

    free(dataUnnormalized);
    return 0;
}

#pragma mark - Magic Mouse

static void gestureMagicMouseOneFingerSwipe(const Finger *data, int nFingers, double timestamp) {
    static int tracking = 0;
    static int touchId = -1;
    static double startTime = -1;
    static float startx = 0;
    static float starty = 0;
    static int triggered = 0;

    if (CGEventSourceButtonState(kCGEventSourceStateHIDSystemState, kCGMouseButtonLeft) ||
        CGEventSourceButtonState(kCGEventSourceStateHIDSystemState, kCGMouseButtonRight)) {
        tracking = 0;
        touchId = -1;
        startTime = -1;
        triggered = 0;
        return;
    }

    if (nFingers == 1) {
        NSString *leftCommand = commandForGesture(@"One-Swipe-Left", MAGICMOUSE);
        NSString *rightCommand = commandForGesture(@"One-Swipe-Right", MAGICMOUSE);
        BOOL hasBinding = leftCommand != nil || rightCommand != nil;
        if (!hasBinding && !MGTraceAuditsGestureCatalog()) {
            // Skip one-finger swipe tracking when neither direction is bound.
            // Tracking would suppress horizontal scrolling without dispatching
            // a gesture.
            tracking = 0;
            touchId = -1;
            startTime = -1;
            triggered = 0;
            return;
        }

        // Keep browser history swipe from firing while a custom one-finger
        // Magic Mouse swipe is active for the app under the cursor.
        if (hasBinding) disableHorizontalScroll = 1;

        if (!tracking || data[0].identifier != touchId) {
            tracking = 1;
            touchId = data[0].identifier;
            startTime = timestamp;
            startx = data[0].px;
            starty = data[0].py;
            triggered = 0;
            return;
        }

        float dx = data[0].px - startx;
        float dy = data[0].py - starty;
        if (fabs(dx) > 0.04 && fabs(dy) < 0.08) {
            if (hasBinding) {
                disableHorizontalScroll = 1;
                customMagicMouseScrollSuppressionUntil = CFAbsoluteTimeGetCurrent() + 0.35;
            }
        }

        if (!triggered && timestamp - startTime <= 0.45 && fabs(dy) < 0.08) {
            if (dx <= -0.16) {
                dispatchExclusiveCommand(@"One-Swipe-Left", MAGICMOUSE, kGestureOwnerOneFingerSwipe);
                if (hasBinding) customMagicMouseScrollSuppressionUntil = CFAbsoluteTimeGetCurrent() + 0.5;
                triggered = 1;
            } else if (dx >= 0.16) {
                dispatchExclusiveCommand(@"One-Swipe-Right", MAGICMOUSE, kGestureOwnerOneFingerSwipe);
                if (hasBinding) customMagicMouseScrollSuppressionUntil = CFAbsoluteTimeGetCurrent() + 0.5;
                triggered = 1;
            }
        }
    } else {
        tracking = 0;
        touchId = -1;
        startTime = -1;
        triggered = 0;
    }
}

static void gestureMagicMouseTwoFingerSwipe(const Finger *data, int nFingers, double timestamp, int thumbPresent) {
    static int tracking = 0;
    static int fingerIds[2];
    static double startTime = -1;
    static float startx[2];
    static float starty[2];
    static int triggered = 0;
    Finger fingers[2];
    int count = 0;

    NSString *leftCommand = commandForGesture(@"Two-Swipe-Left", MAGICMOUSE);
    NSString *rightCommand = commandForGesture(@"Two-Swipe-Right", MAGICMOUSE);
    BOOL hasBinding = leftCommand != nil || rightCommand != nil;
    if (!hasBinding && !MGTraceAuditsGestureCatalog()) {
        tracking = 0;
        startTime = -1;
        triggered = 0;
        return;
    }

    if (nFingers - (thumbPresent ? 1 : 0) != 2) {
        tracking = 0;
        startTime = -1;
        triggered = 0;
        return;
    }

    if (hasBinding) disableHorizontalScroll = 1;

    for (int i = 0; i < nFingers && count < 2; i++) {
        if (thumbPresent && i == thumbPresent - 1)
            continue;
        fingers[count++] = data[i];
    }

    if (count != 2) {
        tracking = 0;
        startTime = -1;
        triggered = 0;
        return;
    }

    if (!tracking) {
        tracking = 1;
        startTime = timestamp;
        for (int i = 0; i < 2; i++) {
            fingerIds[i] = fingers[i].identifier;
            startx[i] = fingers[i].px;
            starty[i] = fingers[i].py;
        }
        return;
    }

    float dx[2] = {0, 0};
    float dy[2] = {0, 0};
    for (int i = 0; i < 2; i++) {
        int matched = 0;
        for (int j = 0; j < 2; j++) {
            if (fingers[j].identifier == fingerIds[i]) {
                dx[i] = fingers[j].px - startx[i];
                dy[i] = fingers[j].py - starty[i];
                matched = 1;
                break;
            }
        }
        if (!matched) {
            tracking = 0;
            triggered = 0;
            return;
        }
    }

    if (timestamp - startTime > 0.60 || fabs(dy[0]) > 0.08 || fabs(dy[1]) > 0.08) {
        tracking = 0;
        triggered = 0;
        return;
    }

    if (!triggered && dx[0] <= -0.08 && dx[1] <= -0.08 && dx[0] + dx[1] <= -0.22) {
        dispatchExclusiveCommand(@"Two-Swipe-Left", MAGICMOUSE, kGestureOwnerTwoFingerSwipe);
        triggered = 1;
    } else if (!triggered && dx[0] >= 0.08 && dx[1] >= 0.08 && dx[0] + dx[1] >= 0.22) {
        dispatchExclusiveCommand(@"Two-Swipe-Right", MAGICMOUSE, kGestureOwnerTwoFingerSwipe);
        triggered = 1;
    }
}

static void gestureMagicMouseTwoFingerTap(Finger *data, int nFingers, double timestamp, int thumbPresent) {
    enum {
        kTwoFingerTapIdle = 0,
        kTwoFingerTapTracking = 1,
        kTwoFingerTapWaitingForLift = 2,
        kTwoFingerTapRejectedUntilLift = 3,
    };
    static int step = kTwoFingerTapIdle;
    static double startTime = -1;
    static int fingerIds[2];
    static float startx[2];
    static float starty[2];

    if (magicMouseTapsSuppressedUntilLift ||
        customMagicMouseTapSuppressionUntil > CFAbsoluteTimeGetCurrent()) {
        step = nFingers == 0 ? kTwoFingerTapIdle : kTwoFingerTapRejectedUntilLift;
        startTime = -1;
        return;
    }

    if (CGEventSourceButtonState(kCGEventSourceStateHIDSystemState, kCGMouseButtonLeft) ||
        CGEventSourceButtonState(kCGEventSourceStateHIDSystemState, kCGMouseButtonRight)) {
        step = nFingers == 0 ? kTwoFingerTapIdle : kTwoFingerTapRejectedUntilLift;
        startTime = -1;
        return;
    }

    if (thumbPresent) {
        Finger tmp = data[thumbPresent - 1];
        data[thumbPresent - 1] = data[--nFingers];
        data[nFingers] = tmp;
    }

    if (nFingers >= 3) {
        step = kTwoFingerTapRejectedUntilLift;
        startTime = -1;
    } else if (step == kTwoFingerTapRejectedUntilLift) {
        if (nFingers == 0)
            step = kTwoFingerTapIdle;
    } else if (step == kTwoFingerTapIdle && nFingers == 2) {
        int identifiers[] = {data[0].identifier, data[1].identifier};
        if (!MGContactOnsetTrackerContactsArrivedWithin(
                &magicMouseContactOnsets, identifiers, 2,
                kMagicMouseTwoFingerTapMaximumOnsetSpread)) {
            MGTraceRecordCandidate(@"Two-Finger Tap", @"canceled",
                                   @"contact-onset-spread");
            step = kTwoFingerTapRejectedUntilLift;
            startTime = -1;
        } else {
            step = kTwoFingerTapTracking;
            startTime = timestamp;
            for (int i = 0; i < 2; i++) {
                fingerIds[i] = data[i].identifier;
                startx[i] = data[i].px;
                starty[i] = data[i].py;
            }
        }
    } else if (step == kTwoFingerTapTracking && nFingers == 2) {
        BOOL valid = timestamp - startTime <= kMagicMouseTwoFingerTapMaxDuration;
        for (int i = 0; valid && i < 2; i++) {
            int matched = 0;
            for (int j = 0; j < 2; j++) {
                if (data[j].identifier == fingerIds[i]) {
                    if (lenSqr(data[j].px, data[j].py, startx[i], starty[i]) > kMagicMouseTwoFingerTapMaxMove)
                        valid = NO;
                    matched = 1;
                    break;
                }
            }
            if (!matched)
                valid = NO;
        }
        if (!valid) {
            step = kTwoFingerTapRejectedUntilLift;
            startTime = -1;
        }
    } else if ((step == kTwoFingerTapTracking || step == kTwoFingerTapWaitingForLift) && nFingers == 1) {
        BOOL valid = timestamp - startTime <=
            kMagicMouseTwoFingerTapMaxDuration + kMagicMouseTwoFingerTapLiftGraceDuration;
        int matched = 0;
        for (int i = 0; valid && i < 2; i++) {
            if (data[0].identifier == fingerIds[i]) {
                if (lenSqr(data[0].px, data[0].py, startx[i], starty[i]) > kMagicMouseTwoFingerTapMaxMove)
                    valid = NO;
                matched = 1;
                break;
            }
        }
        if (!matched || !valid) {
            step = kTwoFingerTapRejectedUntilLift;
            startTime = -1;
        } else {
            step = kTwoFingerTapWaitingForLift;
        }
    } else if ((step == kTwoFingerTapTracking || step == kTwoFingerTapWaitingForLift) && nFingers == 0) {
        if (timestamp - startTime <= kMagicMouseTwoFingerTapMaxDuration + kMagicMouseTwoFingerTapLiftGraceDuration) {
            dispatchExclusiveTapCommand(@"Two-Finger Tap", MAGICMOUSE, kGestureOwnerTwoFingerTap);
        }
        step = kTwoFingerTapIdle;
        startTime = -1;
    }

    if (thumbPresent) {
        Finger tmp = data[thumbPresent - 1];
        data[thumbPresent - 1] = data[nFingers];
        data[nFingers] = tmp;
    }
}

static void gestureMagicMouseThreeFingerTap(Finger *data, int nFingers, double timestamp, int thumbPresent) {
    enum {
        kThreeFingerTapIdle = 0,
        kThreeFingerTapTracking = 1,
        kThreeFingerTapWaitingForLift = 2,
        kThreeFingerTapRejectedUntilLift = 3,
    };
    static int step = 0;
    static double startTime = -1;
    static int fingerIds[3];
    static float startx[3];
    static float starty[3];

    if (magicMouseTapsSuppressedUntilLift ||
        customMagicMouseTapSuppressionUntil > CFAbsoluteTimeGetCurrent() ||
        CGEventSourceButtonState(kCGEventSourceStateHIDSystemState, kCGMouseButtonLeft) ||
        CGEventSourceButtonState(kCGEventSourceStateHIDSystemState, kCGMouseButtonRight)) {
        step = kThreeFingerTapIdle;
        startTime = -1;
        return;
    }

    if (thumbPresent) {
        Finger tmp = data[thumbPresent - 1];
        data[thumbPresent - 1] = data[--nFingers];
        data[nFingers] = tmp;
    }

    if (nFingers > 3) {
        step = kThreeFingerTapRejectedUntilLift;
        startTime = -1;
    } else if (step == kThreeFingerTapRejectedUntilLift) {
        if (nFingers == 0)
            step = kThreeFingerTapIdle;
    } else if (step == kThreeFingerTapIdle && nFingers == 3) {
        int identifiers[] = {data[0].identifier, data[1].identifier, data[2].identifier};
        if (!MGContactOnsetTrackerContactsArrivedWithin(
                &magicMouseContactOnsets, identifiers, 3,
                kMagicMouseTwoFingerTapMaximumOnsetSpread)) {
            MGTraceRecordCandidate(@"Three-Finger Tap", @"canceled",
                                   @"contact-onset-spread");
            step = kThreeFingerTapRejectedUntilLift;
            startTime = -1;
        } else {
            step = kThreeFingerTapTracking;
            startTime = timestamp;
            for (int i = 0; i < 3; i++) {
                fingerIds[i] = data[i].identifier;
                startx[i] = data[i].px;
                starty[i] = data[i].py;
            }
        }
    } else if (step == kThreeFingerTapTracking || step == kThreeFingerTapWaitingForLift) {
        BOOL valid = timestamp - startTime <=
            kMagicMouseThreeFingerTapMaxDuration + kMagicMouseThreeFingerTapLiftGraceDuration;
        for (int i = 0; valid && i < nFingers; i++) {
            int matched = 0;
            for (int j = 0; j < 3; j++) {
                if (data[i].identifier == fingerIds[j]) {
                    if (lenSqr(data[i].px, data[i].py, startx[j], starty[j]) > kMagicMouseThreeFingerTapMaxMove)
                        valid = NO;
                    matched = 1;
                    break;
                }
            }
            if (!matched)
                valid = NO;
        }

        if (!valid) {
            step = kThreeFingerTapRejectedUntilLift;
            startTime = -1;
        } else if (nFingers == 0) {
            dispatchExclusiveCommand(@"Three-Finger Tap", MAGICMOUSE, kGestureOwnerThreeFingerTap);
            step = kThreeFingerTapIdle;
            startTime = -1;
        } else if (nFingers < 3) {
            step = kThreeFingerTapWaitingForLift;
        } else if (timestamp - startTime > kMagicMouseThreeFingerTapMaxDuration) {
            step = kThreeFingerTapRejectedUntilLift;
            startTime = -1;
        }
    }

    if (thumbPresent) {
        Finger tmp = data[thumbPresent - 1];
        data[thumbPresent - 1] = data[nFingers];
        data[nFingers] = tmp;
    }
}

static void gestureMagicMouseRightFrontTap(const Finger *data, int nFingers, double timestamp) {
    static int step = 0;
    static int touchId = -1;
    static double startTime = -1;
    static float startx = 0;
    static float starty = 0;

    if (magicMouseTapsSuppressedUntilLift ||
        customMagicMouseTapSuppressionUntil > CFAbsoluteTimeGetCurrent() ||
        customMagicMousePrimaryTapSuppressionUntil > CFAbsoluteTimeGetCurrent()) {
        step = 0;
        touchId = -1;
        startTime = -1;
        return;
    }

    if (CGEventSourceButtonState(kCGEventSourceStateHIDSystemState, kCGMouseButtonLeft) ||
        CGEventSourceButtonState(kCGEventSourceStateHIDSystemState, kCGMouseButtonRight)) {
        step = 0;
        touchId = -1;
        startTime = -1;
        return;
    }

    if (step == 0 && nFingers == 1) {
        if (data[0].px >= kMagicMouseRightFrontTapStartMinX &&
            data[0].py >= kMagicMouseRightFrontTapStartMinY) {
            step = 1;
            touchId = data[0].identifier;
            startTime = timestamp;
            startx = data[0].px;
            starty = data[0].py;
        }
    } else if (step == 1 && nFingers == 1) {
        if (data[0].identifier != touchId ||
            lenSqr(data[0].px, data[0].py, startx, starty) > kMagicMouseRightFrontTapMaxMove ||
            data[0].px < kMagicMouseRightFrontTapKeepMinX ||
            data[0].py < kMagicMouseRightFrontTapKeepMinY ||
            timestamp - startTime > kMagicMouseRightFrontTapMaxDuration) {
            step = 0;
            touchId = -1;
            startTime = -1;
        }
    } else if (step == 1 && nFingers == 0) {
        if (timestamp - startTime <= kMagicMouseRightFrontTapMaxDuration) {
            dispatchExclusiveTapCommand(@"Right-Front Tap", MAGICMOUSE, kGestureOwnerFrontRightTap);
        }
        step = 0;
        touchId = -1;
        startTime = -1;
    } else if (nFingers != 1) {
        step = 0;
        touchId = -1;
        startTime = -1;
    }
}

static void gestureMagicMouseOneFingerTap(const Finger *data, int nFingers, double timestamp) {
    enum {
        kPrimaryTapIdle = 0,
        kPrimaryTapTracking = 1,
        kPrimaryTapRejectedUntilLift = 2,
    };
    static int step = 0;
    static int touchId = -1;
    static double startTime = -1;
    static float startx = 0;
    static float starty = 0;

    if (nFingers == 0) {
        if (step == kPrimaryTapTracking && timestamp - startTime <= kMagicMousePrimaryTapMaxDuration) {
            dispatchExclusiveTapCommand(@"One-Finger Tap", MAGICMOUSE, kGestureOwnerOneFingerTap);
        }
        step = kPrimaryTapIdle;
        touchId = -1;
        startTime = -1;
        return;
    }

    if (magicMouseTapsSuppressedUntilLift ||
        customMagicMouseTapSuppressionUntil > CFAbsoluteTimeGetCurrent() ||
        customMagicMousePrimaryTapSuppressionUntil > CFAbsoluteTimeGetCurrent()) {
        step = kPrimaryTapRejectedUntilLift;
        touchId = -1;
        startTime = -1;
        return;
    }

    if (CGEventSourceButtonState(kCGEventSourceStateHIDSystemState, kCGMouseButtonLeft) ||
        CGEventSourceButtonState(kCGEventSourceStateHIDSystemState, kCGMouseButtonRight)) {
        step = kPrimaryTapRejectedUntilLift;
        touchId = -1;
        startTime = -1;
        return;
    }

    if (step == kPrimaryTapRejectedUntilLift) {
        return;
    }

    if (step == kPrimaryTapIdle && nFingers == 1) {
        if (data[0].py >= kMagicMousePrimaryTapStartMinY &&
            !magicMousePointIsRightFrontTapRegion(data[0].px, data[0].py)) {
            step = kPrimaryTapTracking;
            touchId = data[0].identifier;
            startTime = timestamp;
            startx = data[0].px;
            starty = data[0].py;
        }
    } else if (step == kPrimaryTapTracking && nFingers == 1) {
        if (data[0].identifier != touchId ||
            lenSqr(data[0].px, data[0].py, startx, starty) > kMagicMousePrimaryTapMaxMove ||
            data[0].py < kMagicMousePrimaryTapKeepMinY ||
            magicMousePointIsRightFrontTapRegion(data[0].px, data[0].py) ||
            timestamp - startTime > kMagicMousePrimaryTapMaxDuration) {
            step = kPrimaryTapRejectedUntilLift;
            touchId = -1;
            startTime = -1;
        }
    } else if (nFingers != 1) {
        step = kPrimaryTapRejectedUntilLift;
        touchId = -1;
        startTime = -1;
    }
}

static void gestureMagicMouseSwipeThreeFingers(Finger *data, int nFingers, double timestamp, int thumbPresent) {
    static double beforeendtime = -10;
    static double endtime = -1;
    static float startx[3], starty[3];
    static int lastNFingers;
    int step = 0;

    if (thumbPresent) {
        Finger tmp = data[thumbPresent - 1];
        data[thumbPresent - 1] = data[--nFingers];
        data[nFingers] = tmp;
    }

    // Resolving the binding costs a window-server round trip, so ask only when
    // a third finger arrives and hold the answer while it stays down.
    static BOOL hasBinding = NO;
    static int contactCountAtLastResolve = 0;
    if (nFingers == 3 && contactCountAtLastResolve != 3)
        hasBinding = hasThreeFingerSwipeBinding(MAGICMOUSE);
    contactCountAtLastResolve = nFingers;
    if (!hasBinding && !MGTraceAuditsGestureCatalog()) {
        step = 0;
        trigger = 0;
        lastNFingers = 0;
        return;
    }

    if (lastNFingers != 3 && nFingers == 3) {
        step = 1;
        if (endtime - beforeendtime < 0.01) { //gap created by hardware (so short human can't do)
            step = 2;
        }
    } else if (lastNFingers == 3 && nFingers == 3) {
        step = 2;
    } else if (lastNFingers == 3 && nFingers != 3) {
        step = 3;
    }

    if (step == 1) { //start three fingers

        for (int i = 0; i < nFingers; i++) {
            startx[i] = data[i].px;
            starty[i] = data[i].py;
        }

        beforeendtime = timestamp;

        trigger = 0;

    } else if (step == 2) { //continue three fingers

        float sumx = 0.0f;
        float sumy = 0.0f;
        int moveRight = 0;
        int moveLeft = 0;
        int moveDown = 0;
        int moveVeryDown = 0;
        int moveUp = 0;
        for (int i = 0; i < nFingers; i++) {
            sumx += data[i].px - startx[i];
            sumy += data[i].py - starty[i];
            if (data[i].px - startx[i] > 0.01) moveRight++; //it's harder to swipe right than to swipe left
            else if (data[i].px - startx[i] < -0.015) moveLeft++;
            if (data[i].py - starty[i] < -0.03) moveDown++;
            if (data[i].py - starty[i] < -0.04) moveVeryDown++;
            else if (data[i].py - starty[i] > 0.03) moveUp++;
        }

        if (moveDown < 3 && moveUp < 3) {
            if (moveLeft == 3 && sumx < -0.25) {
                if (!trigger) {
                    dispatchExclusiveCommand(@"Three-Swipe-Left", MAGICMOUSE, kGestureOwnerThreeFingerSwipe);
                    trigger = 1;
                }
            } else if (moveRight >= 3 && sumx > 0.22) {
                if (!trigger) {
                    dispatchExclusiveCommand(@"Three-Swipe-Right", MAGICMOUSE, kGestureOwnerThreeFingerSwipe);
                    trigger = 1;
                }
            }
        } else if (moveVeryDown == 3) {
            if (sumy < -0.17) {
                if (!trigger) {
                    dispatchExclusiveCommand(@"Three-Swipe-Down", MAGICMOUSE, kGestureOwnerThreeFingerSwipe);
                    trigger = 1;
                }
            }
        } else if (moveUp == 3) {
            if (sumy > 0.25) {
                if (!trigger) {
                    dispatchExclusiveCommand(@"Three-Swipe-Up", MAGICMOUSE, kGestureOwnerThreeFingerSwipe);
                    trigger = 1;
                }
            }
        }
        beforeendtime = timestamp;
        endtime = timestamp;

    } else if (step == 3) { //end three fingers
        endtime = timestamp;
        trigger = 0;
    }

    lastNFingers = nFingers;

    if (thumbPresent) {
        Finger tmp = data[thumbPresent - 1];
        data[thumbPresent - 1] = data[nFingers];
        data[nFingers] = tmp;
    }
}

static void gestureMagicMouseTwoFingers(Finger *data, int nFingers, double timestamp, int thumbPresent) {
    static double beforeendtime = -10;
    static double endtime = -1;
    static float startx[3], starty[3];
    static int lastNFingers;
    int step = 0;

    if (thumbPresent) {
        Finger tmp = data[thumbPresent - 1];
        data[thumbPresent - 1] = data[--nFingers];
        data[nFingers] = tmp;
    }

    if (lastNFingers != 2 && nFingers == 2) {
        step = 1;
        if (endtime - beforeendtime < 0.01) { //gap created by hardware (so short human can't do)
            step = 2;
        }
    } else if (lastNFingers == 2 && nFingers == 2) {
        step = 2;
    } else if (lastNFingers == 2 && nFingers != 2) {
        step = 3;
    }

    if (step == 1) { //start two fingers

        if (data[0].px > data[1].px) {
            Finger tmp = data[0];
            data[0] = data[1];
            data[1] = tmp;
        }

        for (int i = 0; i < nFingers; i++) {
            startx[i] = data[i].px;
            starty[i] = data[i].py;
        }

        beforeendtime = timestamp;

        trigger = 0;

    } else if (step == 2) { //continue two fingers
        if (data[0].px > data[1].px) {
            Finger tmp = data[0];
            data[0] = data[1];
            data[1] = tmp;
        }

        float diffx[2], diffy[2];
        diffx[0] = data[0].px - startx[0];
        diffy[0] = data[0].py - starty[0];
        diffx[1] = data[1].px - startx[1];
        diffy[1] = data[1].py - starty[1];
        float dis0 = lenSqr(data[0].px, data[0].py, startx[0], starty[0]);
        float dis1 = lenSqr(data[1].px, data[1].py, startx[1], starty[1]);

        if (!trigger) {
            if (dis1 < 0.002 && dis0 > 0.06 && fabs(diffy[0]) < 0.05) {
                if (diffx[0] < 0) {
                    dispatchExclusiveCommand(@"Middle-Fix Index-Slide-Out", MAGICMOUSE, kGestureOwnerHoldSlide);
                    trigger = 1;
                } else {
                    dispatchExclusiveCommand(@"Middle-Fix Index-Slide-In", MAGICMOUSE, kGestureOwnerHoldSlide);
                    trigger = 1;
                }

            } else if (dis0 < 0.002 && dis1 > 0.02 && fabs(diffy[1]) < 0.05) {
                if (diffx[1] < 0) {
                    dispatchExclusiveCommand(@"Index-Fix Middle-Slide-In", MAGICMOUSE, kGestureOwnerHoldSlide);
                    trigger = 1;
                } else {
                    dispatchExclusiveCommand(@"Index-Fix Middle-Slide-Out", MAGICMOUSE, kGestureOwnerHoldSlide);
                    trigger = 1;
                }
            } else if (dis0 > 0.01 && dis1 > 0.01 && (dis0 > 0.02 || dis1 > 0.02) &&
                       fabs(diffy[0]) < 0.1 &&  fabs(diffy[1]) < 0.1) {
                if (diffx[0] < 0 && diffx[1] > 0) {
                    dispatchExclusiveCommand(@"Pinch Out", MAGICMOUSE, kGestureOwnerTwoFingerPinch);
                    trigger = 1;
                } else if (diffx[0] > 0 && diffx[1] < 0) {
                    dispatchExclusiveCommand(@"Pinch In", MAGICMOUSE, kGestureOwnerTwoFingerPinch);
                    trigger = 1;
                }
            }
        }

        beforeendtime = timestamp;
        endtime = timestamp;

    } else if (step == 3) { //end two fingers
        endtime = timestamp;
        trigger = 0;
    }

    lastNFingers = nFingers;

    if (thumbPresent) {
        Finger tmp = data[thumbPresent - 1];
        data[thumbPresent - 1] = data[nFingers];
        data[nFingers] = tmp;
    }
}


static int gestureMagicMouseV(const Finger *data, int nFingers) {
    int min = data[0].px > data[1].px;
    static CGFloat baseX, baseY, appX, appY;
    static CFTypeRef cWindow;
    static int type = 0, firstTouch = 1, reset = 0;
    int init = 0;
    static float fing[2][2];
    static float lastMouseX = -99999, lastMouseY = -99999;

    if (cWindow == NULL) {
        if (nFingers == 2) {
            if (firstTouch) {
                fing[0][0] = data[0].px;
                fing[0][1] = data[0].py;
                fing[1][0] = data[1].px;
                fing[1][1] = data[1].py;
                firstTouch = 0;
            }
            // If fingers change too much, need to start over.
            if (!reset && (lenSqr(fing[0][0], fing[0][1], data[0].px, data[0].py) > 0.0005 || lenSqr(fing[1][0], fing[1][1], data[1].px, data[1].py) > 0.0005))
                reset = 1;

            // Check gesture.
            if (!reset &&
               ((data[min].py > 0.9 && data[min].px <= 0.18) || (data[min].py > 0.8 && data[min].px <= 0.15)) &&
               ((data[!min].py > 0.9 && data[!min].px >= 0.82) || (data[!min].py > 0.8 && data[!min].px >= 0.85)) &&
               [commandForGesture(@"V-Shape", MAGICMOUSE) isEqualToString:@"Move / Resize"]) {
                init = 1;
                type = 1;
            }
        } else if (nFingers == 0) {
            firstTouch = 1;
            reset = 0;
        }

    } else {
        // Halt.
        if (nFingers == 0 || nFingers > 2) {
            CFSafeRelease(cWindow);
            cWindow = nil;
            dispatch_async(dispatch_get_main_queue(), ^{
                @autoreleasepool {
                    [cursorWindow orderOut:nil];
                }
            });
            type = 0;
            firstTouch = 1;
            reset = 0;
        // Move or resize.
        } else if (nFingers <= 2) {
            if (type != 3-nFingers) {
                type = 3-nFingers;
                init = 1;
            }
        }
    }

    if (init) {
        getMousePosition(&baseX, &baseY);
        dispatch_async(dispatch_get_main_queue(), ^{
            @autoreleasepool {
                [cursorWindow orderOut:nil];
            }
        });
        if (cWindow == nil)
            cWindow = activateWindowAtPosition(baseX, baseY);

        if (cWindow == nil) {
            type = 0;
        } else {
            getWindowPos(cWindow, &appX, &appY);

            cursorImageType = type - 1;
            dispatch_async(dispatch_get_main_queue(), ^{
                @autoreleasepool {
                    [cursorWindow display];
                    [[cursorWindow contentView] setNeedsDisplay:YES];
                    setCursorWindowAtMouse();
                    [cursorWindow setLevel:NSScreenSaverWindowLevel];
                    [cursorWindow makeKeyAndOrderFront:nil];
                }
            });
        }
    }
    if (type) {
        CGFloat x, y;
        getMousePosition(&x, &y);
        if (init || x != lastMouseX || y != lastMouseY) {
            setCursorWindowAtMouse();
            if (type == 1) {
                setWindowPos2(cWindow, x, y, baseX, baseY, appX, appY);
            } else if (type == 2) {
                if (!setWindowSize2(cWindow, x, y, baseX, baseY)) {
                    CFSafeRelease(cWindow);
                    cWindow = nil;
                    dispatch_async(dispatch_get_main_queue(), ^{
                        @autoreleasepool {
                            [cursorWindow orderOut:nil];
                        }
                    });
                    type = 0;
                    firstTouch = 1;
                    reset = 0;
                } else {
                    float nx = x, ny = y;
                    if (x >= appX + 3)
                        baseX = x;
                    else
                        nx = appX + 3;
                    if (y >= appY + 3)
                        baseY = y;
                    else
                        ny = appY + 3;
                    if (nx != x || ny != y) {
                        mouseClick(8, nx, ny);
                    }
                }
            }
            lastMouseX = x;
            lastMouseY = y;
        }
    }

    return 0;
}


static void gestureMagicMouseTwoFixOneSlide(Finger *data, int nFingers, double timestamp, int thumbPresent) {
    static int step = 0;
    static float fing[3][2];
    // Min id
    static int mini;
    static int move = 0;
    static float last[2];

    static int lastThumbPresent = 0;
    if (!thumbPresent && lastThumbPresent && nFingers == 3) {
        thumbPresent = lastThumbPresent;
    }
    if (thumbPresent) {
        Finger tmp = data[thumbPresent - 1];
        data[thumbPresent - 1] = data[--nFingers];
        data[nFingers] = tmp;
    }
    lastThumbPresent = thumbPresent;

    if (step == 0 && nFingers == 2) {
        if (lenSqrF(data, 0, 1) < 0.4) {
            step = 1;
        }
    } else if (step == 1) {
        if (nFingers == 2 && lenSqrF(data, 0, 1) >= 0.4) {
            step = 0;
        } else if (nFingers == 3) {
            mini = 0;
            for (int i = 0; i < 3; i++) {
                fing[i][0] = data[i].px;
                fing[i][1] = data[i].py;
                if (fing[i][0] + fing[i][1] < fing[mini][0] + fing[mini][1]) {
                    mini = i;
                }
            }
            step = 2;
            move = 0;
        }
    } else if (step == 2) {
        if (nFingers != 3) {
            step = 0;
        } else {
            for (int i = 0; i < 3; i++) {
                if (i != mini && lenSqr(data[i].px, data[i].py, fing[i][0], fing[i][1]) > 0.001) {
                    step = 0;
                }
            }
            if (!move) {
                if (lenSqr(data[mini].px, data[mini].py, fing[mini][0], fing[mini][1]) > 0.001) {
                    move = 1;
                    last[0] = fing[mini][0];
                    last[1] = fing[mini][1];
                }
            } else {

                if (
                    (
                     lenSqr(data[mini].px, data[mini].py, last[0], last[1]) < 0.000001 ||
                     data[mini].state == MTTouchStateBreakTouch
                    ) &&
                    (
                     fabs(data[mini].px - fing[mini][0]) >= 0.07 * charRegIndexRingDistance / 0.33 ||
                     fabs(data[mini].py - fing[mini][1]) >= 0.08 * charRegIndexRingDistance / 0.33
                    )
                ) {
                    float dx = fabs(fing[mini][0] - data[mini].px), dy = fabs(fing[mini][1] - data[mini].py);
                    if (dx > dy) {
                        if (fing[mini][0] < data[mini].px)
                            dispatchExclusiveCommand(@"Two-Fix One-Slide-Right", MAGICMOUSE, kGestureOwnerTwoFixedOneSlide);
                        else
                            dispatchExclusiveCommand(@"Two-Fix One-Slide-Left", MAGICMOUSE, kGestureOwnerTwoFixedOneSlide);
                    } else {
                        if (fing[mini][1] < data[mini].py)
                            dispatchExclusiveCommand(@"Two-Fix One-Slide-Up", MAGICMOUSE, kGestureOwnerTwoFixedOneSlide);
                        else
                            dispatchExclusiveCommand(@"Two-Fix One-Slide-Down", MAGICMOUSE, kGestureOwnerTwoFixedOneSlide);
                    }
                    move = 0;
                    fing[mini][0] = data[mini].px;
                    fing[mini][1] = data[mini].py;
                }
                last[0] = data[mini].px;
                last[1] = data[mini].py;
            }
        }
    }
}

// Besides identifying the thumb that click counting excludes, this recognizer
// carries a dispatch path of its own that no configuration slug reaches: the
// engine name "Thumb" is absent from mouseGestureSlugs, so its action branches
// are dormant. Keep them. They hold the engine's only held middle-button
// lifecycle (down, drag, up), which the momentary click paths cannot produce,
// and a binding that exposes it needs them intact.
static int gestureMagicMouseThumb(const Finger *data, int nFingers) {
    static int type = 0;
    int tb = 0;
    int ret = 0;
    if (nFingers > 0) {
        for (int i = 1; i < nFingers; i++)
            if (data[i].py < data[tb].py)
                tb = i;
        float nextLowestY = 1.0f;
        for (int i = 0; i < nFingers; i++)
            if (i != tb && data[i].py < nextLowestY)
                nextLowestY = data[i].py;

        if (MGMagicMouseLowestContactIsThumb(data[tb].px, data[tb].py,
                                             nextLowestY, nFingers)) {
            if (type == 0) {
                if ([commandForGesture(@"Thumb", MAGICMOUSE) isEqualToString:@"Quick Tab Switching"]) {
                    findTabGroup_lx = -99999;
                    if (selectSafariTab()) { // mouse is on Safari
                        cursorImageType = 2;
                        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
                        [cursorWindow display];
                        [cursorWindow setLevel:NSScreenSaverWindowLevel];
                        [cursorWindow makeKeyAndOrderFront:nil];
                        [pool release];
                        type = 1;
                        quickTabSwitching = 1;
                    }
                } else if ([commandForGesture(@"Thumb", MAGICMOUSE) isEqualToString:@"Middle Click"]) {
                    type = 1;
                    simulating = MIDDLEBUTTONDOWN;
                    simulatingByDevice = MAGICMOUSE;

                    CGEventRef ourEvent = CGEventCreate(NULL);
                    CGPoint location = CGEventGetLocation(ourEvent);
                    CFRelease(ourEvent);
                    CGEventRef eventRef = CGEventCreateMouseEvent(NULL, kCGEventOtherMouseDown, location, kCGMouseButtonCenter);
                    CGEventSetIntegerValueField(eventRef, kCGMouseEventButtonNumber, 2);
                    CGEventPost(kCGSessionEventTap, eventRef);
                    CFRelease(eventRef);
                } else {
                    type = 1;
                    dispatchExclusiveCommand(@"Thumb", MAGICMOUSE, kGestureOwnerThumb);
                }
            }
            ret = tb + 1;
        } else if (type == 1) {
            NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
            [cursorWindow orderOut:nil];
            [pool release];
            type = 0;
            quickTabSwitching = 0;

            if ([commandForGesture(@"Thumb", MAGICMOUSE) isEqualToString:@"Middle Click"]) {
                CGEventRef ourEvent = CGEventCreate(NULL);
                CGPoint location = CGEventGetLocation(ourEvent);
                CFRelease(ourEvent);
                CGEventRef eventRef = CGEventCreateMouseEvent(NULL, kCGEventOtherMouseUp, location, kCGMouseButtonCenter);
                CGEventSetIntegerValueField(eventRef, kCGMouseEventButtonNumber, 2);
                CGEventPost(kCGSessionEventTap, eventRef);
                CFRelease(eventRef);
                simulating = 0;
            }
        }
    } else if (type == 1) {
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        [cursorWindow orderOut:nil];
        [pool release];
        type = 0;
        quickTabSwitching = 0;

        if ([commandForGesture(@"Thumb", MAGICMOUSE) isEqualToString:@"Middle Click"]) {
            CGEventRef ourEvent = CGEventCreate(NULL);
            CGPoint location = CGEventGetLocation(ourEvent);
            CFRelease(ourEvent);
            CGEventRef eventRef = CGEventCreateMouseEvent(NULL, kCGEventOtherMouseUp, location, kCGMouseButtonCenter);
            CGEventSetIntegerValueField(eventRef, kCGMouseEventButtonNumber, 2);
            CGEventPost(kCGSessionEventTap, eventRef);
            CFRelease(eventRef);
            simulating = 0;
        }
    }
    return ret;
}

static void gestureMagicMouseMiddleClick(const Finger *data, int nFingers) {
    middleClickFlag = (nFingers == 2 && (data[0].px > 0.47
                                         || (data[0].px > 0.35 && (data[0].px - data[1].px == 0 || (data[0].py - data[1].py) / (data[0].px - data[1].px) >= 0.16)) ))
                    || (nFingers == 1 && data[0].majorAxis > 10 && fabs(data[0].angle-1.5708) > 0.7854);
}

static int gestureMagicMouseOneFixOneTap(const Finger *data, int nFingers, double timestamp) {
    static double sttime = -1;
    static float fing[2][2];
    static int step = 0;
    static int fixId;
    static float avgx, avgy;

    if (CGEventSourceButtonState(kCGEventSourceStateHIDSystemState, kCGMouseButtonLeft)) {
        sttime = -1;
    }

    if (step == 0 && nFingers == 1) {
        step = 1;
        fixId = data[0].identifier;
        sttime = -1;
    } else if (step == 1) {
        if (nFingers == 2) {
            // A held anchor is already down well before the finger that taps
            // beside it. Two contacts that land together are an ordinary
            // two-finger tap, which reaches its own recognizer one frame later
            // and would otherwise lose the sequence to this one. Both use the
            // same interval, so a pair satisfies exactly one of them.
            int anchorIndex = data[0].identifier == fixId ? 0 :
                              data[1].identifier == fixId ? 1 : -1;
            BOOL anchorWasHeld = anchorIndex >= 0 &&
                MGContactOnsetTrackerContactArrivedAfter(&magicMouseContactOnsets,
                    fixId, data[1 - anchorIndex].identifier,
                    kMagicMouseTwoFingerTapMaximumOnsetSpread);
            if (!anchorWasHeld)
                MGTraceRecordCandidate(@"hold-tap", @"canceled", @"anchor-not-held");
            if (anchorWasHeld && fabs(data[0].py-data[1].py) < 0.25) {
                if (sttime < 0)
                    sttime = timestamp;
                if ((data[0].identifier == fixId || data[0].size > stvt / 10 + 0.2) &&
                   (data[1].identifier == fixId || data[1].size > stvt / 10 + 0.2)) {
                    step = 2;
                    avgx = (data[0].px + data[1].px) / 2;
                    avgy = (data[0].py + data[1].py) / 2;
                    fing[0][0] = data[0].px;
                    fing[0][1] = data[0].py;
                    fing[1][0] = data[1].px;
                    fing[1][1] = data[1].py;
                }
            } else
                step = 0;
        } else if (nFingers == 1) {
            sttime = -1;
            fixId = data[0].identifier;
        } else
            step = 0;
    } else if (step == 2) {
        if (nFingers == 1) {
            if (timestamp - sttime > clickSpeed)
                step = 0;
            else {
                if (data[0].identifier == fixId) {
                    // A hold-tap passes through the same two-contact shape as
                    // an ordinary tap. Once it wins, discard pending taps.
                    customMagicMouseTapSuppressionUntil = CFAbsoluteTimeGetCurrent() + 0.18;
                    if (avgx < data[0].px) {
                        if (fabs(avgx - data[0].px) > 0.22)
                            dispatchExclusiveCommand(@"Middle-Fix Index-Far-Tap", MAGICMOUSE, kGestureOwnerHoldTap);
                        else
                            dispatchExclusiveCommand(@"Middle-Fix Index-Near-Tap", MAGICMOUSE, kGestureOwnerHoldTap);
                    } else {
                        if (fabs(avgx - data[0].px) > 0.22)
                            dispatchExclusiveCommand(@"Index-Fix Middle-Far-Tap", MAGICMOUSE, kGestureOwnerHoldTap);
                        else
                            dispatchExclusiveCommand(@"Index-Fix Middle-Near-Tap", MAGICMOUSE, kGestureOwnerHoldTap);
                    }
                }
            }
            step = 0;
        } else if (nFingers == 2) {
            if (lenSqr(data[0].px, data[0].py, fing[0][0], fing[0][1]) > 0.0007 || lenSqr(data[1].px, data[1].py, fing[1][0], fing[1][1]) > 0.0007)
                step = 0;
        } else {
            step = 0;
        }
    }

    return 0;
}


static int magicMouseCallback(MGMultitouchDeviceRef device, Finger *data, int nFingers, double timestamp, int frame) {
    int ignore = 0;
    int activeMagicMouseContactCount = nFingers;
    int eligibleTapContactCount = nFingers;
    int eligibleClickContactCount = 0;
    int completedClickContactCount = 0;
    MGTraceContact traceContacts[16];
    int traceCount = 0;
    MGMagicMouseContactDecision traceQualityDecisions[16];
    BOOL traceExcludedAsThumb[16] = {NO};
    BOOL clickCluster = YES;

    if (!enAll || !enMMAll) {
        turnOffMagicMouse();
        return 0;
    }

    MGMouseClickInteractionObserveRawContacts(&magicMouseClickInteraction, nFingers);
    if (MGTraceIsActive()) {
        traceCount = MIN(nFingers, 16);
        for (int i = 0; i < traceCount; i++) {
            traceContacts[i] = (MGTraceContact){data[i].identifier, data[i].state,
                data[i].px, data[i].py, data[i].size, data[i].majorAxis,
                data[i].minorAxis, data[i].zDensity};
        }
    }

    int identifiers[16];
    int identifierCount = MIN(nFingers, 16);
    for (int i = 0; i < identifierCount; i++)
        identifiers[i] = data[i].identifier;
    MGContactOnsetTrackerObserve(&magicMouseContactOnsets, identifiers,
                                 identifierCount, timestamp);

    if (nFingers > 1) {
        for (int i = 0; i < nFingers; i++) {
            if (data[i].size > 5.5) {
                ignore = 1;
                break;
            }
        }
    }

    if (enMMHanded) {
        for (int i = 0; i < nFingers; i++)
            data[i].px = 1 - data[i].px;
    }

    magicMouseTwoFingerFlag = 0;
    magicMouseThreeFingerFlag = 0;
    disableHorizontalScroll = 0;
    if (!ignore) {
        int thumbPresent = gestureMagicMouseThumb(data, nFingers);
        observeBoundSwipeFamilies(MAGICMOUSE, nFingers - (thumbPresent ? 1 : 0));

        float clickXs[8], clickYs[8];
        float physicalXs[16], physicalYs[16];
        MGMagicMouseContactDecision physicalDecisions[16];
        int physicalIndexes[16];
        int physicalContactCount = 0;
        Finger tapData[16];
        int tapContactCount = 0;
        int thumbIndex = thumbPresent - 1;
        for (int i = 0; i < nFingers; i++) {
            BOOL excludedAsThumb = i == thumbIndex;
            MGMagicMouseContactDecision qualityDecision = MGMagicMouseContactDecisionForGeometry(
                data[i].px, data[i].py, data[i].size, data[i].minorAxis);
            BOOL excludedByQuality = qualityDecision != MGMagicMouseContactKept;
            if (i < traceCount) {
                traceQualityDecisions[i] = qualityDecision;
                traceExcludedAsThumb[i] = excludedAsThumb;
            }
            if (excludedAsThumb)
                continue;
            if (physicalContactCount < 16) {
                physicalXs[physicalContactCount] = data[i].px;
                physicalYs[physicalContactCount] = data[i].py;
                physicalDecisions[physicalContactCount] = qualityDecision;
                physicalIndexes[physicalContactCount] = i;
                physicalContactCount++;
            }
            if (excludedByQuality)
                continue;
            if (tapContactCount < 16)
                tapData[tapContactCount++] = data[i];
            if (eligibleClickContactCount < 8) {
                clickXs[eligibleClickContactCount] = data[i].px;
                clickYs[eligibleClickContactCount] = data[i].py;
                eligibleClickContactCount++;
            }
        }
        int rescuedPhysicalIndex = MGMagicMouseClusteredThirdFingerIndex(
            physicalXs, physicalYs, physicalDecisions, physicalContactCount);
        int rescuedDataIndex = rescuedPhysicalIndex >= 0
            ? physicalIndexes[rescuedPhysicalIndex] : -1;
        if (rescuedDataIndex >= 0 && eligibleClickContactCount < 8) {
            clickXs[eligibleClickContactCount] = data[rescuedDataIndex].px;
            clickYs[eligibleClickContactCount] = data[rescuedDataIndex].py;
            eligibleClickContactCount++;
        }
        clickCluster = MGMagicMouseContactsFormClickCluster(
            clickXs, clickYs, eligibleClickContactCount);
        if (!clickCluster)
            eligibleClickContactCount = 0;
        magicMouseTwoFingerFlag = eligibleClickContactCount == 2;
        magicMouseThreeFingerFlag = eligibleClickContactCount == 3;

        completedClickContactCount = MGMouseClickInteractionObserveContacts(
            &magicMouseClickInteraction, eligibleClickContactCount,
            CFAbsoluteTimeGetCurrent());

        if (MGTraceIsActive()) {
            MGTraceRecordMouseFrame(device, timestamp, frame, traceContacts, traceCount);
            for (int i = 0; i < traceCount; i++) {
                MGMagicMouseContactDecision qualityDecision = traceQualityDecisions[i];
                BOOL excludedAsThumb = traceExcludedAsThumb[i];
                BOOL excludedByQuality = qualityDecision != MGMagicMouseContactKept;
                BOOL rescuedForClick = i == rescuedDataIndex;
                MGTraceRecordFilterDecision(data[i].identifier,
                    excludedAsThumb ? @"thumb-id" : rescuedForClick
                        ? @"side-narrow-clustered-third"
                        : MGMagicMouseContactDecisionName(qualityDecision),
                    rescuedForClick || !(excludedAsThumb || excludedByQuality), data[i].px, data[i].py,
                    data[i].size, data[i].majorAxis, data[i].minorAxis);
            }
            if (!clickCluster)
                MGTraceRecordCandidate(@"physical-click", @"canceled", @"disconnected-click-cluster");
        }

        eligibleTapContactCount = tapContactCount;
        gestureMagicMouseOneFingerSwipe(data, nFingers, timestamp);
        gestureMagicMouseTwoFingerSwipe(data, nFingers, timestamp, thumbPresent);
        gestureMagicMouseThreeFingerTap(tapData, tapContactCount, timestamp, 0);
        gestureMagicMouseTwoFingerTap(tapData, tapContactCount, timestamp, 0);
        gestureMagicMouseRightFrontTap(data, nFingers, timestamp);
        gestureMagicMouseOneFingerTap(tapData, tapContactCount, timestamp);
        gestureMagicMouseSwipeThreeFingers(data, nFingers, timestamp, thumbPresent);
        gestureMagicMouseTwoFingers(data, nFingers, timestamp, thumbPresent);
        gestureMagicMouseOneFixOneTap(tapData, tapContactCount, timestamp);
        gestureMagicMouseV(data, nFingers);
        gestureMagicMouseTwoFixOneSlide(data, nFingers, timestamp, thumbPresent);
        gestureMagicMouseMiddleClick(data, nFingers);
    } else {
        completedClickContactCount = MGMouseClickInteractionObserveContacts(
            &magicMouseClickInteraction, 0, CFAbsoluteTimeGetCurrent());
        if (MGTraceIsActive()) {
            MGTraceRecordMouseFrame(device, timestamp, frame, traceContacts, traceCount);
            MGTraceRecordCandidate(@"physical-click", @"canceled", @"broad-contact-size");
        }
    }

    if (logLevel >= LOG_LEVEL_DEBUG &&
        eligibleClickContactCount != lastLoggedMagicMouseClickContactCount) {
        NSLog(@"Magic Mouse eligible click contacts: %d", eligibleClickContactCount);
        lastLoggedMagicMouseClickContactCount = eligibleClickContactCount;
    }
    dispatchMagicMousePhysicalClickForContactCount(completedClickContactCount);

    // Release when the contacts a tap recognizer can see are gone, not when the
    // raw count reaches zero. A resting finger the filter excludes cannot form
    // a tap, and a hand often stays on the mouse for many seconds after a
    // click, so waiting for a bare surface suppressed taps long after the
    // clicking fingers had lifted. The button check keeps the flag through the
    // click itself, whose own fingers may be briefly filtered mid-press.
    if (eligibleTapContactCount == 0 &&
        !CGEventSourceButtonState(kCGEventSourceStateHIDSystemState, kCGMouseButtonLeft) &&
        !CGEventSourceButtonState(kCGEventSourceStateHIDSystemState, kCGMouseButtonRight))
        magicMouseTapsSuppressedUntilLift = NO;

    NSUInteger ownerBeforeFinish = magicMouseSequence.owner;
    MGGestureSequenceFinishFrame(&magicMouseSequence, activeMagicMouseContactCount);
    if (ownerBeforeFinish != magicMouseSequence.owner)
        MGTraceRecordOwnership(@"reset", gestureOwnerName(ownerBeforeFinish),
                               gestureOwnerName(magicMouseSequence.owner), YES);

    return 0;
}



#pragma mark - Trackpad area clicks

// Area-click regions in normalized trackpad coordinates: x and y run 0..1
// with the origin at the bottom-left, matching the raw contact frames. The
// regions are absolute surface positions, so dominant-hand mirroring does not
// apply. Starter geometry; these thresholds await hardware validation.
// The configurable trackpad-edge-gesture-depth setting sets how far an edge band reaches
// into the surface. Corner squares span twice that, giving a corner target
// larger than the bands it overrides. The default stays narrow so bands sit
// under the bezel-adjacent strip a resting hand rarely clicks.
#define kTrackpadAreaEdgeBandDepth (areaClickDepth)
#define kTrackpadAreaCornerSize (areaClickDepth * 2.0f)

static NSString *trackpadAreaCornerClickName(float x, float y) {
    BOOL left = x <= kTrackpadAreaCornerSize;
    BOOL right = x >= 1.0f - kTrackpadAreaCornerSize;
    BOOL bottom = y <= kTrackpadAreaCornerSize;
    BOOL top = y >= 1.0f - kTrackpadAreaCornerSize;
    if (top && left) return @"Top-Left-Corner Click";
    if (top && right) return @"Top-Right-Corner Click";
    if (bottom && left) return @"Bottom-Left-Corner Click";
    if (bottom && right) return @"Bottom-Right-Corner Click";
    return nil;
}

enum {
    kTrackpadAreaEdgeLeft = 0,
    kTrackpadAreaEdgeRight,
    kTrackpadAreaEdgeTop,
    kTrackpadAreaEdgeBottom,
};

// span runs along the edge: bottom to top on a vertical edge, left to right
// on a horizontal one, so the slugs read as English.
static NSString *trackpadAreaEdgeThirdName(int edge, float span) {
    BOOL high = span >= 2.0f / 3.0f;
    BOOL low = span < 1.0f / 3.0f;
    switch (edge) {
        case kTrackpadAreaEdgeLeft:
            return high ? @"Left-Edge Top-Third Click"
                 : low ? @"Left-Edge Bottom-Third Click" : @"Left-Edge Middle-Third Click";
        case kTrackpadAreaEdgeRight:
            return high ? @"Right-Edge Top-Third Click"
                 : low ? @"Right-Edge Bottom-Third Click" : @"Right-Edge Middle-Third Click";
        case kTrackpadAreaEdgeTop:
            return high ? @"Top-Edge Right-Third Click"
                 : low ? @"Top-Edge Left-Third Click" : @"Top-Edge Middle-Third Click";
        default:
            return high ? @"Bottom-Edge Right-Third Click"
                 : low ? @"Bottom-Edge Left-Third Click" : @"Bottom-Edge Middle-Third Click";
    }
}

static NSString *trackpadAreaEdgeHalfName(int edge, float span) {
    BOOL high = span >= 0.5f;
    switch (edge) {
        case kTrackpadAreaEdgeLeft:
            return high ? @"Left-Edge Top-Half Click" : @"Left-Edge Bottom-Half Click";
        case kTrackpadAreaEdgeRight:
            return high ? @"Right-Edge Top-Half Click" : @"Right-Edge Bottom-Half Click";
        case kTrackpadAreaEdgeTop:
            return high ? @"Top-Edge Right-Half Click" : @"Top-Edge Left-Half Click";
        default:
            return high ? @"Bottom-Edge Right-Half Click" : @"Bottom-Edge Left-Half Click";
    }
}

static NSString *trackpadAreaEdgeWholeName(int edge) {
    switch (edge) {
        case kTrackpadAreaEdgeLeft: return @"Left-Edge Click";
        case kTrackpadAreaEdgeRight: return @"Right-Edge Click";
        case kTrackpadAreaEdgeTop: return @"Top-Edge Click";
        default: return @"Bottom-Edge Click";
    }
}

// Resolves the most specific bound region containing a single-contact click:
// a bound named corner, then the any-corner name, beats any edge region; a
// bound third beats a bound half beats the whole edge, and the any-edge name
// comes last. Where two edge bands overlap near a corner and no corner is
// bound, the nearer edge is tried first at each span size. Returns nil when
// no bound region contains the click, which leaves it native.
static NSString *boundTrackpadAreaClickGesture(float x, float y) {
    NSString *corner = trackpadAreaCornerClickName(x, y);
    if (corner != nil && bindingForGesture(corner, TRACKPAD) != nil)
        return corner;
    if (corner != nil && bindingForGesture(@"Any-Corner Click", TRACKPAD) != nil)
        return @"Any-Corner Click";

    int edges[2];
    float spans[2], distances[2];
    int edgeCount = 0;
    if (x <= kTrackpadAreaEdgeBandDepth) {
        edges[edgeCount] = kTrackpadAreaEdgeLeft;
        spans[edgeCount] = y;
        distances[edgeCount++] = x;
    } else if (x >= 1.0f - kTrackpadAreaEdgeBandDepth) {
        edges[edgeCount] = kTrackpadAreaEdgeRight;
        spans[edgeCount] = y;
        distances[edgeCount++] = 1.0f - x;
    }
    if (y >= 1.0f - kTrackpadAreaEdgeBandDepth) {
        edges[edgeCount] = kTrackpadAreaEdgeTop;
        spans[edgeCount] = x;
        distances[edgeCount++] = 1.0f - y;
    } else if (y <= kTrackpadAreaEdgeBandDepth) {
        edges[edgeCount] = kTrackpadAreaEdgeBottom;
        spans[edgeCount] = x;
        distances[edgeCount++] = y;
    }
    if (edgeCount == 0)
        return nil;
    if (edgeCount == 2 && distances[1] < distances[0]) {
        int edge = edges[0]; edges[0] = edges[1]; edges[1] = edge;
        float span = spans[0]; spans[0] = spans[1]; spans[1] = span;
    }

    for (int i = 0; i < edgeCount; i++) {
        NSString *third = trackpadAreaEdgeThirdName(edges[i], spans[i]);
        if (bindingForGesture(third, TRACKPAD) != nil)
            return third;
    }
    for (int i = 0; i < edgeCount; i++) {
        NSString *half = trackpadAreaEdgeHalfName(edges[i], spans[i]);
        if (bindingForGesture(half, TRACKPAD) != nil)
            return half;
    }
    for (int i = 0; i < edgeCount; i++) {
        NSString *whole = trackpadAreaEdgeWholeName(edges[i]);
        if (bindingForGesture(whole, TRACKPAD) != nil)
            return whole;
    }
    if (bindingForGesture(@"Any-Edge Click", TRACKPAD) != nil)
        return @"Any-Edge Click";
    return nil;
}

#pragma mark - CGEventCallback

static CGEventRef CGEventCallback(CGEventTapProxy proxy, CGEventType type, CGEventRef event, void *refcon) {
    if (CGEventGetIntegerValueField(event, kCGEventSourceUserData) ==
        kTrickpadReplayedMouseEvent)
        return event;
    BOOL physicalMouseDown = type == kCGEventLeftMouseDown || type == kCGEventRightMouseDown;
    MGMouseClickEligibilitySnapshot mouseDownEligibility = {0};
    int replacementMagicMouseContactCount = 0;
    BOOL hasConfiguredMagicMousePhysicalClick = NO;
    if (physicalMouseDown) {
        MGMouseClickInteractionBegin(&magicMouseClickInteraction,
                                     CFAbsoluteTimeGetCurrent());
        mouseDownEligibility =
            MGMouseClickInteractionEligibilitySnapshot(&magicMouseClickInteraction);
        BOOL hasTwoFingerBinding =
            bindingForGesture(@"Two-Finger Click", MAGICMOUSE) != nil;
        BOOL hasThreeFingerBinding =
            bindingForGesture(@"Three-Finger Click", MAGICMOUSE) != nil;
        hasConfiguredMagicMousePhysicalClick =
            hasTwoFingerBinding || hasThreeFingerBinding;
        BOOL rawCandidate =
            (mouseDownEligibility.rawContactCount == 2 && hasTwoFingerBinding) ||
            (mouseDownEligibility.rawContactCount == 3 && hasThreeFingerBinding);
        if (!MGTraceIsActive() && rawCandidate) {
            useconds_t waited = 0;
            while (mouseDownEligibility.stage == MGMouseClickEligibilityFilterPending &&
                   waited < kMagicMouseClickClassificationWaitMicroseconds) {
                usleep(kMagicMouseClickClassificationPollMicroseconds);
                waited += kMagicMouseClickClassificationPollMicroseconds;
                mouseDownEligibility =
                    MGMouseClickInteractionEligibilitySnapshot(&magicMouseClickInteraction);
            }
            replacementMagicMouseContactCount = MGMouseClickReplacementContactCount(
                mouseDownEligibility, hasTwoFingerBinding, hasThreeFingerBinding);
        }
    }
    NSString *traceCGEvent = nil;
    if (type == kCGEventLeftMouseDown || type == kCGEventRightMouseDown) traceCGEvent = @"mouse-down";
    else if (type == kCGEventLeftMouseUp || type == kCGEventRightMouseUp) traceCGEvent = @"mouse-up";
    else if (type == kCGEventLeftMouseDragged || type == kCGEventRightMouseDragged ||
             type == kCGEventOtherMouseDragged) traceCGEvent = @"mouse-drag";
    else if (type == kCGEventScrollWheel) traceCGEvent = @"scroll";
    if (traceCGEvent != nil) {
        int64_t axis1 = type == kCGEventScrollWheel
            ? CGEventGetIntegerValueField(event, kCGScrollWheelEventDeltaAxis1)
            : [traceCGEvent isEqualToString:@"mouse-drag"]
                ? CGEventGetIntegerValueField(event, kCGMouseEventDeltaX) : 0;
        int64_t axis2 = type == kCGEventScrollWheel
            ? CGEventGetIntegerValueField(event, kCGScrollWheelEventDeltaAxis2)
            : [traceCGEvent isEqualToString:@"mouse-drag"]
                ? CGEventGetIntegerValueField(event, kCGMouseEventDeltaY) : 0;
        MGTraceRecordCGEvent(traceCGEvent,
            CGEventGetDoubleValueField(event, kCGMouseEventPressure),
            axis1, axis2,
            @"observed");
    }
    if (physicalMouseDown) {
        NSString *stage = @"no-raw-contacts";
        if (mouseDownEligibility.stage == MGMouseClickEligibilityFilterPending)
            stage = @"filter-pending";
        else if (mouseDownEligibility.stage == MGMouseClickEligibilityFilteredOut)
            stage = @"filtered-out";
        else if (mouseDownEligibility.stage == MGMouseClickEligibilityAvailable)
            stage = @"available";
        MGTraceRecordClickEligibility(stage, mouseDownEligibility.rawContactCount,
                                      mouseDownEligibility.eligibleContactCount);
    }
    if (trackpadRewritingSecondaryClick && type == kCGEventRightMouseDragged) {
        CGEventSetIntegerValueField(event, kCGMouseEventButtonNumber, 0);
        CGEventSetType(event, kCGEventLeftMouseDragged);
        type = kCGEventLeftMouseDragged;
    } else if (trackpadRewritingSecondaryClick && type == kCGEventRightMouseUp) {
        CGEventSetIntegerValueField(event, kCGMouseEventButtonNumber, 0);
        CGEventSetType(event, kCGEventLeftMouseUp);
        type = kCGEventLeftMouseUp;
    }

    if (type == kCGEventLeftMouseDragged || type == kCGEventRightMouseDragged) {
        MGTrackpadInteractionRecordPhysicalDrag(&trackpadInteraction);
        // A suppressed trackpad click that becomes a drag keeps its native
        // events: restore the held mouse-down before the drag passes through.
        replayPendingTrackpadPrimaryDown();
        MGMouseClickInteractionRecordDrag(&magicMouseClickInteraction,
            (int)CGEventGetIntegerValueField(event, kCGMouseEventDeltaX),
            (int)CGEventGetIntegerValueField(event, kCGMouseEventDeltaY));
    }

    if ((type == kCGEventLeftMouseUp || type == kCGEventRightMouseUp) &&
        MGTrackpadInteractionHasPhysicalClick(&trackpadInteraction)) {
        BOOL trackpadClickReplacedNative = pendingTrackpadPrimaryDown != NULL;
        clearPendingTrackpadClick();
        int trackpadClickFingerCount =
            MGTrackpadInteractionFinishPhysicalClick(&trackpadInteraction);
        NSString *gesture = nil;
        int device = TRACKPAD;
        if (trackpadClickFingerCount == 3)
            gesture = @"Three-Finger Click";
        else if (trackpadClickFingerCount == 4)
            gesture = @"Four-Finger Click";
        else if (trackpadClickFingerCount == 1 && pendingTrackpadAreaClickGesture != nil)
            gesture = pendingTrackpadAreaClickGesture;
        // The configured action dispatches only when its mouse-down was
        // suppressed, and its mouse-up is swallowed with it. A click whose
        // native down passed through stays native and does not dispatch.
        if (gesture != nil && (trackpadClickReplacedNative || MGTraceIsActive()))
            dispatchCommand(gesture, device);
        [pendingTrackpadAreaClickGesture release];
        pendingTrackpadAreaClickGesture = nil;
        trackpadRewritingSecondaryClick = NO;
        if (trackpadClickReplacedNative)
            return NULL;
    }

    // A click and a tap are the same contacts, so the fingers that performed a
    // click must not go on to read as a tap. Fingers commonly rest for a moment
    // after the button releases, which outlasts any fixed window, so this holds
    // until the hand leaves the surface.
    if (type == kCGEventLeftMouseDown || type == kCGEventLeftMouseUp ||
        type == kCGEventRightMouseDown || type == kCGEventRightMouseUp) {
        magicMouseTapsSuppressedUntilLift = YES;
    }

    if (type == kCGEventLeftMouseDown || type == kCGEventRightMouseDown) {
        if (logLevel >= LOG_LEVEL_DEBUG)
            NSLog(@"Physical mouse down; Magic Mouse contacts: two=%d three=%d",
                  magicMouseTwoFingerFlag, magicMouseThreeFingerFlag);
        BOOL trackpadClickBegan = MGTrackpadInteractionBeginPhysicalClick(
            &trackpadInteraction,
            CGEventGetDoubleValueField(event, kCGMouseEventPressure),
            kGestureOwnerPhysicalClick);
        if (trackpadClickBegan)
            trackpadClicked = 1;
        NSString *trackpadAreaClickGesture = nil;
        float trackpadAreaClickX = 0, trackpadAreaClickY = 0;
        if (trackpadClickBegan &&
            MGTrackpadInteractionPendingSingleContactClickPosition(
                &trackpadInteraction, &trackpadAreaClickX, &trackpadAreaClickY))
            trackpadAreaClickGesture = boundTrackpadAreaClickGesture(
                trackpadAreaClickX, trackpadAreaClickY);
        [pendingTrackpadAreaClickGesture release];
        pendingTrackpadAreaClickGesture = [trackpadAreaClickGesture retain];
        BOOL configuredTrackpadClick = trackpadClickBegan &&
            (trackpadAreaClickGesture != nil ||
             MGTrackpadInteractionShouldPreservePrimaryClick(
                &trackpadInteraction,
                bindingForGesture(@"Three-Finger Click", TRACKPAD) != nil,
                bindingForGesture(@"Four-Finger Click", TRACKPAD) != nil));
        if (configuredTrackpadClick && type == kCGEventRightMouseDown) {
            CGEventSetIntegerValueField(event, kCGMouseEventButtonNumber, 0);
            CGEventSetType(event, kCGEventLeftMouseDown);
            type = kCGEventLeftMouseDown;
            trackpadRewritingSecondaryClick = YES;
        }

        if (isTrackpadRecognizing) {
            cancelRecognition = 1;
            return NULL;
        }
        if (simulating) {   //simulating should be reset when mouseup, but sometimes mouseup doesn't get called
            simulating = 0; //so we have to reset it manually
            clearPendingMagicMouseClick();
        }
        // A confidently recognized configured trackpad click replaces the
        // native click: suppress its mouse-down and hold a copy so a drag
        // can restore the native sequence. An ambiguous click never begins
        // a physical click here, so it passes through untouched.
        clearPendingTrackpadClick();
        if (configuredTrackpadClick && !MGTraceIsActive()) {
            pendingTrackpadPrimaryDown = CGEventCreateCopy(event);
            return NULL;
        }
        NSString *gesture = nil;
        int device = 0;
        NSUInteger mouseOwnerBeforeClick = magicMouseSequence.owner;
        if (replacementMagicMouseContactCount == 2)
            gesture = @"Two-Finger Click";
        else if (replacementMagicMouseContactCount == 3)
            gesture = @"Three-Finger Click";
        if (gesture != nil) {
            if (!MGGestureSequenceTryClaim(&magicMouseSequence, kGestureOwnerPhysicalClick))
                gesture = nil;
            else
                device = MAGICMOUSE;
        } else if (middleClickFlag && bindingForGesture(@"Middle Click", MAGICMOUSE) != nil) {
            gesture = @"Middle Click";
            device = MAGICMOUSE;
        }
        if (gesture != nil) {
            MGTraceRecordCandidate(gesture, @"recognized", @"contacts-present-at-mouse-down");
            MGTraceRecordOwnership(@"physical-click", gestureOwnerName(mouseOwnerBeforeClick),
                                   gestureOwnerName(magicMouseSequence.owner), YES);
        } else if (MGTraceIsActive()) {
            MGTraceRecordCandidate(@"physical-click", @"canceled", @"no-eligible-configured-contact-count");
            if ((magicMouseTwoFingerFlag || magicMouseThreeFingerFlag) && mouseOwnerBeforeClick != 0)
                MGTraceRecordOwnership(@"physical-click", gestureOwnerName(mouseOwnerBeforeClick),
                                       gestureOwnerName(magicMouseSequence.owner), NO);
        }
        if (gesture != nil) {
            MGMouseClickInteractionMarkHandled(&magicMouseClickInteraction);
            NSString *command = commandForGesture(gesture, device);
            if (MGTraceSuppressesActions()) {
                if (bindingForGesture(gesture, device) != nil)
                    dispatchCommand(gesture, device);
                else
                    MGTraceRecordDispatch(gesture, @"none", @"none", @"suppressed-for-trace");
            } else if ([command isEqualToString:@"Middle Click"]) {
                simulating = MIDDLEBUTTONDOWN;
                simulatingByDevice = device;
                CGEventSetIntegerValueField(event, kCGMouseEventButtonNumber, 2);
                CGEventSetType(event, kCGEventOtherMouseDown);
            } else if ([command isEqualToString:@"Left Click"]) {
                simulating = LEFTBUTTONDOWN;
                CGEventSetIntegerValueField(event, kCGMouseEventButtonNumber, 0);
                CGEventSetType(event, kCGEventLeftMouseDown);
            } else if ([command isEqualToString:@"Right Click"]) {
                simulating = RIGHTBUTTONDOWN;
                CGEventSetIntegerValueField(event, kCGMouseEventButtonNumber, 1);
                CGEventSetType(event, kCGEventRightMouseDown);
            } else if ([command isEqualToString:@"Open Link in New Tab"]) {
                simulating = COMMANDANDLEFTBUTTONDOWN;
                CGEventSetIntegerValueField(event, kCGMouseEventButtonNumber, 0);
                CGEventSetFlags(event, kCGEventFlagMaskCommand);
                CGEventSetType(event, kCGEventLeftMouseDown);
            } else if (command == nil) {
            } else { // command that will be done by this case must not create a new click event
                simulating = IGNOREMOUSE;
                if (replacementMagicMouseContactCount > 0) {
                    pendingMagicMousePrimaryDown = CGEventCreateCopy(event);
                    pendingMagicMouseClickGesture = [gesture copy];
                } else {
                    dispatchCommand(gesture, device);
                }
                return NULL;
            }
            if (!MGTraceIsActive() && command != nil && logLevel >= LOG_LEVEL_INFO)
                NSLog(@"Gesture \"%@\" -> \"%@\" for %@", gesture, command, deviceTypeName[device]);
        } else if (!MGTraceIsActive() && hasConfiguredMagicMousePhysicalClick) {
            // Once native mouse-down passes through, a later touch frame must not
            // dispatch the configured action over an already-delivered click.
            MGMouseClickInteractionMarkHandled(&magicMouseClickInteraction);
        }


        if (moveResizeFlag) {
            shouldExitMoveResize = 1;
            return NULL;
        }

    } else if (type == kCGEventLeftMouseUp || type == kCGEventRightMouseUp) {
        BOOL magicMouseClickDragged =
            MGMouseClickInteractionHasDragged(&magicMouseClickInteraction);
        int lateMagicMouseClickContactCount =
            MGMouseClickInteractionFinish(&magicMouseClickInteraction);
        if (logLevel >= LOG_LEVEL_DEBUG)
            NSLog(@"Physical mouse up; correlated Magic Mouse contacts: %d",
                  lateMagicMouseClickContactCount);
        dispatchMagicMousePhysicalClickForContactCount(
            lateMagicMouseClickContactCount);

        if (simulating == MIDDLEBUTTONDOWN) {
            CGEventSetIntegerValueField(event, kCGMouseEventButtonNumber, 2);
            CGEventSetType(event, kCGEventOtherMouseUp);
            simulating = 0;
            if (logLevel >= LOG_LEVEL_DEBUG) NSLog(@"Simulated MiddleMouseUp");
        } else if (simulating == LEFTBUTTONDOWN) {
            CGEventSetIntegerValueField(event, kCGMouseEventButtonNumber, 0);
            CGEventSetType(event, kCGEventLeftMouseUp);
            simulating = 0;
            if (logLevel >= LOG_LEVEL_DEBUG) NSLog(@"Simulated LeftMouseUp");
        } else if (simulating == RIGHTBUTTONDOWN) {
            CGEventSetIntegerValueField(event, kCGMouseEventButtonNumber, 1);
            CGEventSetType(event, kCGEventRightMouseUp);
            simulating = 0;
            if (logLevel >= LOG_LEVEL_DEBUG) NSLog(@"Simulated RightMouseUp");
        } else if (simulating == COMMANDANDLEFTBUTTONDOWN) {
            CGEventSetIntegerValueField(event, kCGMouseEventButtonNumber, 0);
            CGEventSetFlags(event, kCGEventFlagMaskCommand);
            CGEventSetType(event, kCGEventLeftMouseUp);
            simulating = 0;
            if (logLevel >= LOG_LEVEL_DEBUG) NSLog(@"Simulated CommandLeftMouseUp");
        } else if (simulating == IGNOREMOUSE) {
            if (pendingMagicMouseClickGesture != nil && !magicMouseClickDragged)
                dispatchExclusiveCommand(pendingMagicMouseClickGesture, MAGICMOUSE,
                                         kGestureOwnerPhysicalClick);
            clearPendingMagicMouseClick();
            simulating = 0;
            return NULL;
        }

    } else if (type == kCGEventScrollWheel) {
        int64_t axis1 = CGEventGetIntegerValueField(event, kCGScrollWheelEventDeltaAxis1);
        int64_t pointAxis1 = CGEventGetIntegerValueField(event, kCGScrollWheelEventPointDeltaAxis1);
        int64_t fixedAxis1 = CGEventGetIntegerValueField(event, kCGScrollWheelEventFixedPtDeltaAxis1);
        int64_t axis2 = CGEventGetIntegerValueField(event, kCGScrollWheelEventDeltaAxis2);
        int64_t pointAxis2 = CGEventGetIntegerValueField(event, kCGScrollWheelEventPointDeltaAxis2);
        int64_t fixedAxis2 = CGEventGetIntegerValueField(event, kCGScrollWheelEventFixedPtDeltaAxis2);
        if (axis1 != 0 || pointAxis1 != 0 || fixedAxis1 != 0 ||
            axis2 != 0 || pointAxis2 != 0 || fixedAxis2 != 0) {
            CFAbsoluteTime suppressionUntil = CFAbsoluteTimeGetCurrent() + kMagicMouseTapSuppressionAfterScroll;
            if (suppressionUntil > customMagicMousePrimaryTapSuppressionUntil) {
                customMagicMousePrimaryTapSuppressionUntil = suppressionUntil;
            }
        }
        // Momentum events arrive after the fingers leave the device, so the
        // phase distinguishes a scroll the hand is still driving from its
        // inertia. Both sequences see every event, because either may be
        // holding suppression over its own momentum.
        int64_t scrollPhase = CGEventGetIntegerValueField(event, kCGScrollWheelEventScrollPhase);
        int64_t momentumPhase = CGEventGetIntegerValueField(event, kCGScrollWheelEventMomentumPhase);
        BOOL mouseArmed = MGGestureSequenceSuppressesScrollEvent(&magicMouseSequence,
                                                                 scrollPhase, momentumPhase);
        BOOL trackpadArmed = MGTrackpadInteractionSuppressesScrollEvent(&trackpadInteraction,
                                                                        scrollPhase, momentumPhase);
        if (logLevel >= LOG_LEVEL_DEBUG) {
            NSLog(@"Scroll event phase=%lld momentum=%lld axis1=%lld axis2=%lld "
                  @"mouseArmed=%d trackpadArmed=%d trackpadRecognizing=%d -> %@",
                  scrollPhase, momentumPhase, axis1, axis2,
                  mouseArmed, trackpadArmed, isTrackpadRecognizing,
                  (mouseArmed || trackpadArmed || isTrackpadRecognizing) ? @"dropped" : @"delivered");
        }
        if (mouseArmed || trackpadArmed || isTrackpadRecognizing) {
            MGTraceRecordCGEvent(@"scroll", 0, axis1, axis2, @"suppressed-by-recognizer");
            return NULL;
        }
        else if (autoScrollFlag) {
            int64_t sc = CGEventGetIntegerValueField(event, kCGScrollWheelEventDeltaAxis1);
            if (sc*autoScrollFlag <= 0)
                return NULL;
        } else if (customMagicMouseScrollSuppressionUntil > CFAbsoluteTimeGetCurrent()) {
            if (axis2 != 0 || pointAxis2 != 0 || fixedAxis2 != 0)
                return NULL;
        } else if (disableHorizontalScroll) {
            CGEventSetIntegerValueField(event, kCGScrollWheelEventDeltaAxis2, 0);
            CGEventSetIntegerValueField(event, kCGScrollWheelEventPointDeltaAxis2, 0);
            CGEventSetIntegerValueField(event, kCGScrollWheelEventFixedPtDeltaAxis2, 0);
        }
        else if ((trackpadNFingers == 3 || trackpadNFingers == 4) && simulating == MIDDLEBUTTONDOWN)
            return NULL;
    } else if (type == kCGEventMouseMoved) {
        if (quickTabSwitching) {
            selectSafariTab();
        } else if (simulating == MIDDLEBUTTONDOWN) {
            CGEventSetIntegerValueField(event, kCGMouseEventButtonNumber, 2);
            CGEventSetType(event, kCGEventOtherMouseDragged);
        }
    } else if (type == kCGEventLeftMouseDragged || type == kCGEventRightMouseDragged) {
        if (simulating == IGNOREMOUSE) {
            if (pendingMagicMousePrimaryDown != NULL &&
                MGMouseClickInteractionHasDragged(&magicMouseClickInteraction)) {
                replayPendingMagicMousePrimaryDown();
                simulating = 0;
                return event;
            }
            return NULL;
        } else if (simulating == MIDDLEBUTTONDOWN) {
            CGEventSetIntegerValueField(event, kCGMouseEventButtonNumber, 2);
            CGEventSetType(event, kCGEventOtherMouseDragged);
        }
    } else if (type == kCGEventTapDisabledByUserInput) {
        CGEventTapEnable(eventTap, true);
    } else if (type == kCGEventTapDisabledByTimeout) {
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
            if (recreatingEventTap) return;
            recreatingEventTap = TRUE;
            NSLog(@"Received kCGEventTapDisabledByTimeout; attempting to recreate CGEventTap. Allow Trickpad in System Settings -> Privacy & Security -> Accessibility.");
            CFMachPortInvalidate(eventTap);
            CFRelease(eventTap);
            eventTap = [me createEventTap];
            if (eventTap == nil) {
                NSLog(@"Could not create CGEventTap. Scheduling retries.");
                eventTapTries = 0;
                [NSTimer scheduledTimerWithTimeInterval:1.0 target:me selector:@selector(createEventTapTimer:) userInfo:nil repeats:NO];
            } else {
                recreatingEventTap = FALSE;
            }
        });
        return NULL;
    }



    if (enCharRegMM) {

        CGEventType nType = CGEventGetType(event);
        static int freePass = 0;

        CGEventType mouseDown, mouseUp, mouseDrag;
        if (charRegMouseButton == 0) {
            mouseDown = kCGEventOtherMouseDown;
            mouseUp = kCGEventOtherMouseUp;
            mouseDrag = kCGEventOtherMouseDragged;
        } else if (charRegMouseButton == 1) {
            mouseDown = kCGEventRightMouseDown;
            mouseUp = kCGEventRightMouseUp;
            mouseDrag = kCGEventRightMouseDragged;
        }
        if (!freePass) {
            if (nType == mouseDown) {
                return NULL;
            } else if ((nType == mouseDrag) &&
                       (!simulating || (simulating == MIDDLEBUTTONDOWN && simulatingByDevice != TRACKPAD)))
            {
                CGPoint tmp = CGEventGetLocation(event);

                if (!isMouseRecognizing) {
                    isMouseRecognizing = 1;
                    mouseRecognizer(tmp.x, -tmp.y, 0);
                } else {
                    if (mouseRecognizer(tmp.x, -tmp.y, 1))
                        isMouseRecognizing = 2;
                }
                return NULL;
            } else if (nType == mouseUp) {
                if (isMouseRecognizing == 2) {
                    CGPoint tmp = CGEventGetLocation(event);
                    mouseRecognizer((float)tmp.x, -(float)tmp.y, 2);
                } else {
                    freePass = 1;
                    CGEventRef eventRef;

                    CGEventRef ourEvent = CGEventCreate(NULL);
                    CGPoint location = CGEventGetLocation(ourEvent);
                    CFRelease(ourEvent);

                    if (charRegMouseButton == 0) { // Middle
                        eventRef = CGEventCreateMouseEvent(NULL, kCGEventOtherMouseDown, location, kCGMouseButtonCenter);
                        CGEventSetIntegerValueField(eventRef, kCGMouseEventButtonNumber, 2);
                        CGEventPost(kCGSessionEventTap, eventRef);
                        CFRelease(eventRef);

                        eventRef = CGEventCreateMouseEvent(NULL, kCGEventOtherMouseUp, location, kCGMouseButtonCenter);
                        CGEventPost(kCGSessionEventTap, eventRef);
                        CFRelease(eventRef);
                    } else if (charRegMouseButton == 1) {
                        eventRef = CGEventCreateMouseEvent(NULL, kCGEventRightMouseDown, location, kCGMouseButtonRight);
                        CGEventPost(kCGSessionEventTap, eventRef);
                        CFRelease(eventRef);

                        eventRef = CGEventCreateMouseEvent(NULL, kCGEventRightMouseUp, location, kCGMouseButtonRight);
                        CGEventPost(kCGSessionEventTap, eventRef);
                        CFRelease(eventRef);
                    }
                }
                isMouseRecognizing = 0;
                return NULL;
            }
        } else if (nType == mouseUp)
            freePass = 0;
    }

    return event;
}

- (CFMachPortRef)createEventTap {
    CGEventMask eventMask;
    CFRunLoopSourceRef runLoopSource;

    eventMask = CGEventMaskBit(kCGEventScrollWheel) |
    CGEventMaskBit(kCGEventMouseMoved) |
    CGEventMaskBit(kCGEventLeftMouseDown) |
    CGEventMaskBit(kCGEventLeftMouseUp) |
    CGEventMaskBit(kCGEventRightMouseDown) |
    CGEventMaskBit(kCGEventRightMouseUp) |
    CGEventMaskBit(kCGEventOtherMouseDown) |
    CGEventMaskBit(kCGEventOtherMouseUp) |
    CGEventMaskBit(kCGEventLeftMouseDragged) |
    CGEventMaskBit(kCGEventRightMouseDragged) |
    CGEventMaskBit(kCGEventOtherMouseDragged);
    //CGEventMaskBit(kCGEventKeyUp) |
    //CGEventMaskBit(kCGEventKeyDown);
    CFMachPortRef eventTap = CGEventTapCreate(kCGSessionEventTap, kCGHeadInsertEventTap, 0, eventMask, CGEventCallback, NULL);

    if (eventTap != nil) {
        CGEventTapEnable(eventTap, true);
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0);
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, kCFRunLoopCommonModes);
    }

    return eventTap;
}

int eventTapTries = 0;

- (void)createEventTapTimer:(NSTimer *)timer {
    CFMachPortRef newEventTap = nil;
    newEventTap = [me createEventTap];
    if (newEventTap == nil) {
        if (logLevel >= LOG_LEVEL_DEBUG) NSLog(@"Could not create CGEventTap (try %d)", eventTapTries);
        eventTapTries++;
        if (eventTapTries < 360) {
            [NSTimer scheduledTimerWithTimeInterval:1.0 target:me selector:@selector(createEventTapTimer:) userInfo:nil repeats:NO];
        } else {
            NSLog(@"Could not create CGEventTap after 5 minutes. Perhaps try removing Trickpad from Accessibility and relaunching it.");
        }
    } else {
        NSLog(@"CGEventTap created");
        eventTap = newEventTap;
        recreatingEventTap = FALSE;
    }
}

#pragma mark - Init

- (id)init {
    if (logLevel >= LOG_LEVEL_INFO) NSLog(@"Initializing.");
    if (self = [super init]) {
        me = self;

        systemWideElement = AXUIElementCreateSystemWide();

        MGApplicationScopeCacheSetResolver(resolveApplicationCandidates);

        // Character Recognizer
        initNormPdf();
        initChars();

        multitouchDevices = [[MGMultitouchDeviceLifecycle alloc]
            initWithTrackpadCallback:trackpadCallback
                       mouseCallback:magicMouseCallback
               deviceRemovedCallback:multitouchDeviceWasRemoved];
        [multitouchDevices start];

        eventTap = [me createEventTap];
        if (eventTap == nil) {
            NSLog(@"Could not create CGEventTap. Allow Trickpad in System Settings -> Privacy & Security -> Accessibility.");
            recreatingEventTap = TRUE;
            eventTapTries = 0;
            [NSTimer scheduledTimerWithTimeInterval:1.0 target:me selector:@selector(createEventTapTimer:) userInfo:nil repeats:NO];
        }

        // The legacy gesture overlay updates windows from non-main threads on
        // recent macOS releases. Disable the overlay and keep gesture actions.
        gestureWindow = nil;
        sizeHistoryDict = [[NSMutableDictionary alloc] init];

        keyUtil = [[KeyUtility alloc] init];
    }
    return self;
}

- (void)reload {
    if (logLevel >= LOG_LEVEL_INFO) NSLog(@"Reloading gestures.");
    cancelPendingGestureSequences();
    turnOffMagicMouse();
    turnOffTrackpad();
    [multitouchDevices rebuild];
}

#pragma mark - Character Recognizer

static void initNormPdf() {
    float mn = 10, mx = -1;
    float lo = 0.5, hi = 1;
    for (int i = -100; i <= 100; i++) {
        normPdf[i + 100] = 1 / sqrt(2*PI*0.3*0.3) * exp(-(i/100.0) * (i/100.0) / (2*0.3*0.3));
        if (normPdf[i + 100] < mn)
            mn = normPdf[i + 100];
        if (normPdf[i + 100] > mx)
            mx = normPdf[i + 100];
    }
    for (int i = -100; i <= 100; i++) {
        normPdf[i + 100] = (normPdf[i + 100] - mn) * (hi - lo) / (mx - mn) + lo;
    }

    mn = 10; mx = -1;
    lo = 0.1; hi = 1.5;
    for (int i = -100; i <= 100; i++) {
        normIPdf[i + 100] = 1 / sqrt(2*PI*0.3*0.3) * exp(-(i/100.0) * (i/100.0) / (2*0.3*0.3));
        if (normIPdf[i + 100] < mn)
            mn = normIPdf[i + 100];
        if (normIPdf[i + 100] > mx)
            mx = normIPdf[i + 100];
    }
    for (int i = -100; i <= 100; i++) {
        normIPdf[i + 100] = (normIPdf[i + 100] - mn) * (hi - lo) / (mx - mn) + lo;
    }
}

static float getScore(const float *pdf, float input, float deg, float span) {
    for (int i = -1; i <= 1; i++) {
        if (input + 2*PI*i >= deg-span && input + 2*PI*i <= deg + span)
            return pdf[(int)(100 + ((input + 2*PI*i - deg) / span) * 100)];
    }
    return 0;
}

static void setDegreeSpan(DegreeSpan *ds, float deg, float span) {
    ds->deg = deg * PI / 180.0f;
    ds->span = span * PI / 180.0f;
}

static void initChars() {
    int c2 = 0;
    nChars = 0;

    chars[nChars].ch = "A";
    setDegreeSpan(&chars[nChars].ds[c2++], 65, 20);
    setDegreeSpan(&chars[nChars].ds[c2++], -65, 20);
    setDegreeSpan(&chars[nChars].ds[c2++], -1, -1);
    nChars++; c2 = 0;

    chars[nChars].ch = "B";
    setDegreeSpan(&chars[nChars].ds[c2++], 90, 30);
    setDegreeSpan(&chars[nChars].ds[c2++], -45, 50);
    setDegreeSpan(&chars[nChars].ds[c2++], -135, 30);
    setDegreeSpan(&chars[nChars].ds[c2++], -45, 30);
    setDegreeSpan(&chars[nChars].ds[c2++], -135, 30);
    /*setDegreeSpan(&chars[nChars].ds[c2++], 0, 30);
     setDegreeSpan(&chars[nChars].ds[c2++], -90, 30);
     setDegreeSpan(&chars[nChars].ds[c2++], 180, 30);
     setDegreeSpan(&chars[nChars].ds[c2++], 0, 30);
     setDegreeSpan(&chars[nChars].ds[c2++], -90, 30);
     setDegreeSpan(&chars[nChars].ds[c2++], 180, 30);*/
    setDegreeSpan(&chars[nChars].ds[c2++], -1, -1);
    nChars++; c2 = 0;

    chars[nChars].ch = "C";
    setDegreeSpan(&chars[nChars].ds[c2++], -135, 30);
    setDegreeSpan(&chars[nChars].ds[c2++], -45, 30);
    setDegreeSpan(&chars[nChars].ds[c2++], -0, 30);
    setDegreeSpan(&chars[nChars].ds[c2++], -1, -1);
    nChars++; c2 = 0;

    chars[nChars].ch = "D";
    setDegreeSpan(&chars[nChars].ds[c2++], 90, 30);
    setDegreeSpan(&chars[nChars].ds[c2++], -45, 20);
    setDegreeSpan(&chars[nChars].ds[c2++], -135, 20);
    setDegreeSpan(&chars[nChars].ds[c2++], -1, -1);
    nChars++; c2 = 0;

    chars[nChars].ch = "E";
    setDegreeSpan(&chars[nChars].ds[c2++], -135, 30);
    setDegreeSpan(&chars[nChars].ds[c2++], -45, 30);
    setDegreeSpan(&chars[nChars].ds[c2++], -135, 30);
    setDegreeSpan(&chars[nChars].ds[c2++], -45, 30);
    setDegreeSpan(&chars[nChars].ds[c2++], -1, -1);
    nChars++; c2 = 0;

    chars[nChars].ch = "F";
    setDegreeSpan(&chars[nChars].ds[c2++], -180, 20);
    setDegreeSpan(&chars[nChars].ds[c2++], -90, 20);
    setDegreeSpan(&chars[nChars].ds[c2++], -1, -1);
    nChars++; c2 = 0;

    chars[nChars].ch = "G";
    setDegreeSpan(&chars[nChars].ds[c2++], -135, 30);
    setDegreeSpan(&chars[nChars].ds[c2++], -45, 30);
    setDegreeSpan(&chars[nChars].ds[c2++], 45, 30);
    setDegreeSpan(&chars[nChars].ds[c2++], 180, 30);
    setDegreeSpan(&chars[nChars].ds[c2++], -1, -1);
    nChars++; c2 = 0;

    chars[nChars].ch = "H";
    setDegreeSpan(&chars[nChars].ds[c2++], -90, 20);
    setDegreeSpan(&chars[nChars].ds[c2++], 90, 30);
    setDegreeSpan(&chars[nChars].ds[c2++], 0, 60);
    //setDegreeSpan(&chars[nChars].ds[c2++], -45, 30);
    setDegreeSpan(&chars[nChars].ds[c2++], -90, 30);
    setDegreeSpan(&chars[nChars].ds[c2++], -1, -1);
    nChars++; c2 = 0;

    chars[nChars].ch = "Down";
    setDegreeSpan(&chars[nChars].ds[c2++], -90, 20);
    setDegreeSpan(&chars[nChars].ds[c2++], -1, -1);
    nChars++; c2 = 0;

    chars[nChars].ch = "Up";
    setDegreeSpan(&chars[nChars].ds[c2++], 90, 20);
    setDegreeSpan(&chars[nChars].ds[c2++], -1, -1);
    nChars++; c2 = 0;
    /*
     chars[nChars].ch = "Down-Up";
     setDegreeSpan(&chars[nChars].ds[c2++], -90, 20);
     setDegreeSpan(&chars[nChars].ds[c2++], 90, 20);
     setDegreeSpan(&chars[nChars].ds[c2++], -1, -1);
     nChars++; c2 = 0;

     chars[nChars].ch = "Up-Down";
     setDegreeSpan(&chars[nChars].ds[c2++], 90, 20);
     setDegreeSpan(&chars[nChars].ds[c2++], -90, 20);
     setDegreeSpan(&chars[nChars].ds[c2++], -1, -1);
     nChars++; c2 = 0;*/
    chars[nChars].ch = "Y";
    setDegreeSpan(&chars[nChars].ds[c2++], -60, 30);
    setDegreeSpan(&chars[nChars].ds[c2++], 60, 20);
    setDegreeSpan(&chars[nChars].ds[c2++], -120, 30);
    setDegreeSpan(&chars[nChars].ds[c2++], -1, -1);
    nChars++; c2 = 0;

    chars[nChars].ch = "J";
    setDegreeSpan(&chars[nChars].ds[c2++], -90, 20);
    setDegreeSpan(&chars[nChars].ds[c2++], 170, 30);
    setDegreeSpan(&chars[nChars].ds[c2++], -1, -1);
    nChars++; c2 = 0;

    chars[nChars].ch = "K";
    setDegreeSpan(&chars[nChars].ds[c2++], -135, 30);
    setDegreeSpan(&chars[nChars].ds[c2++], 90, 30);
    setDegreeSpan(&chars[nChars].ds[c2++], -45, 30);
    setDegreeSpan(&chars[nChars].ds[c2++], -1, -1);
    nChars++; c2 = 0;

    chars[nChars].ch = "L";
    setDegreeSpan(&chars[nChars].ds[c2++], -90, 20);
    setDegreeSpan(&chars[nChars].ds[c2++], 0, 20);
    setDegreeSpan(&chars[nChars].ds[c2++], -1, -1);
    nChars++; c2 = 0;

    chars[nChars].ch = "M";
    setDegreeSpan(&chars[nChars].ds[c2++], 60, 30);
    setDegreeSpan(&chars[nChars].ds[c2++], -60, 30);
    setDegreeSpan(&chars[nChars].ds[c2++], 60, 30);
    setDegreeSpan(&chars[nChars].ds[c2++], -60, 30);
    setDegreeSpan(&chars[nChars].ds[c2++], -1, -1);
    nChars++; c2 = 0;

    chars[nChars].ch = "N";
    setDegreeSpan(&chars[nChars].ds[c2++], 90, 20);
    setDegreeSpan(&chars[nChars].ds[c2++], -60, 30);
    setDegreeSpan(&chars[nChars].ds[c2++], 90, 20);
    setDegreeSpan(&chars[nChars].ds[c2++], -1, -1);
    nChars++; c2 = 0;

    chars[nChars].ch = "O";
    setDegreeSpan(&chars[nChars].ds[c2++], -135, 30);
    setDegreeSpan(&chars[nChars].ds[c2++], -60, 30);
    setDegreeSpan(&chars[nChars].ds[c2++], 60, 30);
    setDegreeSpan(&chars[nChars].ds[c2++], 135, 30);
    setDegreeSpan(&chars[nChars].ds[c2++], -1, -1);
    nChars++; c2 = 0;

    chars[nChars].ch = "P";
    setDegreeSpan(&chars[nChars].ds[c2++], 90, 30);
    setDegreeSpan(&chars[nChars].ds[c2++], -45, 20);
    setDegreeSpan(&chars[nChars].ds[c2++], -135, 20);
    setDegreeSpan(&chars[nChars].ds[c2++], -1, -1);
    nChars++; c2 = 0;

    chars[nChars].ch = "Q";
    setDegreeSpan(&chars[nChars].ds[c2++], -135, 30);
    setDegreeSpan(&chars[nChars].ds[c2++], -60, 30);
    setDegreeSpan(&chars[nChars].ds[c2++], 60, 30);
    setDegreeSpan(&chars[nChars].ds[c2++], 110, 30);
    setDegreeSpan(&chars[nChars].ds[c2++], -60, 20);
    setDegreeSpan(&chars[nChars].ds[c2++], -1, -1);
    nChars++; c2 = 0;

    chars[nChars].ch = "R";
    setDegreeSpan(&chars[nChars].ds[c2++], 90, 20);
    setDegreeSpan(&chars[nChars].ds[c2++], -45, 30);
    setDegreeSpan(&chars[nChars].ds[c2++], -135, 30);
    setDegreeSpan(&chars[nChars].ds[c2++], -45, 30);
    setDegreeSpan(&chars[nChars].ds[c2++], -1, -1);
    nChars++; c2 = 0;

    chars[nChars].ch = "S";
    setDegreeSpan(&chars[nChars].ds[c2++], -135, 30);
    setDegreeSpan(&chars[nChars].ds[c2++], -45, 30);
    setDegreeSpan(&chars[nChars].ds[c2++], -135, 30);
    setDegreeSpan(&chars[nChars].ds[c2++], 180, 50);
    setDegreeSpan(&chars[nChars].ds[c2++], -1, -1);
    nChars++; c2 = 0;

    chars[nChars].ch = "T";
    setDegreeSpan(&chars[nChars].ds[c2++], 0, 20);
    setDegreeSpan(&chars[nChars].ds[c2++], -90, 20);
    setDegreeSpan(&chars[nChars].ds[c2++], -1, -1);
    nChars++; c2 = 0;

    chars[nChars].ch = "U";
    setDegreeSpan(&chars[nChars].ds[c2++], -90, 20);
    setDegreeSpan(&chars[nChars].ds[c2++], 0, 20);
    setDegreeSpan(&chars[nChars].ds[c2++], 90, 20);
    setDegreeSpan(&chars[nChars].ds[c2++], -1, -1);
    nChars++; c2 = 0;

    chars[nChars].ch = "V";
    setDegreeSpan(&chars[nChars].ds[c2++], -60, 30);
    setDegreeSpan(&chars[nChars].ds[c2++], 60, 20);
    setDegreeSpan(&chars[nChars].ds[c2++], -1, -1);
    nChars++; c2 = 0;

    chars[nChars].ch = "W";
    setDegreeSpan(&chars[nChars].ds[c2++], -60, 30);
    setDegreeSpan(&chars[nChars].ds[c2++], 60, 30);
    setDegreeSpan(&chars[nChars].ds[c2++], -60, 30);
    setDegreeSpan(&chars[nChars].ds[c2++], 60, 30);
    setDegreeSpan(&chars[nChars].ds[c2++], -1, -1);
    nChars++; c2 = 0;

    chars[nChars].ch = "X";
    setDegreeSpan(&chars[nChars].ds[c2++], 45, 30);
    setDegreeSpan(&chars[nChars].ds[c2++], 180, 20);
    setDegreeSpan(&chars[nChars].ds[c2++], -45, 30);
    setDegreeSpan(&chars[nChars].ds[c2++], -1, -1);
    nChars++; c2 = 0;



    chars[nChars].ch = "Z";
    setDegreeSpan(&chars[nChars].ds[c2++], 0, 20);
    setDegreeSpan(&chars[nChars].ds[c2++], -135, 30);
    setDegreeSpan(&chars[nChars].ds[c2++], 0, 20);
    setDegreeSpan(&chars[nChars].ds[c2++], -1, -1);
    nChars++; c2 = 0;
    /*
     chars[nChars].ch = "1";
     setDegreeSpan(&chars[nChars].ds[c2++], 45, 30);
     setDegreeSpan(&chars[nChars].ds[c2++], -90, 20);
     setDegreeSpan(&chars[nChars].ds[c2++], -1, -1);
     nChars++; c2 = 0;

     chars[nChars].ch = "2";
     setDegreeSpan(&chars[nChars].ds[c2++], 45, 30);
     setDegreeSpan(&chars[nChars].ds[c2++], -45, 30);
     setDegreeSpan(&chars[nChars].ds[c2++], -135, 30);
     setDegreeSpan(&chars[nChars].ds[c2++], 0, 20);
     setDegreeSpan(&chars[nChars].ds[c2++], -1, -1);
     nChars++; c2 = 0;

     chars[nChars].ch = "3";
     setDegreeSpan(&chars[nChars].ds[c2++], -45, 30);
     setDegreeSpan(&chars[nChars].ds[c2++], -135, 30);
     setDegreeSpan(&chars[nChars].ds[c2++], -45, 30);
     setDegreeSpan(&chars[nChars].ds[c2++], -135, 30);
     setDegreeSpan(&chars[nChars].ds[c2++], -1, -1);
     nChars++; c2 = 0;

     chars[nChars].ch = "4";
     setDegreeSpan(&chars[nChars].ds[c2++], -135, 30);
     setDegreeSpan(&chars[nChars].ds[c2++], 0, 20);
     setDegreeSpan(&chars[nChars].ds[c2++], 135, 30);
     setDegreeSpan(&chars[nChars].ds[c2++], -90, 20);
     setDegreeSpan(&chars[nChars].ds[c2++], -1, -1);
     nChars++; c2 = 0;


     chars[nChars].ch = "5";
     setDegreeSpan(&chars[nChars].ds[c2++], 180, 20);
     setDegreeSpan(&chars[nChars].ds[c2++], -90, 20);
     setDegreeSpan(&chars[nChars].ds[c2++], -45, 30);
     setDegreeSpan(&chars[nChars].ds[c2++], -135, 30);
     setDegreeSpan(&chars[nChars].ds[c2++], 135, 30);
     setDegreeSpan(&chars[nChars].ds[c2++], -1, -1);
     nChars++; c2 = 0;

     chars[nChars].ch = "6";
     setDegreeSpan(&chars[nChars].ds[c2++], -135, 30);
     setDegreeSpan(&chars[nChars].ds[c2++], -45, 30);
     setDegreeSpan(&chars[nChars].ds[c2++], 45, 30);
     setDegreeSpan(&chars[nChars].ds[c2++], 135, 30);
     setDegreeSpan(&chars[nChars].ds[c2++], -1, -1);
     nChars++; c2 = 0;

     chars[nChars].ch = "7";
     setDegreeSpan(&chars[nChars].ds[c2++], 0, 20);
     setDegreeSpan(&chars[nChars].ds[c2++], -135, 30);
     setDegreeSpan(&chars[nChars].ds[c2++], -1, -1);
     nChars++; c2 = 0;

     chars[nChars].ch = "8";
     setDegreeSpan(&chars[nChars].ds[c2++], -135, 30);
     setDegreeSpan(&chars[nChars].ds[c2++], -45, 30);
     setDegreeSpan(&chars[nChars].ds[c2++], -135, 30);
     setDegreeSpan(&chars[nChars].ds[c2++], 135, 30);
     setDegreeSpan(&chars[nChars].ds[c2++], 45, 30);
     setDegreeSpan(&chars[nChars].ds[c2++], 135, 30);
     setDegreeSpan(&chars[nChars].ds[c2++], -1, -1);
     nChars++; c2 = 0;

     chars[nChars].ch = "9";
     setDegreeSpan(&chars[nChars].ds[c2++], 135, 30);
     setDegreeSpan(&chars[nChars].ds[c2++], -135, 30);
     setDegreeSpan(&chars[nChars].ds[c2++], -45, 30);
     setDegreeSpan(&chars[nChars].ds[c2++], 45, 30);
     setDegreeSpan(&chars[nChars].ds[c2++], -90, 20);
     setDegreeSpan(&chars[nChars].ds[c2++], -1, -1);
     nChars++; c2 = 0;

     chars[nChars].ch = "Up";
     setDegreeSpan(&chars[nChars].ds[c2++], 90, 20);
     setDegreeSpan(&chars[nChars].ds[c2++], -1, -1);
     nChars++; c2 = 0;
     */

    chars[nChars].ch = "Left";
    setDegreeSpan(&chars[nChars].ds[c2++], 180, 35);
    setDegreeSpan(&chars[nChars].ds[c2++], -1, -1);
    nChars++; c2 = 0;

    chars[nChars].ch = "Right";
    setDegreeSpan(&chars[nChars].ds[c2++], 0, 35);
    setDegreeSpan(&chars[nChars].ds[c2++], -1, -1);
    nChars++; c2 = 0;

    chars[nChars].ch = "Left-Right";
    setDegreeSpan(&chars[nChars].ds[c2++], 180, 30);
    setDegreeSpan(&chars[nChars].ds[c2++], 0, 30);
    setDegreeSpan(&chars[nChars].ds[c2++], -1, -1);
    nChars++; c2 = 0;

    chars[nChars].ch = "Right-Left";
    setDegreeSpan(&chars[nChars].ds[c2++], 0, 30);
    setDegreeSpan(&chars[nChars].ds[c2++], 180, 30);
    setDegreeSpan(&chars[nChars].ds[c2++], -1, -1);
    nChars++; c2 = 0;

     chars[nChars].ch = "/ Down";
     setDegreeSpan(&chars[nChars].ds[c2++], -120, 25);
     setDegreeSpan(&chars[nChars].ds[c2++], -1, -1);
     nChars++; c2 = 0;

     chars[nChars].ch = "/ Up";
     setDegreeSpan(&chars[nChars].ds[c2++], 60, 25);
     setDegreeSpan(&chars[nChars].ds[c2++], -1, -1);
     nChars++; c2 = 0;


     chars[nChars].ch = "\\ Down";
     setDegreeSpan(&chars[nChars].ds[c2++], -60, 25);
     setDegreeSpan(&chars[nChars].ds[c2++], -1, -1);
     nChars++; c2 = 0;

     chars[nChars].ch = "\\ Up";
     setDegreeSpan(&chars[nChars].ds[c2++], 120, 25);
     setDegreeSpan(&chars[nChars].ds[c2++], -1, -1);
     nChars++; c2 = 0;


    chars[nChars].ch = "Up-Left";
    setDegreeSpan(&chars[nChars].ds[c2++], 90, 20);
    setDegreeSpan(&chars[nChars].ds[c2++], 180, 20);
    setDegreeSpan(&chars[nChars].ds[c2++], -1, -1);
    nChars++; c2 = 0;

    chars[nChars].ch = "Up-Right";
    setDegreeSpan(&chars[nChars].ds[c2++], 90, 20);
    setDegreeSpan(&chars[nChars].ds[c2++], 0, 20);
    setDegreeSpan(&chars[nChars].ds[c2++], -1, -1);
    nChars++; c2 = 0;

    chars[nChars].ch = "Left-Up";
    setDegreeSpan(&chars[nChars].ds[c2++], 180, 20);
    setDegreeSpan(&chars[nChars].ds[c2++], 90, 20);
    setDegreeSpan(&chars[nChars].ds[c2++], -1, -1);
    nChars++; c2 = 0;

    chars[nChars].ch = "Right-Up";
    setDegreeSpan(&chars[nChars].ds[c2++], 0, 20);
    setDegreeSpan(&chars[nChars].ds[c2++], 90, 20);
    setDegreeSpan(&chars[nChars].ds[c2++], -1, -1);
    nChars++; c2 = 0;
    /*
     chars[nChars].ch = "Down-Left";
     setDegreeSpan(&chars[nChars].ds[c2++], -90, 20);
     setDegreeSpan(&chars[nChars].ds[c2++], 180, 20);
     setDegreeSpan(&chars[nChars].ds[c2++], -1, -1);
     nChars++; c2 = 0;
     */
    /*
     chars[nChars].ch = "[RUL]";
     setDegreeSpan(&chars[nChars].ds[c2++], 0, 20);
     setDegreeSpan(&chars[nChars].ds[c2++], 90, 20);
     setDegreeSpan(&chars[nChars].ds[c2++], 180, 20);
     setDegreeSpan(&chars[nChars].ds[c2++], -1, -1);
     nChars++; c2 = 0;

     chars[nChars].ch = "[RUD]";
     setDegreeSpan(&chars[nChars].ds[c2++], 0, 20);
     setDegreeSpan(&chars[nChars].ds[c2++], 90, 20);
     setDegreeSpan(&chars[nChars].ds[c2++], -90, 20);
     setDegreeSpan(&chars[nChars].ds[c2++], -1, -1);
     nChars++; c2 = 0;

     chars[nChars].ch = "[RUR]";
     setDegreeSpan(&chars[nChars].ds[c2++], 0, 20);
     setDegreeSpan(&chars[nChars].ds[c2++], 90, 20);
     setDegreeSpan(&chars[nChars].ds[c2++], 0, 20);
     setDegreeSpan(&chars[nChars].ds[c2++], -1, -1);
     nChars++; c2 = 0;
     */
    /*
     int i, j;
     for (i = nChars-1; i >= 0; i--) {
     chars[nChars].ch = chars[i].ch + 'a' - 'A';
     for (j = 0; chars[i].ds[j].span > 0; j++);

     for (j--; j >= 0; j--)
     setDegreeSpan(&chars[nChars].ds[c2++], chars[i].ds[j].deg > 0?chars[i].ds[j].deg*180/pi-180:chars[i].ds[j].deg*180/pi + 180, chars[i].ds[j].span*180/pi);
     setDegreeSpan(&chars[nChars].ds[c2++], -1, -1);
     nChars++; c2 = 0;
     }

     */
}

static void advanceStep(float deg) {
    float highestScore = -1e5;
    for (int i = 0; i < nChars; i++) {
        if (chars[i].ds[chars[i].step].span > 0) {
            float lo = chars[i].ds[chars[i].step].deg - chars[i].ds[chars[i].step].span;
            float hi = chars[i].ds[chars[i].step].deg + chars[i].ds[chars[i].step].span;

            if (lo < - PI)
                lo += 2*PI;
            if (hi > PI)
                hi -= 2*PI;

            if ((lo < hi && deg >= lo && deg <= hi) ||
                 (lo > hi && (deg >= lo || deg <= hi)))
                chars[i].step++;
        }
        if (chars[i].step > 0) {
            chars[i].score += getScore(normPdf, deg, chars[i].ds[chars[i].step-1].deg, chars[i].ds[chars[i].step-1].span);
            float penalty = getScore(normIPdf, deg,
                                     chars[i].ds[chars[i].step-1].deg > 0 ? chars[i].ds[chars[i].step-1].deg-PI : chars[i].ds[chars[i].step-1].deg+PI,
                                     PI - chars[i].ds[chars[i].step-1].span);
            if (chars[i].ds[chars[i].step].span < 0)
                chars[i].score -= 2 * penalty;
            else
                chars[i].score -= penalty;

        } else {
            chars[i].score -= getScore(normIPdf, deg,
                                       chars[i].ds[0].deg > 0 ? chars[i].ds[0].deg-PI : chars[i].ds[0].deg+PI, PI - chars[i].ds[0].span);
        }
        if (chars[i].score > highestScore)
            highestScore = chars[i].score;

    }
    if (highestScore < -5) {
        cancelRecognition = 1;
    }
}

static const char *finalizeStep(float x1, float y1, float x2, float y2, float top, float bottom, float left, float right) {
    int out = -1;
    if (top == bottom)
        top = bottom + 1e-8;
    if (right == left)
        right = left + 1e-8;
    for (int i = 0; i < nChars; i++) {
        if (strcmp(chars[i].ch, "H") == 0 && out != -1 && strcmp(chars[out].ch, "B") == 0)
            continue;

        if (strcmp(chars[i].ch, "J") == 0 && out != -1 && strcmp(chars[out].ch, "Y") == 0)
            continue;

        if ((strcmp(chars[i].ch, "D") == 0 && (y2-y1)/(top-bottom) > 0.2) ||
           (strcmp(chars[i].ch, "P") == 0 && (y2-y1)/(top-bottom) < 0.2))
            continue;

        if (strcmp(chars[i].ch, "N") == 0 && (y2-y1)/(top-bottom) < 0.3)
            continue;

        if (strcmp(chars[i].ch, "Y") == 0 && (y1-y2)/(top-bottom) < 0.5)
            continue;

        if ((strcmp(chars[i].ch, "O") == 0 && (y2-y1)/(top-bottom) < -0.2) ||
           (strcmp(chars[i].ch, "G") == 0 && (y2-y1)/(top-bottom) > -0.2))
            continue;

        if ((strcmp(chars[i].ch, "T") == 0 ||
           strcmp(chars[i].ch, "F") == 0 ||
           strcmp(chars[i].ch, "Left-Up") == 0 ||
            strcmp(chars[i].ch, "Right-Up") == 0) && (top-bottom)/(right-left) < 0.2)
            continue;

        if ((strcmp(chars[i].ch, "L") == 0 ||
            strcmp(chars[i].ch, "Up-Left") == 0 ||
            strcmp(chars[i].ch, "Up-Right") == 0) && (right-left)/(top-bottom) < 0.2)
            continue;

        /*if ((strcmp(chars[i].ch, "L") == 0 ||
            strcmp(chars[i].ch, "") == 0 ||
            strcmp(chars[i].ch, "Right-Up") == 0 ||
            strcmp(chars[i].ch, "Left-Up") == 0) && (top-bottom)/(right-left) < 0.2)
            continue;
        */
        if (chars[i].ds[chars[i].step].span < 0 && (out == -1 || chars[i].score > chars[out].score))
            out = i;
    }
    /*
     if (chars[out].ch[0] == 'N') {
     CGPostKeyboardEvent((CGCharCode)0, (CGKeyCode)55, true );
     CGPostKeyboardEvent((CGCharCode)0, (CGKeyCode)45, true );
     CGPostKeyboardEvent((CGCharCode)0, (CGKeyCode)45, false );
     CGPostKeyboardEvent((CGCharCode)0, (CGKeyCode)55, false );
     } else if (chars[out].ch[0] == 'S') {
     CGPostKeyboardEvent((CGCharCode)0, (CGKeyCode)55, true );
     CGPostKeyboardEvent((CGCharCode)0, (CGKeyCode)1, true );
     CGPostKeyboardEvent((CGCharCode)0, (CGKeyCode)1, false );
     CGPostKeyboardEvent((CGCharCode)0, (CGKeyCode)55, false );
     } else if (chars[out].ch[0] == 'O') {
     CGPostKeyboardEvent((CGCharCode)0, (CGKeyCode)55, true );
     CGPostKeyboardEvent((CGCharCode)0, (CGKeyCode)31, true );
     CGPostKeyboardEvent((CGCharCode)0, (CGKeyCode)31, false );
     CGPostKeyboardEvent((CGCharCode)0, (CGKeyCode)55, false );
     }*/
    if (out == -1 || chars[out].score < 0)
        return "?";
    return chars[out].ch;
}

static void clearStep() {
    for (int i = 0; i < nChars; i++) {
        chars[i].step = 0;
        chars[i].score = 0;
    }
}

static float hint_firstPos[2], hint_x, hint_y, hint_top, hint_bottom, hint_left, hint_right;
static const float hintWaitTime = 0.3f;
static const char *emptyString = "";

- (void)showHintTimer:(NSTimer *)aTimer {
    [gestureWindow setHintText: finalizeStep(hint_firstPos[0], hint_firstPos[1], hint_x, hint_y, hint_top, hint_bottom, hint_left, hint_right)];
}

static int mouseRecognizer(float x, float y, int step) {
    static NSTimer *timer = nil;

    static float lpos[2];
    static const float dst = 5;

    static float firstPos[2];
    static float top, bottom, left, right;

    static int distCounter = 0;
    int returnValue = 0;
    if (step == 0) {
        @autoreleasepool {
            lpos[0] = x;
            lpos[1] = y;
            firstPos[0] = lpos[0];
            firstPos[1] = lpos[1];
            clearStep();
            top = -10000;
            bottom = 10000;
            left = 10000;
            right = -10000;
            distCounter = 0;

            dispatch_async(dispatch_get_main_queue(), ^{
                [gestureWindow setHintText: emptyString];
                [gestureWindow setUpWindowForMagicMouse];
                [gestureWindow addRelativePointX:x-firstPos[0] Y:y-firstPos[1]];
            });
        };

    } else if (step == 1 && !cancelRecognition) {
        if (y > top)
            top = y;
        if (y < bottom)
            bottom = y;
        if (x > right)
            right = x;
        if (x < left)
            left = x;
        if (lenSqr(lpos[0], lpos[1], x, y) > dst) {
            @autoreleasepool {
                float deg = atan2(y - lpos[1], x - lpos[0]);
                advanceStep(deg);
                lpos[0] = x;
                lpos[1] = y;

                [gestureWindow addRelativePointX:x-firstPos[0] Y:y-firstPos[1]];

                if (distCounter >= 0) {
                    distCounter++;
                    if (distCounter >= 3) {
                        dispatch_async(dispatch_get_main_queue(), ^{
                            [gestureWindow display];
                            [gestureWindow setLevel:NSScreenSaverWindowLevel];
                            [gestureWindow makeKeyAndOrderFront:nil];
                        });
                        distCounter = -1;
                        returnValue = 1;
                    }
                }
                if (timer != nil) {
                    if ([timer isValid])
                        [timer invalidate];
                    [timer release];
                    timer = nil;
                }
                timer = [[NSTimer scheduledTimerWithTimeInterval:(hintWaitTime)
                                                          target:me
                                                        selector:@selector(showHintTimer:)
                                                        userInfo:nil
                                                         repeats:NO] retain];
                hint_firstPos[0] = firstPos[0];
                hint_firstPos[1] = firstPos[1];
                hint_x = x;
                hint_y = y;
                hint_top = top;
                hint_bottom = bottom;
                hint_left = left;
                hint_right = right;
                dispatch_async(dispatch_get_main_queue(), ^{
                    [gestureWindow setHintText: emptyString];
                });
            };
        }
    } else if (step == 2 || cancelRecognition) {
        cancelRecognition = 0;
        @autoreleasepool {
            dispatch_async(dispatch_get_main_queue(), ^{
                [gestureWindow clear];
                [gestureWindow orderOut:nil];
            });
        };
        if (!cancelRecognition) {
            NSString *commandString = [[NSString alloc] initWithUTF8String:finalizeStep(firstPos[0], firstPos[1], x, y, top, bottom, left, right)];
            dispatchCommand(commandString, CHARRECOGNITION);
            [commandString release];
        }

        if (timer != nil) {
            if ([timer isValid])
                [timer invalidate];
            [timer release];
            timer = nil;
        }
    }
    return returnValue;
}

static void trackpadRecognizerOne(const Finger *data, int nFingers, double timestamp) {
    static float lpos[2];
    static int step = 0;
    static const float dst = 0.0002;

    static float firstPos[2];
    static float top, bottom, left, right;
    static double sttime = -1;
    static float fing[2][2];
    static int fixId;

    static double hintTime;
    static CGFloat mx, my;

    if (step == 0 && nFingers == 1) {
        step = 1;
        fixId = data[0].identifier;
        sttime = -1;
    } else if (step == 1 && nFingers == 2) {
        if (nFingers == 2) {
            if (fabs(data[0].px-data[1].px) > charRegIndexRingDistance && fabs(data[0].py-data[1].py)< 0.5 && fabs(data[0].px-data[1].px) < 0.65 &&
               !CGEventSourceButtonState(kCGEventSourceStateHIDSystemState, kCGMouseButtonLeft)) {
                if (sttime < 0)
                    sttime = timestamp;
                if ((data[0].identifier == fixId || data[0].size > stvt / 10) &&
                   (data[1].identifier == fixId || data[1].size > stvt / 10)) {
                    step = 2;

                    fing[0][0] = data[0].px;
                    fing[0][1] = data[0].py;
                    fing[1][0] = data[1].px;
                    fing[1][1] = data[1].py;
                }
            } else
                step = 0;
        } else if (nFingers == 1) {
            sttime = -1;
            fixId = data[0].identifier;
        } else
            step = 0;

    } else if (step == 2) {
        if (nFingers == 1) {
            if (timestamp - sttime > clickSpeed || (isTrackpadRecognizing > 0 && isTrackpadRecognizing != 1)) {
                step = 0;
            } else {
                @autoreleasepool {
                    getMousePosition(&mx, &my);

                    step = 3;
                    isTrackpadRecognizing = 1;
                    lpos[0] = data[0].px;
                    lpos[1] = data[0].py;
                    firstPos[0] = lpos[0];
                    firstPos[1] = lpos[1];

                    clearStep();
                    top = 0;
                    bottom = 1;
                    left = 1;
                    right = 0;

                    dispatch_async(dispatch_get_main_queue(), ^{
                        [gestureWindow setHintText: emptyString];
                        [gestureWindow setUpWindowForTrackpad];
                        [gestureWindow addPointX:data[0].px Y:data[0].py];
                        [gestureWindow display];
                        [gestureWindow setLevel:NSScreenSaverWindowLevel];
                        [gestureWindow makeKeyAndOrderFront:nil];
                    });

                    step = 3;
                }
            }
        } else if (nFingers == 2) {
            if (lenSqr(data[0].px, data[0].py, fing[0][0], fing[0][1]) > 0.001 || lenSqr(data[1].px, data[1].py, fing[1][0], fing[1][1]) > 0.001)
                step = 0;
        } else {
            step = 0;
        }

    } else if (step == 3) {
        if (nFingers != 1 || cancelRecognition) {
            step = 0;
            @autoreleasepool {
                mouseClick(8, mx, my);
                if (!cancelRecognition && nFingers == 0) {
                    NSString *commandString = [[NSString alloc] initWithUTF8String:finalizeStep(firstPos[0], firstPos[1], lpos[0], lpos[1], top, bottom, left, right)];
                    dispatchCommand(commandString, CHARRECOGNITION);
                    [commandString release];
                }
                cancelRecognition = 0;
                dispatch_async(dispatch_get_main_queue(), ^{
                    [gestureWindow clear];
                    [gestureWindow orderOut:nil];
                });
            }
            isTrackpadRecognizing = 0;
        } else {
            if (hintTime > 0 && timestamp - hintTime >= hintWaitTime) {
                [gestureWindow setHintText: finalizeStep(firstPos[0], firstPos[1], lpos[0], lpos[1], top, bottom, left, right)];
                hintTime = -1;
            }

            if (data[0].py > top)
                top = data[0].py;
            if (data[0].py < bottom)
                bottom = data[0].py;
            if (data[0].px > right)
                right = data[0].px;
            if (data[0].px < left)
                left = data[0].px;
            if (lenSqr(lpos[0], lpos[1], data[0].px, data[0].py) > dst) {
                float deg = atan2(data[0].py - lpos[1], data[0].px - lpos[0]);
                advanceStep(deg);
                @autoreleasepool {
                    lpos[0] = data[0].px;
                    lpos[1] = data[0].py;
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [gestureWindow addPointX:data[0].px Y:data[0].py];
                    });
                }
                hintTime = timestamp;
                [gestureWindow setHintText: emptyString];
            }

            mouseClick(8, 10000, 10000);
        }
    }
}

static void trackpadRecognizerTwo(const Finger *data, int nFingers, double timestamp) {
    static float lpos[2];
    static int step = 0;
    static const float dst = 0.0002;

    static float firstPos[2];
    static float top, bottom, left, right;
    static float fing[2][2];
    static double sttime;
    static NSMutableString *commandString = nil;

    static double hintTime;
    static int distCounter = 0;
    float x, y;

    if (step == 0 && nFingers < 2) {
        step = 1;
    } else if (step == 1 && nFingers == 2) {
        int left = data[0].px > data[1].px;
        if (fabs(data[0].px-data[1].px) > charRegIndexRingDistance &&
           fabs(data[0].px-data[1].px) < 0.65 &&
           fabs(data[0].py-data[1].py)< 0.6  &&
           data[!left].py-data[left].py + data[!left].py > -0.12 &&
           data[0].py > 0.14 && data[1].py > 0.14 &&
           !CGEventSourceButtonState(kCGEventSourceStateHIDSystemState, kCGMouseButtonLeft) &&
           !(data[0].majorAxis >= 11 && data[1].majorAxis >= 11 && data[!left].angle > 1.5708 && data[left].angle < 1.5708 && data[!left].angle-data[left].angle > 0.5)) {
            @autoreleasepool {
                x = (data[0].px + data[1].px) / 2;
                y = (data[0].py + data[1].py) / 2;

                step = 3;
                isTrackpadRecognizing = 2;
                lpos[0] = x;
                lpos[1] = y;
                firstPos[0] = lpos[0];
                firstPos[1] = lpos[1];
                fing[0][0] = data[0].px;
                fing[0][1] = data[0].py;
                fing[1][0] = data[1].px;
                fing[1][1] = data[1].py;
                clearStep();
                top = 0;
                bottom = 1;
                left = 1;
                right = 0;

                dispatch_async(dispatch_get_main_queue(), ^{
                    [gestureWindow setHintText: emptyString];

                    distCounter = 0;

                    [gestureWindow setUpWindowForTrackpad];
                    [gestureWindow addPointX:x Y:y];
                });

                hintTime = -1;
            };
        } else
            step = 0;
    } else if (step == 3) {

        if (nFingers != 2 || cancelRecognition) {
            step = 0;
            @autoreleasepool {
                if (!cancelRecognition && distCounter == -1) {
                    if (!commandString) {
                        commandString = [[NSMutableString alloc] init];
                    }
                    [commandString setString:[NSString stringWithUTF8String:finalizeStep(firstPos[0], firstPos[1], lpos[0], lpos[1], top, bottom, left, right)]];
                    if (nFingers != 3) {
                        dispatchCommand(commandString, CHARRECOGNITION);
                    }
                }
                cancelRecognition = 0;
                dispatch_async(dispatch_get_main_queue(), ^{
                    [gestureWindow clear];
                    [gestureWindow orderOut:nil];
                });
            };
            isTrackpadRecognizing = 0;

        } else {
            if (hintTime > 0 && timestamp - hintTime >= hintWaitTime) {
                @autoreleasepool {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [gestureWindow setHintText: finalizeStep(firstPos[0], firstPos[1], lpos[0], lpos[1], top, bottom, left, right)];
                    });
                };
                hintTime = -1;
            }

            x = (data[0].px + data[1].px) / 2;
            y = (data[0].py + data[1].py) / 2;

            if (y > top)
                top = y;
            if (y < bottom)
                bottom = y;
            if (x > right)
                right = x;
            if (x < left)
                left = x;
            if (lenSqr(lpos[0], lpos[1], x, y) > dst) {
                float deg = atan2(y - lpos[1], x - lpos[0]);
                advanceStep(deg);
                @autoreleasepool {
                    if (distCounter >= 0) {
                        distCounter++;
                        if (distCounter >= 5) {
                            if (lenSqr(fing[0][0], fing[0][1], data[0].px, data[0].py) > 0.003 && lenSqr(fing[1][0], fing[1][1], data[1].px, data[1].py) > 0.003
                               && fabs(lenSqr(fing[0][0], fing[0][1], fing[1][0], fing[1][1])-lenSqr(data[0].px, data[0].py, data[1].px, data[1].py)) < 0.13) {
                                dispatch_async(dispatch_get_main_queue(), ^{
                                    [gestureWindow display];
                                    [gestureWindow setLevel:NSScreenSaverWindowLevel];
                                    [gestureWindow makeKeyAndOrderFront:nil];
                                });
                                distCounter = -1;
                            } else {
                                cancelRecognition = 1;
                            }
                        }
                    }

                    lpos[0] = x;
                    lpos[1] = y;
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [gestureWindow addPointX:x Y:y];
                    });

                    hintTime = timestamp;
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [gestureWindow setHintText: emptyString];
                    });
                };
            }
        }
    } else if (step == 4) {
        if (timestamp - sttime > clickSpeed || nFingers < 2 || nFingers > 3)
            step = 0;
        else if (nFingers == 2) {
            step = 5;
            sttime = timestamp;
        }
    } else if (step == 5) {
        if (timestamp - sttime > clickSpeed || nFingers < 2 || nFingers > 3)
            step = 0;
        if (nFingers == 3) {
            step = 0;
        }
    }
}

#pragma mark -

- (void) dealloc {
    [multitouchDevices release];
    [super dealloc];
}

@end
