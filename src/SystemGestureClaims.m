// Maps macOS multi-touch preference keys to the gesture slugs whose trigger they
// overlap, and phrases the overlap for a reader deciding whether to rebind.

#import "SystemGestureClaims.h"

// One built-in gesture, and the configuration slugs whose trigger it shares.
//
// `domains` are the preference domains that answer for `key`, in order. macOS
// assigns touch gestures in more than one domain, and the Trackpad pane is not
// the only place a trackpad gesture is turned on.
// `disqualifier` is a second key that, when non-zero, means the setting is on
// but assigned to a different motion, so the entry does not apply.
// `prerequisite` is a second key that must itself be non-zero before the setting
// can answer the motion at all. A setting can be enabled and still be out of
// reach, because the motion that would trigger it is switched off elsewhere.
// A claim needs proof. The key and any prerequisite must read non-zero before
// the entry warns, and a disqualifier removes the claim only when it too reads
// non-zero. A preference macOS has never written proves nothing, so it neither
// establishes a claim nor takes one away.
// `setting`, `motion`, and `location` quote the macOS interface, so a reader
// comparing a warning against System Settings sees the same words in both. A
// NULL `setting` means the label is unconfirmed and the motion stands alone.
// `startsWithBoundTap` marks a built-in double tap, whose opening tap is the
// single tap a binding uses. That is the overlap a reader most easily misses.
//
// scripts/check.sh holds this table and scripts/system-gestures.sh to the same
// device, domain, key, and slug rows.
typedef struct {
    const char *domains;
    const char *key;
    const char *disqualifier;
    const char *prerequisite;
    const char *slugs;
    const char *setting;
    const char *motion;
    const char *location;
    BOOL startsWithBoundTap;
    BOOL trackpad;
} MGSystemGestureEntry;

#define MOUSE_DOMAINS "com.apple.AppleMultitouchMouse"
#define TRACKPAD_DOMAINS "com.apple.driver.AppleBluetoothMultitouch.trackpad,com.apple.AppleMultitouchTrackpad"

// A setting is named only where its pane holds exactly one gesture using that
// motion. Where two settings can share a motion, a NULL name keeps the warning
// to the motion rather than guessing which one the reader will find.
//
// Pinch and spread appear on the trackpad alone. A Magic Mouse has no room for
// the thumb those gestures need.
static const MGSystemGestureEntry kEntries[] = {
    {MOUSE_DOMAINS, "MouseOneFingerDoubleTapGesture", NULL, NULL, "one-finger-tap",
     "Smart zoom", "Double-tap with One Finger", "Mouse > Point & Click", YES, NO},
    {MOUSE_DOMAINS, "MouseTwoFingerDoubleTapGesture", NULL, NULL, "two-finger-tap",
     "Mission Control", "Double-tap with Two Fingers", "Mouse > More Gestures", YES, NO},
    {MOUSE_DOMAINS, "MouseTwoFingerHorizSwipeGesture", NULL, NULL,
     "two-finger-swipe-left,two-finger-swipe-right",
     "Swipe between full-screen applications", "Swipe Left or Right with Two Fingers",
     "Mouse > More Gestures", NO, NO},
    {MOUSE_DOMAINS, "MouseHorizontalScroll", NULL, NULL,
     "one-finger-swipe-left,one-finger-swipe-right",
     "Swipe between pages", "Scroll Left or Right with One Finger",
     "Mouse > More Gestures", NO, NO},

    {TRACKPAD_DOMAINS, "TrackpadTwoFingerDoubleTapGesture", NULL, NULL, "two-finger-tap",
     "Smart zoom", "Double-tap with two fingers", "Trackpad > Scroll & Zoom", YES, YES},
    // Secondary click stays on while moving to a corner, so the setting being
    // enabled does not by itself mean it still uses a two-finger tap. It also
    // answers a two-finger press whether or not tap to click is on, and a press
    // is not the motion a tap binding uses, so `Clicking` gates the overlap.
    {TRACKPAD_DOMAINS, "TrackpadRightClick", "TrackpadCornerSecondaryClick", "Clicking",
     "two-finger-tap",
     "Secondary click", "Click or Tap with Two Fingers", "Trackpad > Point & Click", NO, YES},
    {TRACKPAD_DOMAINS, "TrackpadThreeFingerTapGesture", NULL, NULL, "three-finger-tap",
     "Look up & data detectors", "Tap with Three Fingers", "Trackpad > Point & Click", NO, YES},
    {TRACKPAD_DOMAINS, "TrackpadThreeFingerHorizSwipeGesture", NULL, NULL,
     "three-finger-swipe-left,three-finger-swipe-right",
     "Swipe between full-screen applications", "Swipe Left or Right with Three Fingers",
     "Trackpad > More Gestures", NO, YES},
    {TRACKPAD_DOMAINS, "TrackpadFourFingerHorizSwipeGesture", NULL, NULL,
     "four-finger-swipe-left,four-finger-swipe-right",
     "Swipe between full-screen applications", "Swipe Left or Right with Four Fingers",
     "Trackpad > More Gestures", NO, YES},
    // One key answers for both directions, and each names its own setting.
    {TRACKPAD_DOMAINS, "TrackpadThreeFingerVertSwipeGesture", NULL, NULL, "three-finger-swipe-up",
     "Mission Control", "Swipe Up with Three Fingers", "Trackpad > More Gestures", NO, YES},
    {TRACKPAD_DOMAINS, "TrackpadThreeFingerVertSwipeGesture", NULL, NULL, "three-finger-swipe-down",
     "App Exposé", "Swipe Down with Three Fingers", "Trackpad > More Gestures", NO, YES},
    {TRACKPAD_DOMAINS, "TrackpadFourFingerVertSwipeGesture", NULL, NULL, "four-finger-swipe-up",
     "Mission Control", "Swipe Up with Four Fingers", "Trackpad > More Gestures", NO, YES},
    {TRACKPAD_DOMAINS, "TrackpadFourFingerVertSwipeGesture", NULL, NULL, "four-finger-swipe-down",
     "App Exposé", "Swipe Down with Four Fingers", "Trackpad > More Gestures", NO, YES},
    {TRACKPAD_DOMAINS, "TrackpadThreeFingerDrag", NULL, NULL,
     "three-finger-swipe-left,three-finger-swipe-right,three-finger-swipe-up,three-finger-swipe-down",
     "Three Finger Drag", "drag with three fingers",
     "Accessibility > Pointer Control > Trackpad Options", NO, YES},
    {TRACKPAD_DOMAINS, "TrackpadFourFingerPinchGesture", NULL, NULL,
     "index-to-pinky,pinky-to-index",
     NULL, "a pinch with thumb and three fingers", "Trackpad > More Gestures", NO, YES},
    {TRACKPAD_DOMAINS, "TrackpadFiveFingerPinchGesture", NULL, NULL,
     "index-to-pinky,pinky-to-index",
     "Show Desktop", "Spread with thumb and three fingers", "Trackpad > More Gestures", NO, YES},
    // Display magnification, which enlarges the whole screen rather than
    // content inside an app the way Smart zoom does.
    {"com.apple.universalaccess", "closeViewTrackpadGestureZoomEnabled", NULL, NULL,
     "three-finger-tap", "Use trackpad gesture to zoom",
     "Double-tap three fingers to toggle zoom", "Accessibility > Zoom", YES, YES},
};

static const size_t kEntryCount = sizeof(kEntries) / sizeof(kEntries[0]);

MGSystemGestureClaim MGSystemGestureClaimForValue(NSNumber *value) {
    if (value == nil)
        return MGSystemGestureClaimUnknown;
    return [value integerValue] == 0 ? MGSystemGestureClaimFree : MGSystemGestureClaimTaken;
}

// A directional swipe slug's bare family slug, or nil for any other shape.
// "four-finger-swipe-down" -> "four-finger-swipe".
static NSString *MGSwipeFamilySlug(NSString *slug) {
    for (NSString *direction in @[@"-left", @"-right", @"-up", @"-down"]) {
        if ([slug hasSuffix:direction]) {
            NSString *family = [slug substringToIndex:
                [slug length] - [direction length]];
            return [family hasSuffix:@"-swipe"] ? family : nil;
        }
    }
    return nil;
}

NSArray *MGSystemGestureConflicts(NSSet *configuredMouseSlugs,
                                  NSSet *configuredTrackpadSlugs,
                                  NSNumber *(^valueForKey)(NSString *domains, NSString *key)) {
    // One binding can collide with several built-in gestures, so findings group
    // under the binding they concern. Reporting each collision as its own
    // paragraph produced near-identical blocks that read as a rendering fault.
    NSMutableArray *order = [NSMutableArray array];
    NSMutableDictionary *bulletsByBinding = [NSMutableDictionary dictionary];
    for (size_t i = 0; i < kEntryCount; i++) {
        const MGSystemGestureEntry entry = kEntries[i];
        NSString *domains = [NSString stringWithUTF8String:entry.domains];
        if (MGSystemGestureClaimForValue(valueForKey(domains,
                [NSString stringWithUTF8String:entry.key])) != MGSystemGestureClaimTaken)
            continue;
        if (entry.disqualifier != NULL &&
            MGSystemGestureClaimForValue(valueForKey(domains,
                [NSString stringWithUTF8String:entry.disqualifier])) ==
                MGSystemGestureClaimTaken)
            continue;
        // A prerequisite that is off, or that macOS has never written, leaves
        // the overlap unproven. Staying quiet costs a reader a conflict they can
        // still discover by trying the gesture; warning wrongly costs them a
        // gesture they could have used.
        if (entry.prerequisite != NULL &&
            MGSystemGestureClaimForValue(valueForKey(domains,
                [NSString stringWithUTF8String:entry.prerequisite])) !=
                MGSystemGestureClaimTaken)
            continue;
        NSSet *configured = entry.trackpad ? configuredTrackpadSlugs : configuredMouseSlugs;
        NSString *device = entry.trackpad ? @"Trackpad" : @"Mouse";
        NSString *motion = [NSString stringWithUTF8String:entry.motion];
        // The macOS gesture leads, then its motion in Apple's own words. Naming
        // the owner of each part keeps the reader from having to work out which
        // gesture is theirs. A shared motion needs no explaining beyond the
        // heading; only a double tap containing the bound tap does.
        NSString *shared = entry.startsWithBoundTap
            ? [motion stringByAppendingString:@", which opens with your single tap"]
            : motion;
        // %s decodes bytes in the legacy system encoding, which mangles any
        // accented setting name, so the C strings convert through UTF-8.
        NSString *bullet = entry.setting != NULL
            ? [NSString stringWithFormat:@"%@\n    macOS: %@",
               [NSString stringWithUTF8String:entry.setting], shared]
            : [NSString stringWithFormat:@"macOS: %@", shared];
        NSMutableSet *seenSlugs = [NSMutableSet set];
        for (NSString *slug in [[NSString stringWithUTF8String:entry.slugs]
                                componentsSeparatedByString:@","]) {
            // A bare swipe family binds every direction of its family, so a
            // claim on one direction concerns it too. Deriving the family name
            // here keeps new directional slugs covered without a table edit.
            NSString *matched = nil;
            if ([configured containsObject:slug]) {
                matched = slug;
            } else {
                NSString *family = MGSwipeFamilySlug(slug);
                if (family != nil && [configured containsObject:family])
                    matched = family;
            }
            if (matched == nil || [seenSlugs containsObject:matched])
                continue;
            [seenSlugs addObject:matched];
            NSString *binding = [NSString stringWithFormat:@"%@ %@", device, matched];
            if ([bulletsByBinding objectForKey:binding] == nil) {
                [order addObject:binding];
                [bulletsByBinding setObject:[NSMutableArray array] forKey:binding];
            }
            [[bulletsByBinding objectForKey:binding] addObject:
                [NSString stringWithFormat:@"  • %@\n    Change it in System Settings > %@",
                 bullet, [NSString stringWithUTF8String:entry.location]]];
        }
    }

    NSMutableArray *warnings = [NSMutableArray array];
    for (NSString *binding in order) {
        [warnings addObject:[NSString stringWithFormat:
            @"Your %@ binding shares its trigger with:\n\n%@", binding,
            [[bulletsByBinding objectForKey:binding] componentsJoinedByString:@"\n\n"]]];
    }
    return warnings;
}

NSArray *MGSystemGestureClaimTableLines(void) {
    NSMutableArray *lines = [NSMutableArray array];
    for (size_t i = 0; i < kEntryCount; i++) {
        const MGSystemGestureEntry entry = kEntries[i];
        // The gates decide whether a claim applies, so they belong in the
        // comparison. Without them one copy can gate an entry and the other not,
        // and the two would still read as identical.
        NSString *disqualifier = entry.disqualifier != NULL
            ? [NSString stringWithUTF8String:entry.disqualifier] : @"-";
        NSString *prerequisite = entry.prerequisite != NULL
            ? [NSString stringWithUTF8String:entry.prerequisite] : @"-";
        for (NSString *slug in [[NSString stringWithUTF8String:entry.slugs]
                                componentsSeparatedByString:@","]) {
            [lines addObject:[NSString stringWithFormat:@"%@ %s %s %@ %@ %@",
                              entry.trackpad ? @"trackpad" : @"mouse",
                              entry.domains, entry.key, slug,
                              prerequisite, disqualifier]];
        }
    }
    return [lines sortedArrayUsingSelector:@selector(compare:)];
}

// Raise this after reading the panes named in kEntries on a newer release and
// correcting anything Apple moved. Preference keys outlive interface labels, so
// a stale value here costs a reader an extra look, not a wrong warning.
static const NSInteger kSettingsVerifiedMacOSMajor = 26;

NSString *MGSystemGestureSettingsProvenance(void) {
    NSInteger running = [[NSProcessInfo processInfo] operatingSystemVersion].majorVersion;
    NSString *checked = [NSString stringWithFormat:
        @"Setting names and locations were last checked on macOS %ld.",
        (long)kSettingsVerifiedMacOSMajor];
    if (running <= kSettingsVerifiedMacOSMajor)
        return checked;
    return [checked stringByAppendingFormat:
        @" This Mac runs macOS %ld, so a name may have moved.", (long)running];
}

NSArray *MGSystemGestureConflictsForCurrentUser(NSSet *configuredMouseSlugs,
                                                NSSet *configuredTrackpadSlugs) {
    return MGSystemGestureConflicts(configuredMouseSlugs, configuredTrackpadSlugs,
        ^NSNumber *(NSString *domains, NSString *key) {
            for (NSString *domain in [domains componentsSeparatedByString:@","]) {
                id value = [(id)CFPreferencesCopyAppValue((CFStringRef)key,
                                                          (CFStringRef)domain) autorelease];
                if ([value isKindOfClass:[NSNumber class]])
                    return value;
            }
            return nil;
        });
}
