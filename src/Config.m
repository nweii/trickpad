//
//  Config.m
//  Trickpad
//
//  Copyright 2026 Nathan Cheng. All rights reserved.
//

#import "Config.h"
#import <Carbon/Carbon.h>
#import <ApplicationServices/ApplicationServices.h>
#import <IOKit/hidsystem/IOLLEvent.h>
#import <math.h>
#import "SystemGestureClaims.h"
#import "tomlc17.h"

@interface ConfigResult ()
@property(nonatomic, readwrite, retain) NSDictionary *settings;
@property(nonatomic, readwrite, retain) NSArray *diagnostics;
@property(nonatomic, readwrite, retain) NSDictionary *sourceComments;
@end

@implementation ConfigResult

@synthesize settings = _settings;
@synthesize diagnostics = _diagnostics;
@synthesize sourceComments = _sourceComments;

- (NSString *)commentForDevice:(NSString *)device
                   application:(NSString *)application
                       gesture:(NSString *)gesture {
    return [[[_sourceComments objectForKey:device] objectForKey:application]
        objectForKey:gesture];
}

- (void)dealloc {
    [_settings release];
    [_diagnostics release];
    [_sourceComments release];
    [super dealloc];
}

@end

// The tables accept common alternative spellings because people and coding
// agents may use different names for the same value.

@interface Config ()
+ (NSDictionary *)settingsFromLegacyText:(NSString *)text
                              diagnostics:(NSMutableArray *)diagnostics;
@end

@implementation Config

#pragma mark - Gesture vocabulary

// Configuration slugs map to the engine's gesture names. One slug may cover
// several engine names that differ only by the distance between two fingers.
+ (NSDictionary *)mouseGestureSlugs {
    static NSDictionary *m = nil;
    if (m == nil) {
        m = [@{
            @"hold-left-tap-right": @[@"Index-Fix Middle-Near-Tap", @"Index-Fix Middle-Far-Tap"],
            @"hold-right-tap-left": @[@"Middle-Fix Index-Near-Tap", @"Middle-Fix Index-Far-Tap"],
            @"hold-two-tap-between": @[@"Two-Fix Between-Tap"],
            @"hold-two-tap-left": @[@"Two-Fix Left-Tap"],
            @"hold-two-tap-right": @[@"Two-Fix Right-Tap"],
            @"one-finger-tap": @[@"One-Finger Tap"],
            @"two-finger-tap": @[@"Two-Finger Tap"],
            @"three-finger-tap": @[@"Three-Finger Tap"],
            @"one-finger-double-tap": @[@"One-Finger Double-Tap"],
            @"two-finger-double-tap": @[@"Two-Finger Double-Tap"],
            @"three-finger-double-tap": @[@"Three-Finger Double-Tap"],
            @"two-finger-click": @[@"Two-Finger Click"],
            @"three-finger-click": @[@"Three-Finger Click"],
            @"front-right-tap": @[@"Right-Front Tap"],
            @"one-finger-swipe": @[@"One-Swipe-Any"],
            @"two-finger-swipe": @[@"Two-Swipe-Any"],
            @"three-finger-swipe": @[@"Three-Swipe-Any"],
            @"one-finger-swipe-left": @[@"One-Swipe-Left"],
            @"one-finger-swipe-right": @[@"One-Swipe-Right"],
            @"two-finger-swipe-left": @[@"Two-Swipe-Left"],
            @"two-finger-swipe-right": @[@"Two-Swipe-Right"],
            @"three-finger-swipe-left": @[@"Three-Swipe-Left"],
            @"three-finger-swipe-right": @[@"Three-Swipe-Right"],
            @"three-finger-swipe-up": @[@"Three-Swipe-Up"],
            @"three-finger-swipe-down": @[@"Three-Swipe-Down"],
        } retain];
    }
    return m;
}

+ (NSDictionary *)trackpadGestureSlugs {
    static NSDictionary *m = nil;
    if (m == nil) {
        m = [@{
            @"hold-right-tap-left": @[@"One-Fix Left-Tap"],
            @"hold-left-tap-right": @[@"One-Fix Right-Tap"],
            @"hold-slide": @[@"One-Fix One-Slide"],
            @"two-finger-tap": @[@"Two-Finger Tap"],
            @"three-finger-tap": @[@"Three-Finger Tap"],
            @"four-finger-tap": @[@"Four-Finger Tap"],
            @"five-finger-tap": @[@"Five-Finger Tap"],
            @"two-finger-double-tap": @[@"Two-Finger Double-Tap"],
            @"three-finger-double-tap": @[@"Three-Finger Double-Tap"],
            @"four-finger-double-tap": @[@"Four-Finger Double-Tap"],
            @"five-finger-double-tap": @[@"Five-Finger Double-Tap"],
            @"three-finger-click": @[@"Three-Finger Click"],
            @"four-finger-click": @[@"Four-Finger Click"],
            @"edge-click": @[@"Any-Edge Click"],
            @"corner-click": @[@"Any-Corner Click"],
            @"left-edge-click": @[@"Left-Edge Click"],
            @"right-edge-click": @[@"Right-Edge Click"],
            @"top-edge-click": @[@"Top-Edge Click"],
            @"bottom-edge-click": @[@"Bottom-Edge Click"],
            @"left-edge-top-half-click": @[@"Left-Edge Top-Half Click"],
            @"left-edge-bottom-half-click": @[@"Left-Edge Bottom-Half Click"],
            @"right-edge-top-half-click": @[@"Right-Edge Top-Half Click"],
            @"right-edge-bottom-half-click": @[@"Right-Edge Bottom-Half Click"],
            @"top-edge-left-half-click": @[@"Top-Edge Left-Half Click"],
            @"top-edge-right-half-click": @[@"Top-Edge Right-Half Click"],
            @"bottom-edge-left-half-click": @[@"Bottom-Edge Left-Half Click"],
            @"bottom-edge-right-half-click": @[@"Bottom-Edge Right-Half Click"],
            @"left-edge-top-third-click": @[@"Left-Edge Top-Third Click"],
            @"left-edge-middle-third-click": @[@"Left-Edge Middle-Third Click"],
            @"left-edge-bottom-third-click": @[@"Left-Edge Bottom-Third Click"],
            @"right-edge-top-third-click": @[@"Right-Edge Top-Third Click"],
            @"right-edge-middle-third-click": @[@"Right-Edge Middle-Third Click"],
            @"right-edge-bottom-third-click": @[@"Right-Edge Bottom-Third Click"],
            @"top-edge-left-third-click": @[@"Top-Edge Left-Third Click"],
            @"top-edge-middle-third-click": @[@"Top-Edge Middle-Third Click"],
            @"top-edge-right-third-click": @[@"Top-Edge Right-Third Click"],
            @"bottom-edge-left-third-click": @[@"Bottom-Edge Left-Third Click"],
            @"bottom-edge-middle-third-click": @[@"Bottom-Edge Middle-Third Click"],
            @"bottom-edge-right-third-click": @[@"Bottom-Edge Right-Third Click"],
            @"top-left-corner-click": @[@"Top-Left-Corner Click"],
            @"top-right-corner-click": @[@"Top-Right-Corner Click"],
            @"bottom-left-corner-click": @[@"Bottom-Left-Corner Click"],
            @"bottom-right-corner-click": @[@"Bottom-Right-Corner Click"],
            @"three-finger-swipe": @[@"Three-Swipe-Any"],
            @"four-finger-swipe": @[@"Four-Swipe-Any"],
            @"three-finger-swipe-left": @[@"Three-Swipe-Left"],
            @"three-finger-swipe-right": @[@"Three-Swipe-Right"],
            @"three-finger-swipe-up": @[@"Three-Swipe-Up"],
            @"three-finger-swipe-down": @[@"Three-Swipe-Down"],
            @"four-finger-swipe-left": @[@"Four-Swipe-Left"],
            @"four-finger-swipe-right": @[@"Four-Swipe-Right"],
            @"four-finger-swipe-up": @[@"Four-Swipe-Up"],
            @"four-finger-swipe-down": @[@"Four-Swipe-Down"],
            @"index-to-pinky": @[@"Index-To-Pinky"],
            @"pinky-to-index": @[@"Pinky-To-Index"],
        } retain];
    }
    return m;
}

// Area-click names read naturally in several orders, so a reordering of a
// documented name is accepted and canonicalized here, at parse time, before
// anything downstream sees it. The edge-region family is ambiguous as a bag of
// words (left-edge-top-half-click and top-edge-left-half-click share a word
// multiset), so the direction word attached to "edge" names the edge and the
// remaining direction and size words form the part. An ordering that leaves no
// direction attached to "edge" stays ambiguous and returns nil, as does any
// word set that is not an area-click name in `slugs`.
+ (NSString *)canonicalAreaClickSlug:(NSString *)slug inSlugs:(NSDictionary *)slugs {
    NSArray *tokens = [slug componentsSeparatedByString:@"-"];
    NSSet *directions = [NSSet setWithArray:@[@"left", @"right", @"top", @"bottom", @"middle"]];
    NSSet *sizes = [NSSet setWithArray:@[@"half", @"third"]];

    NSString *shape = nil;      // "edge" or "corner"
    NSString *size = nil;
    NSMutableArray *found = [NSMutableArray array];
    NSUInteger clicks = 0;
    NSUInteger edgeIndex = NSNotFound;
    for (NSUInteger i = 0; i < [tokens count]; i++) {
        NSString *token = [tokens objectAtIndex:i];
        if ([token isEqualToString:@"click"]) {
            clicks++;
        } else if ([token isEqualToString:@"edge"] || [token isEqualToString:@"corner"]) {
            if (shape != nil)
                return nil;
            shape = token;
            edgeIndex = i;
        } else if ([sizes containsObject:token]) {
            if (size != nil)
                return nil;
            size = token;
        } else if ([directions containsObject:token]) {
            if ([found containsObject:token])
                return nil;
            [found addObject:token];
        } else {
            return nil;
        }
    }
    if (clicks != 1 || shape == nil)
        return nil;

    NSString *candidate = nil;
    if ([shape isEqualToString:@"corner"]) {
        if (size == nil && [found count] == 0) {
            candidate = @"corner-click";
        } else if (size == nil && [found count] == 2) {
            // Corners have one vertical and one horizontal word; canonical
            // order puts the vertical first, so the bag alone decides.
            NSString *vertical = [found containsObject:@"top"] ? @"top" :
                ([found containsObject:@"bottom"] ? @"bottom" : nil);
            NSString *horizontal = [found containsObject:@"left"] ? @"left" :
                ([found containsObject:@"right"] ? @"right" : nil);
            if (vertical == nil || horizontal == nil)
                return nil;
            candidate = [NSString stringWithFormat:@"%@-%@-corner-click", vertical, horizontal];
        } else {
            return nil;
        }
    } else if (size == nil && [found count] <= 1) {
        candidate = [found count] == 0 ? @"edge-click" :
            [NSString stringWithFormat:@"%@-edge-click", [found firstObject]];
    } else if (size != nil && [found count] == 2) {
        // Adjacency decides the edge: the direction word beside "edge", the
        // preceding one first the way the canonical names read. "middle" is
        // never an edge, so it cannot claim the slot.
        NSString *edgeDirection = nil;
        NSString *before = edgeIndex > 0 ? [tokens objectAtIndex:edgeIndex - 1] : nil;
        NSString *after = edgeIndex + 1 < [tokens count] ? [tokens objectAtIndex:edgeIndex + 1] : nil;
        if ([found containsObject:before] && ![before isEqualToString:@"middle"])
            edgeDirection = before;
        else if ([found containsObject:after] && ![after isEqualToString:@"middle"])
            edgeDirection = after;
        if (edgeDirection == nil)
            return nil;
        NSString *partDirection = [[found firstObject] isEqualToString:edgeDirection]
            ? [found lastObject] : [found firstObject];
        candidate = [NSString stringWithFormat:@"%@-edge-%@-%@-click",
                     edgeDirection, partDirection, size];
    } else {
        return nil;
    }
    return [slugs objectForKey:candidate] != nil ? candidate : nil;
}

// The whole gesture vocabulary accepts its words in any order, canonicalized
// here at parse time when the exact lookup misses, so everything downstream
// sees only canonical names. Three families share a word multiset and cannot
// be named by a bag of words alone: the edge-region family uses the adjacency
// rule in canonicalAreaClickSlug:, hold-tap names read each direction beside
// its "hold" or "tap", and brush names are ordered by "to", so only their
// canonical spellings load. Every other documented name has a unique word
// multiset, which ConfigCheck asserts, so a bag matching exactly one slug
// resolves to it; anything still ambiguous or matching nothing returns nil.
+ (NSString *)canonicalSlug:(NSString *)slug inSlugs:(NSDictionary *)slugs {
    NSString *area = [Config canonicalAreaClickSlug:slug inSlugs:slugs];
    if (area != nil)
        return area;

    NSArray *tokens = [slug componentsSeparatedByString:@"-"];
    NSArray *bag = [tokens sortedArrayUsingSelector:@selector(compare:)];

    if ([bag isEqualToArray:@[@"hold", @"left", @"right", @"tap"]]) {
        // Each direction pairs with the anchor word beside it. A direction
        // beside both anchors takes whichever the other direction leaves,
        // and a direction beside neither leaves the ordering ambiguous.
        NSString *held = nil;
        NSString *tapped = nil;
        for (NSString *direction in @[@"left", @"right"]) {
            NSUInteger i = [tokens indexOfObject:direction];
            BOOL nearHold = (i > 0 && [[tokens objectAtIndex:i - 1] isEqualToString:@"hold"]) ||
                (i + 1 < [tokens count] && [[tokens objectAtIndex:i + 1] isEqualToString:@"hold"]);
            BOOL nearTap = (i > 0 && [[tokens objectAtIndex:i - 1] isEqualToString:@"tap"]) ||
                (i + 1 < [tokens count] && [[tokens objectAtIndex:i + 1] isEqualToString:@"tap"]);
            if (nearHold && !nearTap)
                held = direction;
            else if (nearTap && !nearHold)
                tapped = direction;
            else if (!nearHold && !nearTap)
                return nil;
        }
        if (held == nil && tapped != nil)
            held = [tapped isEqualToString:@"left"] ? @"right" : @"left";
        else if (tapped == nil && held != nil)
            tapped = [held isEqualToString:@"left"] ? @"right" : @"left";
        if (held == nil || tapped == nil)
            return nil;
        NSString *candidate = [NSString stringWithFormat:@"hold-%@-tap-%@", held, tapped];
        return [slugs objectForKey:candidate] != nil ? candidate : nil;
    }

    NSString *match = nil;
    for (NSString *candidate in slugs) {
        NSArray *candidateBag = [[candidate componentsSeparatedByString:@"-"]
                                 sortedArrayUsingSelector:@selector(compare:)];
        if ([bag isEqualToArray:candidateBag]) {
            if (match != nil)
                return nil;
            match = candidate;
        }
    }
    return match;
}

static NSUInteger fingerCountInGestureSlug(NSString *slug) {
    NSDictionary *counts = @{
        @"one": @1, @"two": @2, @"three": @3, @"four": @4, @"five": @5,
    };
    NSArray *words = [slug componentsSeparatedByString:@"-"];
    for (NSUInteger i = 0; i + 1 < [words count]; i++) {
        NSNumber *count = [counts objectForKey:[words objectAtIndex:i]];
        if (count != nil && [[words objectAtIndex:i + 1] isEqualToString:@"finger"])
            return [count unsignedIntegerValue];
    }
    return 0;
}

static NSUInteger maximumFingerCountInSlugs(NSDictionary *slugs) {
    NSUInteger maximum = 0;
    for (NSString *slug in slugs)
        maximum = MAX(maximum, fingerCountInGestureSlug(slug));
    return maximum;
}

static NSString *gestureNameProblem(NSString *key, NSString *device,
                                    NSDictionary *slugs) {
    BOOL mouse = [device isEqualToString:@"mouse"];
    NSDictionary *otherSlugs = mouse
        ? [Config trackpadGestureSlugs] : [Config mouseGestureSlugs];
    NSString *otherName = [otherSlugs objectForKey:key] == nil
        ? [Config canonicalSlug:key inSlugs:otherSlugs] : key;
    NSMutableArray *reasons = [NSMutableArray array];
    if (otherName != nil) {
        NSString *otherDevice = mouse ? @"Trackpad" : @"Magic Mouse";
        [reasons addObject:[NSString stringWithFormat:@"\"%@\" is a %@ gesture.",
                            otherName, otherDevice]];
    }

    NSUInteger count = fingerCountInGestureSlug(key);
    NSUInteger maximum = maximumFingerCountInSlugs(slugs);
    if (count > maximum && maximum > 0) {
        NSString *deviceName = mouse ? @"Magic Mouse" : @"Trackpad";
        NSDictionary *countWords = @{
            @1: @"one", @2: @"two", @3: @"three", @4: @"four", @5: @"five",
        };
        NSString *maximumWord = [countWords objectForKey:@(maximum)] ?: [@(maximum) stringValue];
        [reasons addObject:[NSString stringWithFormat:
            @"%@ gestures use up to %@ fingers.", deviceName, maximumWord]];
    }

    if ([reasons count] == 0)
        return [NSString stringWithFormat:@"no %@ gesture named \"%@\"", device, key];
    return [reasons componentsJoinedByString:@" "];
}

+ (NSString *)canonicalGestureName:(NSString *)raw inSlugs:(NSDictionary *)slugs {
    for (NSString *slug in slugs) {
        NSArray *engineNames = [slugs objectForKey:slug];
        if ([engineNames containsObject:raw])
            return [engineNames firstObject];
    }
    return raw;
}

// A bare swipe slug binds every direction of its family through one engine
// name. Dispatch tries the recognized direction first, then this family name,
// so a directional binding overrides the bare one for its own direction.
+ (NSString *)directionlessGestureName:(NSString *)engineName {
    static NSDictionary *families = nil;
    if (families == nil) {
        families = [@{
            @"One-Swipe-Left": @"One-Swipe-Any",
            @"One-Swipe-Right": @"One-Swipe-Any",
            @"Two-Swipe-Left": @"Two-Swipe-Any",
            @"Two-Swipe-Right": @"Two-Swipe-Any",
            @"Three-Swipe-Left": @"Three-Swipe-Any",
            @"Three-Swipe-Right": @"Three-Swipe-Any",
            @"Three-Swipe-Up": @"Three-Swipe-Any",
            @"Three-Swipe-Down": @"Three-Swipe-Any",
            @"Four-Swipe-Left": @"Four-Swipe-Any",
            @"Four-Swipe-Right": @"Four-Swipe-Any",
            @"Four-Swipe-Up": @"Four-Swipe-Any",
            @"Four-Swipe-Down": @"Four-Swipe-Any",
        } retain];
    }
    return [families objectForKey:engineName];
}

// The double tap a repeat of this tap reaches, or nil when a tap does not pair
// with one. A double tap has no recognizer: the single tap's recognizer runs
// twice, and the second run inside the Mac's double-click interval dispatches
// this name instead.
+ (NSString *)doubleTapGestureName:(NSString *)engineName {
    static NSDictionary *doubles = nil;
    if (doubles == nil) {
        doubles = [@{
            @"One-Finger Tap": @"One-Finger Double-Tap",
            @"Two-Finger Tap": @"Two-Finger Double-Tap",
            @"Three-Finger Tap": @"Three-Finger Double-Tap",
            @"Four-Finger Tap": @"Four-Finger Double-Tap",
            @"Five-Finger Tap": @"Five-Finger Double-Tap",
        } retain];
    }
    return [doubles objectForKey:engineName];
}

// Built-in engine commands, keyed by the slug the configuration uses. The value
// is the exact string dispatchCommand compares against in Gesture.m.
+ (NSDictionary *)actionNames {
    static NSDictionary *m = nil;
    if (m == nil) {
        m = [@{
            @"middle-click": @"Middle Click",
            @"mission-control": @"Mission Control",
            @"app-expose": @"Application Windows",
            @"show-desktop": @"Show Desktop",
            @"app-switcher": @"Application Switcher",
            @"next-tab": @"Next Tab",
            @"previous-tab": @"Previous Tab",
            @"new-tab": @"New Tab",
            @"close-tab": @"Close / Close Tab",
            @"reopen-tab": @"Open Recently Closed Tab",
            @"maximize": @"Maximize",
            @"minimize": @"Minimize",
        } retain];
    }
    return m;
}

// Engine gesture names phrased as the motion a hand makes, for the menu. Every
// name reachable from a slug table needs an entry; scripts/check.sh enforces it.
+ (NSString *)humanNameForGesture:(NSString *)raw {
    static NSDictionary *phrases = nil;
    if (phrases == nil) {
        phrases = [@{
            // Naming the held finger's side reads as a handedness claim
            // ("your left finger"), and the tap direction already carries the
            // shape, so the held finger goes unsided.
            @"Index-Fix Middle-Near-Tap": @"Hold a finger, tap to its right",
            @"Index-Fix Middle-Far-Tap": @"Hold a finger, tap wide to its right",
            @"Middle-Fix Index-Near-Tap": @"Hold a finger, tap to its left",
            @"Middle-Fix Index-Far-Tap": @"Hold a finger, tap wide to its left",
            @"One-Fix Left-Tap": @"Hold a finger, tap to its left",
            @"One-Fix Right-Tap": @"Hold a finger, tap to its right",
            @"One-Fix One-Slide": @"Hold one finger, slide another",
            @"Two-Fix Between-Tap": @"Hold two fingers, tap between them",
            @"Two-Fix Left-Tap": @"Hold two fingers, tap to their left",
            @"Two-Fix Right-Tap": @"Hold two fingers, tap to their right",
            @"One-Finger Tap": @"Tap with one finger",
            @"Two-Finger Tap": @"Tap with two fingers",
            @"Three-Finger Tap": @"Tap with three fingers",
            @"Four-Finger Tap": @"Tap with four fingers",
            @"Five-Finger Tap": @"Tap with five fingers",
            @"One-Finger Double-Tap": @"Tap twice with one finger",
            @"Two-Finger Double-Tap": @"Tap twice with two fingers",
            @"Three-Finger Double-Tap": @"Tap twice with three fingers",
            @"Four-Finger Double-Tap": @"Tap twice with four fingers",
            @"Five-Finger Double-Tap": @"Tap twice with five fingers",
            @"Two-Finger Click": @"Click with two fingers",
            @"Three-Finger Click": @"Click with three fingers",
            @"Four-Finger Click": @"Click with four fingers",
            // Area-click rows front-load the edge and separate the span with
            // a middle dot, so a column of similar bindings aligns and scans.
            @"Any-Edge Click": @"Click along any edge",
            @"Any-Corner Click": @"Click any corner",
            @"Left-Edge Click": @"Click left edge",
            @"Right-Edge Click": @"Click right edge",
            @"Top-Edge Click": @"Click top edge",
            @"Bottom-Edge Click": @"Click bottom edge",
            @"Left-Edge Top-Half Click": @"Click left edge · top half",
            @"Left-Edge Bottom-Half Click": @"Click left edge · bottom half",
            @"Right-Edge Top-Half Click": @"Click right edge · top half",
            @"Right-Edge Bottom-Half Click": @"Click right edge · bottom half",
            @"Top-Edge Left-Half Click": @"Click top edge · left half",
            @"Top-Edge Right-Half Click": @"Click top edge · right half",
            @"Bottom-Edge Left-Half Click": @"Click bottom edge · left half",
            @"Bottom-Edge Right-Half Click": @"Click bottom edge · right half",
            @"Left-Edge Top-Third Click": @"Click left edge · top third",
            @"Left-Edge Middle-Third Click": @"Click left edge · middle third",
            @"Left-Edge Bottom-Third Click": @"Click left edge · bottom third",
            @"Right-Edge Top-Third Click": @"Click right edge · top third",
            @"Right-Edge Middle-Third Click": @"Click right edge · middle third",
            @"Right-Edge Bottom-Third Click": @"Click right edge · bottom third",
            @"Top-Edge Left-Third Click": @"Click top edge · left third",
            @"Top-Edge Middle-Third Click": @"Click top edge · middle third",
            @"Top-Edge Right-Third Click": @"Click top edge · right third",
            @"Bottom-Edge Left-Third Click": @"Click bottom edge · left third",
            @"Bottom-Edge Middle-Third Click": @"Click bottom edge · middle third",
            @"Bottom-Edge Right-Third Click": @"Click bottom edge · right third",
            @"Top-Left-Corner Click": @"Click top left corner",
            @"Top-Right-Corner Click": @"Click top right corner",
            @"Bottom-Left-Corner Click": @"Click bottom left corner",
            @"Bottom-Right-Corner Click": @"Click bottom right corner",
            @"Right-Front Tap": @"Tap the front right of the mouse",
            @"One-Swipe-Any": @"Swipe with one finger, any direction",
            @"Two-Swipe-Any": @"Swipe with two fingers, any direction",
            @"Three-Swipe-Any": @"Swipe with three fingers, any direction",
            @"Four-Swipe-Any": @"Swipe with four fingers, any direction",
            @"One-Swipe-Left": @"Swipe left with one finger",
            @"One-Swipe-Right": @"Swipe right with one finger",
            @"Two-Swipe-Left": @"Swipe left with two fingers",
            @"Two-Swipe-Right": @"Swipe right with two fingers",
            @"Three-Swipe-Left": @"Swipe left with three fingers",
            @"Three-Swipe-Right": @"Swipe right with three fingers",
            @"Three-Swipe-Up": @"Swipe up with three fingers",
            @"Three-Swipe-Down": @"Swipe down with three fingers",
            @"Four-Swipe-Left": @"Swipe left with four fingers",
            @"Four-Swipe-Right": @"Swipe right with four fingers",
            @"Four-Swipe-Up": @"Swipe up with four fingers",
            @"Four-Swipe-Down": @"Swipe down with four fingers",
            @"Index-To-Pinky": @"Brush index toward pinky",
            @"Pinky-To-Index": @"Brush pinky toward index",
        } retain];
    }
    NSString *phrase = [phrases objectForKey:raw];
    return phrase ?: raw;
}

#pragma mark - Keystroke vocabulary

static NSDictionary *keyNames(void) {
    static NSDictionary *m = nil;
    if (m == nil) {
        NSMutableDictionary *d = [[NSMutableDictionary alloc] init];
        NSDictionary *named = @{
            @"return": @36, @"enter": @36,
            @"escape": @53, @"esc": @53,
            @"tab": @48,
            @"space": @49, @"spacebar": @49,
            @"delete": @51, @"backspace": @51, @"del": @51,
            @"forward-delete": @117,
            @"keypad-enter": @76,
            @"left": @123, @"right": @124, @"down": @125, @"up": @126,
            @"home": @115, @"end": @119,
            @"page-up": @116, @"page-down": @121,
            @"f1": @122, @"f2": @120, @"f3": @99, @"f4": @118,
            @"f5": @96, @"f6": @97, @"f7": @98, @"f8": @100,
            @"f9": @101, @"f10": @109, @"f11": @103, @"f12": @111,
            @"[": @33, @"]": @30, @"-": @27, @"=": @24,
            @";": @41, @"'": @39, @",": @43, @".": @47, @"/": @44,
            @"\\": @42, @"`": @50,
        };
        [d addEntriesFromDictionary:named];

        // Letters and digits are derived directly instead of listed in the tables.
        NSString *letters = @"asdfhgzxcv bqweryt123465=97-80]ou[ip lj'k;\\,/nm.";
        const int letterCodes[] = {0,1,2,3,4,5,6,7,8,9,-1,11,12,13,14,15,16,17,
                                   18,19,20,21,23,22,24,25,26,27,28,29,30,31,32,
                                   33,34,35,-1,37,38,39,40,41,42,43,44,45,46,47};
        for (NSUInteger i = 0; i < [letters length] && i < sizeof(letterCodes)/sizeof(int); i++) {
            if (letterCodes[i] < 0)
                continue;
            NSString *ch = [letters substringWithRange:NSMakeRange(i, 1)];
            if ([d objectForKey:ch] == nil)
                [d setObject:@(letterCodes[i]) forKey:ch];
        }
        m = d;
    }
    return m;
}

// Modifier spellings are lowercase. Symbols allow copied keyboard shortcuts to
// parse without replacing the symbols with names.
static NSDictionary *modifierNames(void) {
    static NSDictionary *m = nil;
    if (m == nil) {
        m = [@{
            @"cmd": @(kCGEventFlagMaskCommand | NX_DEVICELCMDKEYMASK),
            @"command": @(kCGEventFlagMaskCommand | NX_DEVICELCMDKEYMASK),
            @"⌘": @(kCGEventFlagMaskCommand | NX_DEVICELCMDKEYMASK),
            @"left-cmd": @(kCGEventFlagMaskCommand | NX_DEVICELCMDKEYMASK),
            @"left-command": @(kCGEventFlagMaskCommand | NX_DEVICELCMDKEYMASK),
            @"right-cmd": @(kCGEventFlagMaskCommand | NX_DEVICERCMDKEYMASK),
            @"right-command": @(kCGEventFlagMaskCommand | NX_DEVICERCMDKEYMASK),
            @"ctrl": @(kCGEventFlagMaskControl | NX_DEVICELCTLKEYMASK),
            @"control": @(kCGEventFlagMaskControl | NX_DEVICELCTLKEYMASK),
            @"⌃": @(kCGEventFlagMaskControl | NX_DEVICELCTLKEYMASK),
            @"left-ctrl": @(kCGEventFlagMaskControl | NX_DEVICELCTLKEYMASK),
            @"left-control": @(kCGEventFlagMaskControl | NX_DEVICELCTLKEYMASK),
            @"right-ctrl": @(kCGEventFlagMaskControl | NX_DEVICERCTLKEYMASK),
            @"right-control": @(kCGEventFlagMaskControl | NX_DEVICERCTLKEYMASK),
            @"opt": @(kCGEventFlagMaskAlternate | NX_DEVICELALTKEYMASK),
            @"option": @(kCGEventFlagMaskAlternate | NX_DEVICELALTKEYMASK),
            @"alt": @(kCGEventFlagMaskAlternate | NX_DEVICELALTKEYMASK),
            @"⌥": @(kCGEventFlagMaskAlternate | NX_DEVICELALTKEYMASK),
            @"left-opt": @(kCGEventFlagMaskAlternate | NX_DEVICELALTKEYMASK),
            @"left-option": @(kCGEventFlagMaskAlternate | NX_DEVICELALTKEYMASK),
            @"left-alt": @(kCGEventFlagMaskAlternate | NX_DEVICELALTKEYMASK),
            @"right-opt": @(kCGEventFlagMaskAlternate | NX_DEVICERALTKEYMASK),
            @"right-option": @(kCGEventFlagMaskAlternate | NX_DEVICERALTKEYMASK),
            @"right-alt": @(kCGEventFlagMaskAlternate | NX_DEVICERALTKEYMASK),
            @"shift": @(kCGEventFlagMaskShift | NX_DEVICELSHIFTKEYMASK),
            @"⇧": @(kCGEventFlagMaskShift | NX_DEVICELSHIFTKEYMASK),
            @"left-shift": @(kCGEventFlagMaskShift | NX_DEVICELSHIFTKEYMASK),
            @"right-shift": @(kCGEventFlagMaskShift | NX_DEVICERSHIFTKEYMASK),
        } retain];
    }
    return m;
}

static NSString *keyDisplayName(NSString *token) {
    NSDictionary *named = @{
        @"return": @"Return", @"enter": @"Return",
        @"escape": @"Escape", @"esc": @"Escape",
        @"tab": @"Tab", @"space": @"Space", @"spacebar": @"Space",
        @"delete": @"Delete", @"backspace": @"Delete", @"del": @"Delete",
        @"forward-delete": @"Forward Delete", @"keypad-enter": @"Keypad Enter",
        @"left": @"Left", @"right": @"Right", @"down": @"Down", @"up": @"Up",
        @"home": @"Home", @"end": @"End",
        @"page-up": @"Page Up", @"page-down": @"Page Down",
    };
    NSString *display = [named objectForKey:token];
    if (display != nil)
        return display;
    if ([token length] == 1 && [[NSCharacterSet letterCharacterSet]
        characterIsMember:[token characterAtIndex:0]])
        return [token uppercaseString];
    if ([token hasPrefix:@"f"] && [token length] <= 3)
        return [token uppercaseString];
    return token;
}

static void recordExplicitModifierSide(NSMutableDictionary *sides,
                                       NSString *token) {
    NSArray *parts = [token componentsSeparatedByString:@"-"];
    if ([parts count] != 2 ||
        ![@[@"left", @"right"] containsObject:[parts objectAtIndex:0]])
        return;
    NSString *name = [parts objectAtIndex:1];
    NSDictionary *families = @{
        @"ctrl": @"control", @"control": @"control",
        @"opt": @"option", @"option": @"option", @"alt": @"option",
        @"shift": @"shift",
        @"cmd": @"command", @"command": @"command",
    };
    NSString *family = [families objectForKey:name];
    if (family == nil)
        return;
    NSString *side = [parts objectAtIndex:0];
    NSString *existing = [sides objectForKey:family];
    if (existing == nil || [existing isEqualToString:side])
        [sides setObject:side forKey:family];
    else
        [sides setObject:@"both" forKey:family];
}

#pragma mark - Value parsing

static NSString *stripQuotes(NSString *s) {
    if ([s length] >= 2) {
        unichar first = [s characterAtIndex:0];
        unichar last = [s characterAtIndex:[s length] - 1];
        if (first == '"' && last == '"') {
            NSString *array = [NSString stringWithFormat:@"[%@]", s];
            NSData *data = [array dataUsingEncoding:NSUTF8StringEncoding];
            NSArray *decoded = data == nil ? nil :
                [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
            if ([decoded isKindOfClass:[NSArray class]] && [decoded count] == 1 &&
                [[decoded firstObject] isKindOfClass:[NSString class]])
                return [decoded firstObject];
        }
        if (first == '\'' && last == '\'')
            return [s substringWithRange:NSMakeRange(1, [s length] - 2)];
    }
    return s;
}

static BOOL parseBooleanValue(NSString *v, BOOL *result) {
    NSString *s = [[stripQuotes(v) lowercaseString] stringByTrimmingCharactersInSet:
                   [NSCharacterSet whitespaceCharacterSet]];
    if ([@[@"true", @"yes", @"on", @"1"] containsObject:s]) {
        if (result) *result = YES;
        return YES;
    }
    if ([@[@"false", @"no", @"off", @"0"] containsObject:s]) {
        if (result) *result = NO;
        return YES;
    }
    return NO;
}

static BOOL parseBoolean(NSString *v, BOOL fallback) {
    BOOL result = fallback;
    parseBooleanValue(v, &result);
    return result;
}

static BOOL parsePositiveNumber(NSString *v, double *result) {
    NSString *s = [stripQuotes(v) stringByTrimmingCharactersInSet:
                   [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSScanner *scanner = [NSScanner scannerWithString:s];
    double number = 0;
    if (![scanner scanDouble:&number] || ![scanner isAtEnd] || !isfinite(number) || number <= 0)
        return NO;
    if (result) *result = number;
    return YES;
}

// Returns why a custom URL cannot be opened, or nil when its structure is
// valid. Handler availability is deliberately left to macOS at dispatch time.
static NSString *urlProblem(NSString *value) {
    if ([value length] == 0)
        return @"URL is empty";

    if ([value rangeOfCharacterFromSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]].location != NSNotFound)
        return @"URL contains unencoded whitespace";

    NSRange colon = [value rangeOfString:@":"];
    if (colon.location == NSNotFound || colon.location == 0)
        return @"URL is missing a valid scheme followed by \":\"";

    NSString *scheme = [value substringToIndex:colon.location];
    NSCharacterSet *first = [NSCharacterSet characterSetWithCharactersInString:
                             @"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"];
    if (![first characterIsMember:[scheme characterAtIndex:0]])
        return @"URL scheme must begin with a letter";

    NSMutableCharacterSet *schemeCharacters = [NSMutableCharacterSet characterSetWithCharactersInString:
                                                @"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789+.-"];
    if ([scheme rangeOfCharacterFromSet:[schemeCharacters invertedSet]].location != NSNotFound)
        return @"URL scheme may contain only letters, digits, +, -, and .";

    NSCharacterSet *hex = [NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdefABCDEF"];
    for (NSUInteger i = 0; i < [value length]; i++) {
        if ([value characterAtIndex:i] != '%')
            continue;
        if (i + 2 >= [value length] ||
            ![hex characterIsMember:[value characterAtIndex:i + 1]] ||
            ![hex characterIsMember:[value characterAtIndex:i + 2]])
            return @"URL contains a malformed percent escape";
        i += 2;
    }

    if ([NSURL URLWithString:value] == nil)
        return @"URL could not be parsed";
    return nil;
}

static BOOL dateFormatHasBalancedQuotes(NSString *format) {
    BOOL quoted = NO;
    for (NSUInteger i = 0; i < [format length]; i++) {
        if ([format characterAtIndex:i] != '\'')
            continue;
        if (i + 1 < [format length] && [format characterAtIndex:i + 1] == '\'') {
            i++;
            continue;
        }
        quoted = !quoted;
    }
    return !quoted;
}

// Returns why a substitution expression is invalid, or nil for one of the
// three expressions the configuration language supports.
static NSString *substitutionProblem(NSString *expression) {
    if ([expression isEqualToString:@"clipboard"] ||
        [expression isEqualToString:@"clipboard|urlencode"])
        return nil;

    if ([expression hasPrefix:@"datetime:"]) {
        NSString *format = [expression substringFromIndex:9];
        if ([format length] == 0)
            return @"datetime substitution needs a format";
        if (!dateFormatHasBalancedQuotes(format))
            return @"datetime substitution has an unmatched quote";
        return nil;
    }

    if ([expression hasPrefix:@"clipboard|"])
        return [NSString stringWithFormat:@"unknown clipboard substitution filter \"%@\"",
                [expression substringFromIndex:10]];

    return [NSString stringWithFormat:@"unknown substitution \"%@\"", expression];
}

// Encodes one URL component using only RFC 3986 unreserved bytes. In
// particular, &, =, /, and ? are escaped rather than changing URL structure.
static NSString *encodeURLComponent(NSString *value) {
    NSCharacterSet *unreserved = [NSCharacterSet characterSetWithCharactersInString:
                                  @"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~"];
    return [(value ?: @"") stringByAddingPercentEncodingWithAllowedCharacters:unreserved];
}

+ (NSString *)URLByResolvingSubstitutions:(NSString *)url
                                clipboard:(NSString *)clipboard
                                     date:(NSDate *)date
                                  problem:(NSString **)outProblem {
    if (outProblem != NULL)
        *outProblem = nil;

    NSMutableString *resolved = [NSMutableString string];
    NSUInteger cursor = 0;
    while (cursor < [url length]) {
        unichar c = [url characterAtIndex:cursor];
        if (c != '{' && c != '}') {
            [resolved appendFormat:@"%C", c];
            cursor++;
            continue;
        }

        if (c == '}' || cursor + 1 >= [url length] || [url characterAtIndex:cursor + 1] != '{') {
            if (outProblem != NULL)
                *outProblem = @"substitution has unmatched braces";
            return nil;
        }

        NSRange close = [url rangeOfString:@"}}"
                                    options:0
                                      range:NSMakeRange(cursor + 2, [url length] - cursor - 2)];
        if (close.location == NSNotFound) {
            if (outProblem != NULL)
                *outProblem = @"substitution has unmatched braces";
            return nil;
        }

        NSString *expression = [url substringWithRange:NSMakeRange(cursor + 2,
                                              close.location - cursor - 2)];
        if ([expression rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"{}"]].location != NSNotFound) {
            if (outProblem != NULL)
                *outProblem = @"substitution has unmatched braces";
            return nil;
        }

        NSString *problem = substitutionProblem(expression);
        if (problem != nil) {
            if (outProblem != NULL)
                *outProblem = problem;
            return nil;
        }

        if ([expression isEqualToString:@"clipboard"])
            [resolved appendString:clipboard ?: @""];
        else if ([expression isEqualToString:@"clipboard|urlencode"])
            [resolved appendString:encodeURLComponent(clipboard)];
        else {
            NSDateFormatter *formatter = [[[NSDateFormatter alloc] init] autorelease];
            [formatter setLocale:[[[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"] autorelease]];
            [formatter setTimeZone:[NSTimeZone localTimeZone]];
            [formatter setDateFormat:[expression substringFromIndex:9]];
            [resolved appendString:[formatter stringFromDate:date ?: [NSDate date]]];
        }
        cursor = close.location + 2;
    }

    NSString *problem = urlProblem(resolved);
    if (problem != nil) {
        if (outProblem != NULL)
            *outProblem = problem;
        return nil;
    }
    return resolved;
}

static NSString *urlBindingProblem(NSString *url) {
    NSString *problem = nil;
    [Config URLByResolvingSubstitutions:url
                             clipboard:@"clipboard"
                                  date:[NSDate dateWithTimeIntervalSince1970:0]
                               problem:&problem];
    return problem;
}

// Resolves one directly executable file. Scripts run through their shebang;
// accepting shell source here would add a second configuration language.
static NSString *resolvedScriptPath(NSString *rawPath, NSString **outProblem) {
    NSString *path = [[rawPath stringByTrimmingCharactersInSet:
                       [NSCharacterSet whitespaceCharacterSet]] stringByExpandingTildeInPath];
    path = [path stringByStandardizingPath];
    NSString *problem = nil;
    if ([path length] == 0)
        problem = @"script path is empty";
    else if (![path isAbsolutePath])
        problem = @"script must use an absolute path or begin with ~";
    else {
        NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:NULL];
        if (attributes == nil)
            problem = @"script file does not exist";
        else if (![[attributes objectForKey:NSFileType] isEqualToString:NSFileTypeRegular])
            problem = @"script path is not a regular file";
        else if (![[NSFileManager defaultManager] isExecutableFileAtPath:path])
            problem = @"script file is not executable";
    }
    if (outProblem != NULL)
        *outProblem = problem;
    return problem == nil ? path : nil;
}

// Resolves one macOS system sound by name. The name is case-sensitive and
// carries no extension, so a binding names the sound the way System Settings
// does rather than a file path.
static NSString *resolvedSoundName(NSString *rawName, NSString **outProblem) {
    NSString *name = [rawName stringByTrimmingCharactersInSet:
                      [NSCharacterSet whitespaceCharacterSet]];
    NSString *problem = nil;
    if ([name length] == 0)
        problem = @"sound name is empty";
    else if ([name rangeOfString:@"/"].location != NSNotFound ||
             [name rangeOfString:@":"].location != NSNotFound)
        problem = @"sound must be a name in /System/Library/Sounds, not a path";
    else {
        BOOL found = NO;
        NSArray *files = [[NSFileManager defaultManager]
                          contentsOfDirectoryAtPath:@"/System/Library/Sounds" error:NULL];
        for (NSString *file in files) {
            if ([[file stringByDeletingPathExtension] isEqualToString:name]) {
                found = YES;
                break;
            }
        }
        if (!found)
            problem = [NSString stringWithFormat:
                       @"no sound named \"%@\" in /System/Library/Sounds", name];
    }
    if (outProblem != NULL)
        *outProblem = problem;
    return problem == nil ? name : nil;
}

// Validates the text a say: binding speaks when its gesture fires. The payload
// keeps its case and punctuation; only an empty phrase is meaningless.
static NSString *resolvedSpeechText(NSString *rawText, NSString **outProblem) {
    NSString *text = [rawText stringByTrimmingCharactersInSet:
                      [NSCharacterSet whitespaceCharacterSet]];
    NSString *problem = [text length] == 0 ? @"say needs the words to speak" : nil;
    if (outProblem != NULL)
        *outProblem = problem;
    return problem == nil ? text : nil;
}

// Returns an engine gesture dictionary, or nil for an unrecognized value.
// Keystrokes contain a key, modifiers, or both. Actions are dispatched by name.
static NSDictionary *parseBinding(NSString *rawValue) {
    NSString *unquoted = stripQuotes([rawValue stringByTrimmingCharactersInSet:
                         [NSCharacterSet whitespaceCharacterSet]]);
    NSString *value = [unquoted lowercaseString];
    if ([value length] == 0)
        return nil;

    if ([value isEqualToString:@"off"])
        return @{ @"Gesture": @"", @"Command": @"", @"IsAction": @YES,
                  @"ModifierFlags": @0, @"KeyCode": @0, @"Enable": @NO };

    if ([value hasPrefix:@"url:"]) {
        NSString *url = [unquoted substringFromIndex:4];
        if (urlBindingProblem(url) != nil)
            return nil;
        return @{ @"Gesture": @"", @"Command": url, @"OpenURL": url,
                  @"IsAction": @YES, @"ModifierFlags": @0, @"KeyCode": @0,
                  @"Enable": @YES };
    }

    if ([value hasPrefix:@"script:"]) {
        NSString *path = resolvedScriptPath([unquoted substringFromIndex:7], NULL);
        if (path == nil)
            return nil;
        return @{ @"Gesture": @"", @"Command": path, @"ScriptPath": path,
                  @"IsAction": @YES, @"ModifierFlags": @0, @"KeyCode": @0,
                  @"Enable": @YES };
    }

    if ([value hasPrefix:@"sound:"]) {
        NSString *name = resolvedSoundName([unquoted substringFromIndex:6], NULL);
        if (name == nil)
            return nil;
        return @{ @"Gesture": @"", @"Command": name, @"PlaySound": name,
                  @"IsAction": @YES, @"ModifierFlags": @0, @"KeyCode": @0,
                  @"Enable": @YES };
    }

    if ([value hasPrefix:@"say:"]) {
        NSString *text = resolvedSpeechText([unquoted substringFromIndex:4], NULL);
        if (text == nil)
            return nil;
        return @{ @"Gesture": @"", @"Command": text, @"SpeakText": text,
                  @"IsAction": @YES, @"ModifierFlags": @0, @"KeyCode": @0,
                  @"Enable": @YES };
    }

    NSString *action = [[Config actionNames] objectForKey:value];
    if (action != nil) {
        return @{@"Gesture": @"", @"Command": action, @"IsAction": @YES,
                 @"ModifierFlags": @0, @"KeyCode": @0, @"Enable": @YES};
    }

    NSUInteger flags = 0;
    NSMutableDictionary *explicitModifierSides = [NSMutableDictionary dictionary];

    // Leading modifier symbols have no separator and must be consumed first.
    while ([value length] > 0) {
        NSString *head = [value substringToIndex:1];
        NSNumber *flag = [modifierNames() objectForKey:head];
        if (flag == nil)
            break;
        flags |= [flag unsignedIntegerValue];
        value = [value substringFromIndex:1];
    }

    NSArray *tokens = nil;
    BOOL usesPlusSeparator = [value rangeOfString:@"+"].location != NSNotFound;
    if ([keyNames() objectForKey:value] != nil) {
        // Match the full value before splitting so the hyphens in page-down and
        // forward-delete are treated as part of the key name.
        tokens = @[value];
    } else {
        tokens = [value componentsSeparatedByString:@"+"];
        if ([tokens count] == 1) {
            NSMutableCharacterSet *seps = [NSMutableCharacterSet whitespaceCharacterSet];
            [seps addCharactersInString:@"-"];
            tokens = [value componentsSeparatedByCharactersInSet:seps];
        }
    }

    NSString *keyToken = nil;
    for (NSUInteger i = 0; i < [tokens count]; i++) {
        NSString *raw = [tokens objectAtIndex:i];
        NSString *t = [raw stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if ([t length] == 0) {
            if (usesPlusSeparator)
                return nil;
            continue;
        }
        NSString *modifierToken = t;
        NSNumber *flag = [modifierNames() objectForKey:t];
        if (flag == nil && ([t isEqualToString:@"left"] || [t isEqualToString:@"right"]) &&
            i + 1 < [tokens count]) {
            NSString *next = [[tokens objectAtIndex:i + 1]
                stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            NSString *sidedModifier = [NSString stringWithFormat:@"%@-%@", t, next];
            flag = [modifierNames() objectForKey:sidedModifier];
            if (flag != nil) {
                modifierToken = sidedModifier;
                i++;
            }
        }
        if (flag != nil) {
            flags |= [flag unsignedIntegerValue];
            recordExplicitModifierSide(explicitModifierSides, modifierToken);
            continue;
        }
        // A value carries exactly one key. An unknown token, or a second key,
        // rejects the whole value instead of binding a different shortcut.
        if (keyToken != nil || [keyNames() objectForKey:t] == nil)
            return nil;
        keyToken = t;
    }

    if (keyToken == nil && flags == 0)
        return nil;
    NSNumber *code = keyToken == nil ? nil : [keyNames() objectForKey:keyToken];
    if (keyToken != nil && code == nil)
        return nil;

    NSMutableDictionary *binding = [NSMutableDictionary dictionaryWithDictionary:@{
        @"Gesture": @"", @"Command": rawValue, @"IsAction": @NO,
        @"ModifierFlags": @(flags), @"Enable": @YES, @"HasKey": @(keyToken != nil),
    }];
    if (keyToken != nil) {
        [binding setObject:code forKey:@"KeyCode"];
        [binding setObject:keyDisplayName(keyToken) forKey:@"KeyDisplayName"];
    }
    if ([explicitModifierSides count] > 0)
        [binding setObject:explicitModifierSides forKey:@"ExplicitModifierSides"];
    return binding;
}

static const NSInteger kSequenceWaitLimitMilliseconds = 3000;

static NSString *bindingProblem(NSString *rawValue) {
    NSString *unquoted = stripQuotes([rawValue stringByTrimmingCharactersInSet:
                         [NSCharacterSet whitespaceCharacterSet]]);
    NSString *lower = [unquoted lowercaseString];
    if ([lower hasPrefix:@"url:"])
        return urlBindingProblem([unquoted substringFromIndex:4]);
    if ([lower hasPrefix:@"script:"]) {
        NSString *problem = nil;
        resolvedScriptPath([unquoted substringFromIndex:7], &problem);
        return problem;
    }
    if ([lower hasPrefix:@"sound:"]) {
        NSString *problem = nil;
        resolvedSoundName([unquoted substringFromIndex:6], &problem);
        return problem;
    }
    if ([lower hasPrefix:@"say:"]) {
        NSString *problem = nil;
        resolvedSpeechText([unquoted substringFromIndex:4], &problem);
        return problem;
    }
    if ([lower hasPrefix:@"wait:"])
        return @"wait: is available only inside a sequence array";
    return [NSString stringWithFormat:
            @"\"%@\" is not a key, shortcut, action, URL, script, sound, or speech", rawValue];
}

static NSDictionary *parseSequence(NSString *rawValue, NSString **outProblem) {
    NSData *data = [rawValue dataUsingEncoding:NSUTF8StringEncoding];
    id decoded = data == nil ? nil :
        [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
    if (![decoded isKindOfClass:[NSArray class]]) {
        if (outProblem != NULL)
            *outProblem = @"a sequence must be an array of binding strings";
        return nil;
    }
    NSArray *values = decoded;
    if ([values count] == 0) {
        if (outProblem != NULL)
            *outProblem = @"a sequence must contain at least one element";
        return nil;
    }

    NSMutableArray *steps = [NSMutableArray array];
    NSInteger totalWait = 0;
    NSCharacterSet *digits = [NSCharacterSet characterSetWithCharactersInString:@"0123456789"];
    for (NSUInteger i = 0; i < [values count]; i++) {
        id value = [values objectAtIndex:i];
        if (![value isKindOfClass:[NSString class]]) {
            if (outProblem != NULL)
                *outProblem = [NSString stringWithFormat:
                    @"sequence element %lu must be a binding string", (unsigned long)i + 1];
            return nil;
        }
        NSString *text = value;
        NSString *lower = [text lowercaseString];
        if ([lower hasPrefix:@"wait:"]) {
            NSString *milliseconds = [text substringFromIndex:5];
            if ([milliseconds length] == 0 ||
                [milliseconds rangeOfCharacterFromSet:[digits invertedSet]].location != NSNotFound) {
                if (outProblem != NULL)
                    *outProblem = [NSString stringWithFormat:
                        @"sequence element %lu wait must be a positive whole number of milliseconds",
                        (unsigned long)i + 1];
                return nil;
            }
            long long wait = [milliseconds longLongValue];
            if (wait <= 0) {
                if (outProblem != NULL)
                    *outProblem = [NSString stringWithFormat:
                        @"sequence element %lu wait must be a positive whole number of milliseconds",
                        (unsigned long)i + 1];
                return nil;
            }
            if (wait > kSequenceWaitLimitMilliseconds - totalWait) {
                if (outProblem != NULL)
                    *outProblem = [NSString stringWithFormat:
                        @"sequence waits total more than %ld ms; use script: for longer work",
                        (long)kSequenceWaitLimitMilliseconds];
                return nil;
            }
            totalWait += (NSInteger)wait;
            [steps addObject:@{ @"WaitMilliseconds": @((NSInteger)wait) }];
            continue;
        }

        NSDictionary *step = parseBinding(text);
        if (step == nil || ![[step objectForKey:@"Enable"] boolValue]) {
            NSString *problem = step == nil ? bindingProblem(text) :
                @"off is not an action inside a sequence";
            if (outProblem != NULL)
                *outProblem = [NSString stringWithFormat:@"sequence element %lu: %@",
                               (unsigned long)i + 1, problem];
            return nil;
        }
        [steps addObject:step];
    }

    if (outProblem != NULL)
        *outProblem = nil;
    return @{ @"Gesture": @"", @"Command": @"Sequence", @"Sequence": steps,
              @"IsAction": @YES, @"ModifierFlags": @0, @"KeyCode": @0,
              @"Enable": @YES };
}

+ (NSString *)keystrokeDisplayNameForBinding:(NSDictionary *)binding {
    NSUInteger flags = [[binding objectForKey:@"ModifierFlags"] unsignedIntegerValue];
    BOOL hasKey = [binding objectForKey:@"HasKey"] == nil ||
        [[binding objectForKey:@"HasKey"] boolValue];
    NSString *key = [binding objectForKey:@"KeyDisplayName"];
    if (hasKey && [key length] == 0)
        key = [NSString stringWithFormat:@"Key %@", [binding objectForKey:@"KeyCode"] ?: @"?"];
    NSDictionary *sides = [binding objectForKey:@"ExplicitModifierSides"];
    if ([sides count] == 0) {
        NSMutableString *out = [NSMutableString string];
        if (flags & kCGEventFlagMaskControl)   [out appendString:@"⌃"];
        if (flags & kCGEventFlagMaskAlternate) [out appendString:@"⌥"];
        if (flags & kCGEventFlagMaskShift)     [out appendString:@"⇧"];
        if (flags & kCGEventFlagMaskCommand)   [out appendString:@"⌘"];
        if (hasKey)
            [out appendString:key];
        return out;
    }

    NSMutableArray *parts = [NSMutableArray array];
    NSArray *modifiers = @[
        @[@"control", @"Control", @(kCGEventFlagMaskControl),
          @(NX_DEVICELCTLKEYMASK), @(NX_DEVICERCTLKEYMASK)],
        @[@"option", @"Option", @(kCGEventFlagMaskAlternate),
          @(NX_DEVICELALTKEYMASK), @(NX_DEVICERALTKEYMASK)],
        @[@"shift", @"Shift", @(kCGEventFlagMaskShift),
          @(NX_DEVICELSHIFTKEYMASK), @(NX_DEVICERSHIFTKEYMASK)],
        @[@"command", @"Command", @(kCGEventFlagMaskCommand),
          @(NX_DEVICELCMDKEYMASK), @(NX_DEVICERCMDKEYMASK)],
    ];
    for (NSArray *modifier in modifiers) {
        if (!(flags & [[modifier objectAtIndex:2] unsignedIntegerValue]))
            continue;
        NSString *side = [sides objectForKey:[modifier objectAtIndex:0]];
        NSString *name = [modifier objectAtIndex:1];
        BOOL hasBothSides = (flags & [[modifier objectAtIndex:3] unsignedIntegerValue]) &&
            (flags & [[modifier objectAtIndex:4] unsignedIntegerValue]);
        if (hasBothSides || [side isEqualToString:@"both"]) {
            [parts addObject:[NSString stringWithFormat:@"Left %@", name]];
            [parts addObject:[NSString stringWithFormat:@"Right %@", name]];
        } else {
            [parts addObject:side == nil ? name :
                [NSString stringWithFormat:@"%@ %@", [side capitalizedString], name]];
        }
    }
    if (hasKey)
        [parts addObject:key];
    return [parts componentsJoinedByString:@" + "];
}

#pragma mark - File loading

+ (NSString *)resolvedPath {
    NSDictionary *environment = [[NSProcessInfo processInfo] environment];
    NSString *override = [environment objectForKey:@"TRICKPAD_CONFIG"];
    if ([override length] > 0)
        return [override stringByStandardizingPath];

    NSString *path = [[self configDirectory] stringByAppendingPathComponent:@"config.toml"];
    if ([[NSFileManager defaultManager] fileExistsAtPath:path])
        return path;
    return nil;
}

+ (NSString *)configDirectory {
    return [@"~/.config/trickpad" stringByStandardizingPath];
}

// Setting names accepted in [GENERAL]. A name outside this set is reported
// rather than ignored, which catches a misspelling that would otherwise leave
// the default in place with no sign anything was wrong.
static NSSet *knownSettingNames(void) {
    static NSSet *s = nil;
    if (s == nil) {
        s = [[NSSet setWithArray:@[@"config-version", @"dominant-hand", @"menu-bar-icon", @"enable-mouse", @"enable-trackpad", @"tap-speed", @"trackpad-edge-gesture-depth",
                                   @"haptic-feedback", @"verbose-logging",
                                   // Accepted for compatibility with existing files. Magic Mouse
                                   // physical-click bindings load unconditionally, so nothing
                                   // reads this setting; it still parses as a boolean.
                                   @"experimental-mouse-click-gestures"]] retain];
    }
    return s;
}

static NSArray *splitExpandedProperties(NSString *body) {
    NSMutableArray *properties = [NSMutableArray array];
    NSUInteger start = 0;
    BOOL quoted = NO;
    BOOL escaped = NO;
    NSUInteger arrayDepth = 0;
    for (NSUInteger i = 0; i < [body length]; i++) {
        unichar character = [body characterAtIndex:i];
        if (character == '"' && !escaped)
            quoted = !quoted;
        if (!quoted && character == '[')
            arrayDepth++;
        else if (!quoted && character == ']' && arrayDepth > 0)
            arrayDepth--;
        if (character == ',' && !quoted && arrayDepth == 0) {
            [properties addObject:[body substringWithRange:NSMakeRange(start, i - start)]];
            start = i + 1;
        }
        escaped = character == '\\' && !escaped;
        if (character != '\\')
            escaped = NO;
    }
    [properties addObject:[body substringFromIndex:start]];
    return properties;
}

static NSUInteger unquotedClosingBraceLocation(NSString *text) {
    BOOL quoted = NO;
    BOOL escaped = NO;
    for (NSUInteger i = 0; i < [text length]; i++) {
        unichar character = [text characterAtIndex:i];
        if (character == '"' && !escaped)
            quoted = !quoted;
        if (character == '}' && !quoted)
            return i;
        escaped = character == '\\' && !escaped;
        if (character != '\\')
            escaped = NO;
    }
    return NSNotFound;
}

// tomlc17 owns syntax, escaping, comments, and table construction. This adapter
// serializes the small typed schema that the gesture validation below consumes.
static NSString *TOMLString(toml_datum_t datum) {
    if (datum.type != TOML_STRING || datum.u.s == NULL)
        return nil;
    return [NSString stringWithUTF8String:datum.u.s];
}

static NSString *quotedConfigString(NSString *value) {
    NSData *data = [NSJSONSerialization dataWithJSONObject:@[value] options:0 error:NULL];
    NSString *array = data == nil ? nil :
        [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease];
    if ([array length] < 2)
        return @"\"\"";
    return [[array substringWithRange:NSMakeRange(1, [array length] - 2)]
        stringByReplacingOccurrencesOfString:@"\\/" withString:@"/"];
}

static NSString *legacyScalar(toml_datum_t datum) {
    switch (datum.type) {
        case TOML_STRING:
            return quotedConfigString(TOMLString(datum));
        case TOML_BOOLEAN:
            return datum.u.boolean ? @"true" : @"false";
        case TOML_INT64:
            return [NSString stringWithFormat:@"%lld", (long long)datum.u.int64];
        case TOML_FP64:
            return [NSString stringWithFormat:@"%.17g", datum.u.fp64];
        default:
            return nil;
    }
}

static NSString *legacyArray(toml_datum_t array) {
    if (array.type != TOML_ARRAY)
        return nil;
    NSMutableArray *elements = [NSMutableArray array];
    for (int i = 0; i < array.u.arr.size; i++) {
        toml_datum_t element = array.u.arr.elem[i];
        NSString *rendered = element.type == TOML_ARRAY
            ? legacyArray(element) : legacyScalar(element);
        [elements addObject:rendered ?: @"null"];
    }
    return [NSString stringWithFormat:@"[%@]", [elements componentsJoinedByString:@", "]];
}

static NSString *legacyInlineTable(toml_datum_t table) {
    if (table.type != TOML_TABLE || !(table.flag & TOML_FLAG_INLINED))
        return nil;
    NSMutableArray *properties = [NSMutableArray array];
    for (int i = 0; i < table.u.tab.size; i++) {
        NSString *key = [NSString stringWithUTF8String:table.u.tab.key[i]];
        toml_datum_t datum = table.u.tab.value[i];
        NSString *value = datum.type == TOML_ARRAY
            ? legacyArray(datum) : legacyScalar(datum);
        if (value == nil)
            value = @"\"<unsupported TOML value>\"";
        [properties addObject:[NSString stringWithFormat:@"%@ = %@", key, value]];
    }
    return [NSString stringWithFormat:@"{ %@ }", [properties componentsJoinedByString:@", "]];
}

static void addDiagnostic(NSMutableArray *diagnostics, NSString *message,
                          NSString *device, NSString *title, NSString *reason) {
    NSMutableDictionary *diagnostic = [NSMutableDictionary dictionaryWithObject:message
                                                                          forKey:@"Message"];
    if (device != nil) [diagnostic setObject:device forKey:@"Device"];
    if (title != nil) [diagnostic setObject:title forKey:@"Title"];
    if (reason != nil) [diagnostic setObject:reason forKey:@"Reason"];
    [diagnostics addObject:diagnostic];
}

// Extracts trailing TOML comments once while Config owns the source. tomlc17's
// line numbers then attach each comment to the binding parsed from that line.
static NSArray *sourceComments(NSString *text) {
    NSMutableArray *comments = [NSMutableArray array];
    for (NSString *line in [text componentsSeparatedByString:@"\n"]) {
        BOOL inBasic = NO, inLiteral = NO, escaped = NO;
        NSString *comment = @"";
        for (NSUInteger i = 0; i < [line length]; i++) {
            unichar c = [line characterAtIndex:i];
            if (inBasic) {
                if (escaped) escaped = NO;
                else if (c == '\\') escaped = YES;
                else if (c == '"') inBasic = NO;
            } else if (inLiteral) {
                if (c == '\'') inLiteral = NO;
            } else if (c == '"') {
                inBasic = YES;
            } else if (c == '\'') {
                inLiteral = YES;
            } else if (c == '#') {
                // whitespaceAndNewlineCharacterSet: under CRLF endings each line
                // keeps a trailing CR that whitespaceCharacterSet would preserve,
                // and a CR appended into the reconstructed text becomes a phantom
                // line inflating every later diagnostic's reported line number.
                comment = [[line substringFromIndex:i + 1]
                    stringByTrimmingCharactersInSet:
                        [NSCharacterSet whitespaceAndNewlineCharacterSet]];
                break;
            }
        }
        [comments addObject:comment];
    }
    return comments;
}

// Removes parser-only comments from the engine dictionary and indexes them by
// the same device, application, and gesture names the menu already receives.
static NSDictionary *detachSourceComments(NSDictionary *settings) {
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    for (NSArray *pair in @[@[@"Mouse", @"MagicMouseCommands"],
                             @[@"Trackpad", @"TrackpadCommands"]]) {
        NSMutableDictionary *applications = [NSMutableDictionary dictionary];
        for (NSDictionary *application in [settings objectForKey:pair[1]]) {
            NSMutableDictionary *gestures = [NSMutableDictionary dictionary];
            for (NSMutableDictionary *binding in [application objectForKey:@"Gestures"]) {
                NSString *comment = [binding objectForKey:@"SourceComment"];
                if (comment != nil) {
                    [gestures setObject:comment forKey:[binding objectForKey:@"Gesture"]];
                    [binding removeObjectForKey:@"SourceComment"];
                }
            }
            if ([gestures count] > 0)
                [applications setObject:gestures forKey:[application objectForKey:@"Application"]];
        }
        if ([applications count] > 0)
            [result setObject:applications forKey:pair[0]];
    }
    return result;
}

static void appendLegacyLine(NSMutableString *output, NSInteger *currentLine,
                             NSInteger sourceLine, NSString *line) {
    while (*currentLine < MAX(1, sourceLine)) {
        [output appendString:@"\n"];
        (*currentLine)++;
    }
    [output appendFormat:@"%@\n", line];
    (*currentLine)++;
}

static void appendTOMLTable(NSMutableString *output, NSInteger *currentLine,
                            NSString *section, NSString *application,
                            toml_datum_t table, NSArray *comments) {
    NSString *header = application == nil
        ? [NSString stringWithFormat:@"[%@]", [section lowercaseString]]
        : [NSString stringWithFormat:@"[%@ %@]", [section lowercaseString],
                                           quotedConfigString(application)];
    appendLegacyLine(output, currentLine, table.lineno, header);
    for (int i = 0; i < table.u.tab.size; i++) {
        toml_datum_t value = table.u.tab.value[i];
        if (value.type == TOML_TABLE && !(value.flag & TOML_FLAG_INLINED))
            continue;
        NSString *key = [NSString stringWithUTF8String:table.u.tab.key[i]];
        NSString *rendered = value.type == TOML_TABLE
            ? legacyInlineTable(value) : value.type == TOML_ARRAY
                ? legacyArray(value) : legacyScalar(value);
        if ([section isEqualToString:@"GENERAL"] && application == nil) {
            NSSet *booleans = [NSSet setWithArray:@[
                @"enable-mouse", @"enable-trackpad", @"haptic-feedback",
                @"verbose-logging", @"experimental-mouse-click-gestures"]];
            BOOL wrongType = ([booleans containsObject:key] && value.type != TOML_BOOLEAN) ||
                ([key isEqualToString:@"config-version"] && value.type != TOML_INT64) ||
                (([key isEqualToString:@"dominant-hand"] || [key isEqualToString:@"menu-bar-icon"]) && value.type != TOML_STRING) ||
                (([key isEqualToString:@"tap-speed"] || [key isEqualToString:@"trackpad-edge-gesture-depth"]) &&
                 value.type != TOML_INT64 && value.type != TOML_FP64);
            if (wrongType)
                rendered = @"\"<wrong TOML type>\"";
        }
        if (rendered == nil)
            rendered = @"\"<unsupported TOML value>\"";
        NSString *line = value.type == TOML_TABLE
            ? [NSString stringWithFormat:@"%@ %@", key, rendered]
            : [NSString stringWithFormat:@"%@ = %@", key, rendered];
        if (value.lineno > 0 && (NSUInteger)value.lineno <= [comments count]) {
            NSString *comment = [comments objectAtIndex:(NSUInteger)value.lineno - 1];
            if ([comment length] > 0)
                line = [line stringByAppendingFormat:@" # %@", comment];
        }
        appendLegacyLine(output, currentLine, value.lineno, line);
    }
}

static NSString *legacyTextFromTOML(toml_datum_t root, NSMutableArray *diagnostics,
                                    NSArray *comments) {
    NSMutableString *output = [NSMutableString string];
    NSInteger currentLine = 1;
    for (int i = 0; i < root.u.tab.size; i++) {
        NSString *section = [NSString stringWithUTF8String:root.u.tab.key[i]];
        toml_datum_t table = root.u.tab.value[i];
        if (table.type != TOML_TABLE) {
            addDiagnostic(diagnostics, [NSString stringWithFormat:
                @"line %d:  %@\n          settings must be inside [GENERAL], [MOUSE], or [TRACKPAD]",
                table.lineno, section], nil, nil, nil);
            continue;
        }
        if (![@[@"GENERAL", @"MOUSE", @"TRACKPAD"] containsObject:section]) {
            addDiagnostic(diagnostics, [NSString stringWithFormat:
                @"line %d:  [%@]\n          no section named \"%@\"; TOML table names are case-sensitive",
                table.lineno, section, section], nil, nil, nil);
            continue;
        }
        appendTOMLTable(output, &currentLine, section, nil, table, comments);
        if ([section isEqualToString:@"MOUSE"] || [section isEqualToString:@"TRACKPAD"]) {
            for (int j = 0; j < table.u.tab.size; j++) {
                toml_datum_t application = table.u.tab.value[j];
                if (application.type != TOML_TABLE ||
                    (application.flag & TOML_FLAG_INLINED))
                    continue;
                NSString *name = [NSString stringWithUTF8String:table.u.tab.key[j]];
                appendTOMLTable(output, &currentLine, section, name, application, comments);
                for (int k = 0; k < application.u.tab.size; k++) {
                    toml_datum_t nested = application.u.tab.value[k];
                    if (nested.type == TOML_TABLE && !(nested.flag & TOML_FLAG_INLINED))
                        addDiagnostic(diagnostics, [NSString stringWithFormat:
                            @"line %d:  nested application tables are not supported", nested.lineno],
                            nil, nil, nil);
                }
            }
        } else {
            for (int j = 0; j < table.u.tab.size; j++) {
                toml_datum_t nested = table.u.tab.value[j];
                if (nested.type == TOML_TABLE && !(nested.flag & TOML_FLAG_INLINED))
                    addDiagnostic(diagnostics, [NSString stringWithFormat:
                        @"line %d:  [GENERAL] does not contain nested tables", nested.lineno],
                        nil, nil, nil);
            }
        }
    }
    return output;
}

+ (NSDictionary *)settingsFromFile:(NSString *)path {
    return [[Config resultFromFile:path] settings];
}

+ (NSDictionary *)settingsFromFile:(NSString *)path problems:(NSArray **)outProblems {
    ConfigResult *result = [Config resultFromFile:path];
    if (outProblems != NULL) {
        NSMutableArray *messages = [NSMutableArray array];
        for (NSDictionary *diagnostic in [result diagnostics])
            [messages addObject:[diagnostic objectForKey:@"Message"]];
        *outProblems = messages;
    }
    return [result settings];
}

+ (ConfigResult *)resultFromFile:(NSString *)path {
    ConfigResult *result = [[[ConfigResult alloc] init] autorelease];
    NSMutableArray *diagnostics = [NSMutableArray array];
    result.diagnostics = diagnostics;
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (data == nil)
        return result;
    NSString *text = [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease];
    if (text == nil) {
        addDiagnostic(diagnostics, @"config.toml must be valid UTF-8", nil, nil, nil);
        return result;
    }
    toml_result_t parsed = toml_parse_named(
        [text UTF8String], (int)[text lengthOfBytesUsingEncoding:NSUTF8StringEncoding],
        [path UTF8String]);
    if (!parsed.ok) {
        addDiagnostic(diagnostics, [NSString stringWithUTF8String:parsed.errmsg], nil, nil, nil);
        toml_free(parsed);
        return result;
    }
    NSString *legacy = legacyTextFromTOML(parsed.toptab, diagnostics, sourceComments(text));
    toml_free(parsed);
    NSDictionary *settings = [Config settingsFromLegacyText:legacy diagnostics:diagnostics];
    if (settings != nil)
        result.sourceComments = detachSourceComments(settings);
    result.settings = settings;
    return result;
}

+ (NSDictionary *)settingsFromLegacyText:(NSString *)text diagnostics:(NSMutableArray *)diagnostics {
    NSMutableArray *mouse = [NSMutableArray array];
    NSMutableArray *trackpad = [NSMutableArray array];
    NSMutableDictionary *mouseScopes = [NSMutableDictionary dictionaryWithObject:mouse
                                                                           forKey:@"All Applications"];
    NSMutableDictionary *trackpadScopes = [NSMutableDictionary dictionaryWithObject:trackpad
                                                                              forKey:@"All Applications"];
    NSMutableArray *mouseScopeOrder = [NSMutableArray arrayWithObject:@"All Applications"];
    NSMutableArray *trackpadScopeOrder = [NSMutableArray arrayWithObject:@"All Applications"];
    NSMutableDictionary *general = [NSMutableDictionary dictionary];
    __block NSString *section = @"general";
    NSString *application = nil;
    NSMutableSet *activeBindingKeys = [NSMutableSet set];
    __block NSInteger lineNumber = 0;
    NSInteger physicalLineNumber = 0;
    NSInteger pendingBlockLine = 0;
    NSMutableString *pendingBlock = nil;
    __block BOOL unsupportedVersion = NO;

    void (^report)(NSString *, NSString *) = ^(NSString *text, NSString *reason) {
        NSString *device = [section isEqualToString:@"mouse"] ? @"Mouse" :
            ([section isEqualToString:@"trackpad"] ? @"Trackpad" : nil);
        addDiagnostic(diagnostics,
                      [NSString stringWithFormat:@"line %ld:  %@\n          %@",
                       (long)lineNumber, text, reason], device,
                      device == nil ? nil : text, device == nil ? nil : reason);
    };

    for (NSString *rawLine in [text componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]]) {
        physicalLineNumber++;
        NSString *line = rawLine;
        NSString *sourceComment = nil;
        // The TOML parser already handled comments. This second pass only
        // supports the canonical text consumed by the legacy semantic layer;
        // keep # characters inside the adapter's quoted strings intact.
        BOOL quoted = NO;
        BOOL escaped = NO;
        for (NSUInteger i = 0; i < [line length]; i++) {
            unichar character = [line characterAtIndex:i];
            if (character == '"' && !escaped)
                quoted = !quoted;
            if (character == '#' && !quoted &&
                (i == 0 || [[NSCharacterSet whitespaceCharacterSet]
                            characterIsMember:[line characterAtIndex:i - 1]])) {
                sourceComment = [[line substringFromIndex:i + 1]
                    stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
                line = [line substringToIndex:i];
                break;
            }
            escaped = character == '\\' && !escaped;
            if (character != '\\')
                escaped = NO;
        }
        line = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if ([line length] == 0)
            continue;

        BOOL completedPendingBlock = NO;
        if (pendingBlock != nil) {
            NSRange pendingEquals = [line rangeOfString:@"="];
            NSString *pendingKey = pendingEquals.location == NSNotFound ? @"" :
                [[line substringToIndex:pendingEquals.location]
                    stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            NSRange pendingOpeningBrace = [line rangeOfString:@"{"];
            BOOL startsSection = [line hasPrefix:@"["];
            BOOL startsBinding = (pendingOpeningBrace.location != NSNotFound &&
                                  (pendingEquals.location == NSNotFound ||
                                   pendingOpeningBrace.location < pendingEquals.location)) ||
                (pendingEquals.location != NSNotFound &&
                 ![@[@"action", @"defer", @"haptic", @"sound", @"say"] containsObject:[pendingKey lowercaseString]]);
            if (startsSection || startsBinding) {
                lineNumber = pendingBlockLine;
                report(pendingBlock, @"expanded binding is missing a closing }");
                pendingBlock = nil;
                lineNumber = physicalLineNumber;
            } else {
                [pendingBlock appendFormat:@"\n%@", line];
                if (unquotedClosingBraceLocation(pendingBlock) == NSNotFound)
                    continue;
                line = pendingBlock;
                lineNumber = pendingBlockLine;
                pendingBlock = nil;
                completedPendingBlock = YES;
            }
        }
        if (!completedPendingBlock) {
            lineNumber = physicalLineNumber;
            NSRange openingBrace = [line rangeOfString:@"{"];
            NSRange equals = [line rangeOfString:@"="];
            BOOL beginsBlock = openingBrace.location != NSNotFound &&
                (equals.location == NSNotFound || openingBrace.location < equals.location);
            if (beginsBlock && unquotedClosingBraceLocation(line) == NSNotFound) {
                pendingBlock = [NSMutableString stringWithString:line];
                pendingBlockLine = lineNumber;
                continue;
            }
        }

        if ([line hasPrefix:@"["] && [line hasSuffix:@"]"]) {
            NSString *header = [[line substringWithRange:NSMakeRange(1, [line length] - 2)]
                                stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            NSString *lowerHeader = [header lowercaseString];
            application = nil;
            if ([lowerHeader isEqualToString:@"general"] ||
                [lowerHeader isEqualToString:@"mouse"] ||
                [lowerHeader isEqualToString:@"trackpad"]) {
                section = lowerHeader;
            } else {
                NSString *matchedDevice = nil;
                for (NSString *candidate in @[@"mouse", @"trackpad"]) {
                    if ([lowerHeader hasPrefix:[candidate stringByAppendingString:@" "]]) {
                        matchedDevice = candidate;
                        break;
                    }
                }
                NSString *selector = matchedDevice == nil ? nil :
                    [header substringFromIndex:[matchedDevice length]];
                selector = [selector stringByTrimmingCharactersInSet:
                            [NSCharacterSet whitespaceCharacterSet]];
                if (matchedDevice == nil || [selector length] < 2 ||
                    [selector characterAtIndex:0] != '"' ||
                    [selector characterAtIndex:[selector length] - 1] != '"' ||
                    [[selector substringWithRange:NSMakeRange(1, [selector length] - 2)] length] == 0) {
                    report(line, @"section must be [GENERAL], [MOUSE], [TRACKPAD], or a device application table");
                    section = @"invalid";
                    continue;
                }
                section = matchedDevice;
                application = [selector substringWithRange:NSMakeRange(1, [selector length] - 2)];
                NSMutableDictionary *scopes = [section isEqualToString:@"mouse"]
                    ? mouseScopes : trackpadScopes;
                NSMutableArray *order = [section isEqualToString:@"mouse"]
                    ? mouseScopeOrder : trackpadScopeOrder;
                if ([scopes objectForKey:application] == nil) {
                    [scopes setObject:[NSMutableArray array] forKey:application];
                    [order addObject:application];
                }
            }
            continue;
        }

        NSString *expandedValue = nil;
        NSNumber *expandedDefer = nil;
        NSNumber *expandedHaptic = nil;
    NSString *expandedSound = nil;
    NSString *expandedSpeech = nil;
        BOOL expandedInvalid = NO;
        NSRange openingBrace = [line rangeOfString:@"{"];
        NSUInteger closingBraceLocation = unquotedClosingBraceLocation(line);
        NSRange closingBrace = NSMakeRange(closingBraceLocation, closingBraceLocation == NSNotFound ? 0 : 1);
        NSRange firstEquals = [line rangeOfString:@"="];
        BOOL expanded = openingBrace.location != NSNotFound &&
            closingBrace.location != NSNotFound &&
            closingBrace.location > openingBrace.location &&
            (firstEquals.location == NSNotFound || openingBrace.location < firstEquals.location);
        if (expanded) {
            NSString *tail = [[line substringFromIndex:closingBrace.location + 1]
                stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            if ([tail length] > 0) {
                report(line, @"nothing may follow an expanded binding block");
                continue;
            }
            NSString *body = [line substringWithRange:NSMakeRange(
                openingBrace.location + 1, closingBrace.location - openingBrace.location - 1)];
            NSArray *properties = splitExpandedProperties(body);
            for (NSString *rawProperty in properties) {
                NSString *property = [rawProperty stringByTrimmingCharactersInSet:
                    [NSCharacterSet whitespaceAndNewlineCharacterSet]];
                if ([property length] == 0)
                    continue;
                NSRange propertyEquals = [property rangeOfString:@"="];
                if (propertyEquals.location == NSNotFound) {
                    report(line, @"expanded properties use name = value and commas between properties");
                    expandedInvalid = YES;
                    break;
                }
                NSString *propertyName = [[[property substringToIndex:propertyEquals.location]
                    stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] lowercaseString];
                NSString *propertyValue = [[property substringFromIndex:propertyEquals.location + 1]
                    stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
                if ([propertyName isEqualToString:@"action"]) {
                    if ([propertyValue length] < 2 ||
                        !(([propertyValue characterAtIndex:0] == '"' &&
                           [propertyValue characterAtIndex:[propertyValue length] - 1] == '"') ||
                          ([propertyValue characterAtIndex:0] == '[' &&
                           [propertyValue characterAtIndex:[propertyValue length] - 1] == ']'))) {
                        report(line, @"an expanded action value must be a string or sequence array");
                        expandedInvalid = YES;
                        break;
                    }
                    expandedValue = propertyValue;
                } else if ([propertyName isEqualToString:@"defer"]) {
                    BOOL deferValue = NO;
                    if (!parseBooleanValue(propertyValue, &deferValue)) {
                        report(line, @"defer must be true, false, yes, no, on, off, 1, or 0");
                        expandedInvalid = YES;
                        break;
                    }
                    expandedDefer = @(deferValue);
                } else if ([propertyName isEqualToString:@"haptic"]) {
                    BOOL hapticValue = NO;
                    if (!parseBooleanValue(propertyValue, &hapticValue)) {
                        report(line, @"haptic must be true, false, yes, no, on, off, 1, or 0");
                        expandedInvalid = YES;
                        break;
                    }
                    expandedHaptic = @(hapticValue);
                } else if ([propertyName isEqualToString:@"sound"]) {
                    NSString *problem = nil;
                    NSString *name = resolvedSoundName(stripQuotes(propertyValue), &problem);
                    if (name == nil) {
                        report(line, problem);
                        expandedInvalid = YES;
                        break;
                    }
                    expandedSound = name;
                } else if ([propertyName isEqualToString:@"say"]) {
                    NSString *problem = nil;
                    NSString *text = resolvedSpeechText(stripQuotes(propertyValue), &problem);
                    if (text == nil) {
                        report(line, problem);
                        expandedInvalid = YES;
                        break;
                    }
                    expandedSpeech = text;
                } else {
                    report(line, [NSString stringWithFormat:@"no binding property named \"%@\"", propertyName]);
                    expandedInvalid = YES;
                    break;
                }
            }
            if (expandedInvalid)
                continue;
            if (expandedValue == nil && application == nil) {
                report(line, @"a global expanded binding requires an action property");
                continue;
            }
        }

        NSRange eq = expanded ? NSMakeRange(NSNotFound, 0) : [line rangeOfString:@"="];
        if (eq.location == NSNotFound) {
            if (!expanded) {
                report(line, @"not a setting: expected name = value");
                continue;
            }
        }
        NSString *key = [[line substringToIndex:expanded ? openingBrace.location : eq.location]
                         stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        NSString *value = expanded ? expandedValue :
            [[line substringFromIndex:eq.location + 1]
             stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        key = [key lowercaseString];

        NSString *device = section;

        if ([device isEqualToString:@"mouse"] || [device isEqualToString:@"trackpad"]) {
            NSDictionary *slugs = [device isEqualToString:@"mouse"]
                ? [Config mouseGestureSlugs] : [Config trackpadGestureSlugs];
            NSArray *engineNames = [slugs objectForKey:key];
            if (engineNames == nil) {
                // A reordered gesture name canonicalizes here, so the
                // declaration key, engine names, and every downstream surface
                // carry only the canonical spelling.
                NSString *canonical = [Config canonicalSlug:key inSlugs:slugs];
                if (canonical != nil) {
                    key = canonical;
                    engineNames = [slugs objectForKey:key];
                }
            }
            if (engineNames == nil) {
                report(line, gestureNameProblem(key, device, slugs));
                continue;
            }
            if (expandedDefer != nil &&
                (![key hasSuffix:@"-tap"] || [key hasSuffix:@"-double-tap"])) {
                report(line, @"defer is available only for single-tap gestures");
                continue;
            }
            if (expandedHaptic != nil && [device isEqualToString:@"mouse"]) {
                report(line, @"haptic is available only for trackpad bindings");
                continue;
            }
            NSString *bindingProblemText = nil;
            NSDictionary *binding = expanded && expandedValue == nil
                ? @{ @"Gesture": @"", @"InheritAction": @YES,
                     @"SourceLine": @(lineNumber), @"SourceText": line }
                : ([value hasPrefix:@"["]
                    ? parseSequence(value, &bindingProblemText) : parseBinding(value));
            if (binding == nil) {
                report(line, bindingProblemText ?: bindingProblem(value));
                continue;
            }

            NSMutableDictionary *scopes = [device isEqualToString:@"mouse"]
                ? mouseScopes : trackpadScopes;
            NSString *scopeName = application ?: @"All Applications";
            NSMutableArray *target = [scopes objectForKey:scopeName];
            NSString *declarationKey = [NSString stringWithFormat:@"%@|%@|%@",
                                         device, scopeName, key];
            if ([[binding objectForKey:@"InheritAction"] boolValue] ||
                [[binding objectForKey:@"Enable"] boolValue])
                [activeBindingKeys addObject:declarationKey];
            else
                [activeBindingKeys removeObject:declarationKey];
            for (NSString *name in engineNames) {
                NSMutableDictionary *g = [[binding mutableCopy] autorelease];
                [g setObject:name forKey:@"Gesture"];
                [g setObject:@(lineNumber) forKey:@"SourceLine"];
                [g setObject:line forKey:@"SourceText"];
                if ([sourceComment length] > 0)
                    [g setObject:sourceComment forKey:@"SourceComment"];
                if ([[binding objectForKey:@"InheritAction"] boolValue])
                    [g setObject:declarationKey forKey:@"SourceBindingKey"];
                if (expandedDefer != nil)
                    [g setObject:expandedDefer forKey:@"Defer"];
                if (expandedHaptic != nil)
                    [g setObject:expandedHaptic forKey:@"HapticFeedback"];
                if (expandedSound != nil)
                    [g setObject:expandedSound forKey:@"ConfirmSound"];
                if (expandedSpeech != nil)
                    [g setObject:expandedSpeech forKey:@"ConfirmSpeech"];
                [target addObject:g];
            }
        } else if ([device isEqualToString:@"general"]) {
            if (![knownSettingNames() containsObject:key]) {
                report(line, [NSString stringWithFormat:@"no setting named \"%@\"", key]);
                continue;
            }
            if ([key isEqualToString:@"config-version"] && ![stripQuotes(value) isEqualToString:@"3"]) {
                report(line, [NSString stringWithFormat:
                    @"configuration format \"%@\" is not supported; this version reads format 3",
                    value]);
                unsupportedVersion = YES;
            }
            if ([@[@"enable-mouse", @"enable-trackpad", @"haptic-feedback", @"verbose-logging",
                   @"experimental-mouse-click-gestures"] containsObject:key] &&
                !parseBooleanValue(value, NULL)) {
                report(line, [NSString stringWithFormat:
                    @"%@ must be true, false, yes, no, on, off, 1, or 0", key]);
                continue;
            }
            if ([key isEqualToString:@"tap-speed"] && !parsePositiveNumber(value, NULL)) {
                report(line, @"tap-speed must be a positive number of seconds");
                continue;
            }
            if ([key isEqualToString:@"trackpad-edge-gesture-depth"]) {
                double depth = 0;
                if (!parsePositiveNumber(value, &depth) || depth >= 0.5) {
                    report(line, @"trackpad-edge-gesture-depth must be a fraction of the surface above 0 and below 0.5");
                    continue;
                }
            }
            if ([key isEqualToString:@"dominant-hand"] &&
                ![@[@"left", @"right"] containsObject:[[stripQuotes(value) lowercaseString]
                                                         stringByTrimmingCharactersInSet:
                                                             [NSCharacterSet whitespaceCharacterSet]]]) {
                report(line, @"dominant-hand must be left or right");
                continue;
            }
            if ([key isEqualToString:@"menu-bar-icon"]) {
                NSString *icon = [[stripQuotes(value) lowercaseString]
                    stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
                if ([icon length] == 0 ||
                    (![icon isEqualToString:@"trickpad"] && ![icon hasPrefix:@"sf:"]) ||
                    ([icon hasPrefix:@"sf:"] && [icon length] == 3)) {
                    report(line, @"menu-bar-icon must be trickpad or sf: followed by an SF Symbol name");
                    continue;
                }
            }
            [general setObject:value forKey:key];
        } else {
            report(line, [NSString stringWithFormat:@"no section or device named \"%@\"", device]);
        }
    }

    if (pendingBlock != nil) {
        lineNumber = pendingBlockLine;
        report(pendingBlock, @"expanded binding is missing a closing }");
    }

    // A newer or malformed format may reinterpret otherwise valid lines. Keep
    // the entire previous configuration instead of applying a partial guess.
    if (unsupportedVersion)
        return nil;

    NSString *(^str)(NSString *, NSString *) = ^(NSString *k, NSString *fallback) {
        NSString *v = [general objectForKey:k];
        return v ?: fallback;
    };

    BOOL leftHanded = [[stripQuotes(str(@"dominant-hand", @"right")) lowercaseString]
        isEqualToString:@"left"];

    NSArray *(^commands)(NSMutableDictionary *, NSMutableArray *) =
        ^NSArray *(NSMutableDictionary *scopes, NSMutableArray *order) {
            NSMutableArray *result = [NSMutableArray array];
            NSMutableSet *reportedMissingActions = [NSMutableSet set];
            NSMutableDictionary *globalByGesture = [NSMutableDictionary dictionary];
            for (NSDictionary *binding in [scopes objectForKey:@"All Applications"])
                [globalByGesture setObject:binding forKey:[binding objectForKey:@"Gesture"]];
            for (NSString *app in order) {
                NSArray *configured = [scopes objectForKey:app];
                NSMutableArray *resolved = [NSMutableArray array];
                for (NSDictionary *binding in configured) {
                    if (![[binding objectForKey:@"InheritAction"] boolValue]) {
                        [resolved addObject:binding];
                        continue;
                    }
                    NSDictionary *global = [globalByGesture objectForKey:[binding objectForKey:@"Gesture"]];
                    if (global == nil) {
                        NSString *sourceKey = [binding objectForKey:@"SourceBindingKey"];
                        [activeBindingKeys removeObject:sourceKey];
                        if (![reportedMissingActions containsObject:sourceKey]) {
                            [reportedMissingActions addObject:sourceKey];
                            NSString *device = scopes == mouseScopes ? @"Mouse" : @"Trackpad";
                            NSString *title = [binding objectForKey:@"SourceText"];
                            NSString *reason = @"app property overrides require a global action for the same gesture";
                            addDiagnostic(diagnostics, [NSString stringWithFormat:
                                @"line %@:  %@\n          app property overrides require a global action for the same gesture",
                                [binding objectForKey:@"SourceLine"], title],
                                device, title, reason);
                        }
                        continue;
                    }
                    NSMutableDictionary *merged = [[global mutableCopy] autorelease];
                    for (NSString *key in binding) {
                        if (![@[@"InheritAction", @"SourceLine", @"SourceText", @"SourceBindingKey"] containsObject:key])
                            [merged setObject:[binding objectForKey:key] forKey:key];
                    }
                    if ([binding objectForKey:@"SourceComment"] == nil)
                        [merged removeObjectForKey:@"SourceComment"];
                    [merged setObject:[binding objectForKey:@"SourceLine"] forKey:@"SourceLine"];
                    [merged setObject:[binding objectForKey:@"SourceText"] forKey:@"SourceText"];
                    [resolved addObject:merged];
                }
                [result addObject:@{@"Application": app,
                                    @"Path": @"",
                                    @"Gestures": resolved}];
            }
            return result;
        };

    NSArray *resolvedTrackpadCommands = commands(trackpadScopes, trackpadScopeOrder);
    NSArray *resolvedMouseCommands = commands(mouseScopes, mouseScopeOrder);

    // A declaration key is "device|scope|slug". Application scopes do not change
    // whether a motion collides with a built-in gesture, so every active binding
    // for a slug counts once.
    NSMutableSet *mouseSlugs = [NSMutableSet set];
    NSMutableSet *trackpadSlugs = [NSMutableSet set];
    for (NSString *declarationKey in activeBindingKeys) {
        NSArray *parts = [declarationKey componentsSeparatedByString:@"|"];
        if ([parts count] != 3)
            continue;
        [([parts[0] isEqualToString:@"mouse"] ? mouseSlugs : trackpadSlugs)
            addObject:parts[2]];
    }

    return @{
        @"enAll": @1,
        @"ClickSpeed": @([str(@"tap-speed", @"0.25") floatValue]),
        @"AreaClickDepth": @([str(@"trackpad-edge-gesture-depth", @"0.06") floatValue]),
        @"Sensitivity": @4.6666,
        @"ShowIcon": @1,
        @"BindingCount": @([activeBindingKeys count]),
        @"SystemGestureConflicts": MGSystemGestureConflictsForCurrentUser(mouseSlugs, trackpadSlugs),
        @"HapticFeedback": @(parseBoolean(str(@"haptic-feedback", @"true"), YES) ? 1 : 0),
        @"MenuBarIcon": stripQuotes(str(@"menu-bar-icon", @"trickpad")),
        @"LogLevel": @(parseBoolean(str(@"verbose-logging", @"false"), NO) ? 3 : 1),
        @"enTPAll": @(parseBoolean(str(@"enable-trackpad", @"true"), YES) ? 1 : 0),
        @"enMMAll": @(parseBoolean(str(@"enable-mouse", @"true"), YES) ? 1 : 0),
        @"Handed": @(leftHanded ? 1 : 0),
        @"MMHanded": @(leftHanded ? 1 : 0),
        @"enCharRegTP": @0,
        @"enCharRegMM": @0,
        @"charRegMouseButton": @0,
        @"charRegIndexRingDistance": @0.33,
        @"enOneDrawing": @0,
        @"enTwoDrawing": @1,
        @"TrackpadCommands": resolvedTrackpadCommands,
        @"MagicMouseCommands": resolvedMouseCommands,
        @"RecognitionCommands": @[@{@"Application": @"All Applications", @"Path": @"", @"Gestures": @[]}],
    };
}

@end
