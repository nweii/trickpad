// Asserts that claimed macOS motions warn only about the slugs a configuration
// actually binds, on the device that owns them.

#import <Foundation/Foundation.h>
#import "SystemGestureClaims.h"

static void require(BOOL condition, NSString *message) {
    if (!condition) { fprintf(stderr, "FAIL  %s\n", [message UTF8String]); exit(1); }
}

static BOOL warnsAbout(NSArray *warnings, NSString *needle) {
    for (NSString *warning in warnings) {
        if ([warning rangeOfString:needle].location != NSNotFound)
            return YES;
    }
    return NO;
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc == 2 && strcmp(argv[1], "--table") == 0) {
            for (NSString *line in MGSystemGestureClaimTableLines())
                printf("%s\n", [line UTF8String]);
            return 0;
        }
        require(MGSystemGestureClaimForValue(nil) == MGSystemGestureClaimUnknown,
                @"an unwritten preference must stay unknown, not free");
        require(MGSystemGestureClaimForValue(@0) == MGSystemGestureClaimFree,
                @"zero must read as a free motion");
        require(MGSystemGestureClaimForValue(@3) == MGSystemGestureClaimTaken,
                @"a non-zero value must read as a claimed motion");

        NSSet *twoFingerTap = [NSSet setWithObject:@"two-finger-tap"];
        NSSet *none = [NSSet set];

        NSArray *taken = MGSystemGestureConflicts(twoFingerTap, none,
            ^NSNumber *(NSString *domains, NSString *key) {
                return [key isEqualToString:@"MouseTwoFingerDoubleTapGesture"] ? @3 : nil;
            });
        require([taken count] == 1, @"a claimed motion on a bound slug must warn once");
        require(warnsAbout(taken, @"Mouse two-finger-tap"),
                @"the warning must lead with the device and the slug");
        // A built-in double tap contains the bound single tap, and a reader who
        // misses that reads the warning as naming a gesture they never bound.
        require(warnsAbout(taken, @"opens with your single tap"),
                @"the warning must say a double tap contains the tap that is bound");
        require(warnsAbout(taken, @"System Settings"),
                @"the warning must say where the built-in gesture lives");
        require(warnsAbout(taken, @"Mission Control"),
                @"the warning must name the built-in gesture it found");

        NSArray *free = MGSystemGestureConflicts(twoFingerTap, none,
            ^NSNumber *(NSString *domains, NSString *key) {
                return [key isEqualToString:@"MouseTwoFingerDoubleTapGesture"] ? @0 : nil;
            });
        require([free count] == 0, @"a motion macOS has released must not warn");

        NSArray *unwritten = MGSystemGestureConflicts(twoFingerTap, none,
            ^NSNumber *(NSString *domains, NSString *key) { return nil; });
        require([unwritten count] == 0, @"an unwritten preference must not invent a warning");

        // A bare swipe family binds every direction, so a claim on one
        // direction concerns it even though the family slug itself never
        // appears in the claim table.
        NSSet *bareFourSwipe = [NSSet setWithObject:@"four-finger-swipe"];
        NSArray *family = MGSystemGestureConflicts(none, bareFourSwipe,
            ^NSNumber *(NSString *domains, NSString *key) {
                return [key isEqualToString:@"TrackpadFourFingerVertSwipeGesture"] ? @2 : nil;
            });
        require([family count] == 1,
                @"a claimed direction must warn a bare family binding, once");
        require(warnsAbout(family, @"Trackpad four-finger-swipe"),
                @"the family warning must name the slug that is actually bound");

        NSArray *unbound = MGSystemGestureConflicts(none, none,
            ^NSNumber *(NSString *domains, NSString *key) { return @3; });
        require([unbound count] == 0, @"a claimed motion nobody bound must not warn");

        // Secondary click is enabled on most Macs and answers a two-finger
        // press. Tap to click is what makes a two-finger tap reach it, so
        // warning without that key steers a reader off a free gesture.
        NSSet *trackpadTwoFingerTap = [NSSet setWithObject:@"two-finger-tap"];
        NSArray *tapToClickOff = MGSystemGestureConflicts(none, trackpadTwoFingerTap,
            ^NSNumber *(NSString *domains, NSString *key) {
                if ([key isEqualToString:@"TrackpadRightClick"]) return @1;
                if ([key isEqualToString:@"Clicking"]) return @0;
                return nil;
            });
        require(!warnsAbout(tapToClickOff, @"Secondary click"),
                @"secondary click must not warn while tap to click is off");

        NSArray *tapToClickOn = MGSystemGestureConflicts(none, trackpadTwoFingerTap,
            ^NSNumber *(NSString *domains, NSString *key) {
                if ([key isEqualToString:@"TrackpadRightClick"]) return @1;
                if ([key isEqualToString:@"Clicking"]) return @1;
                return nil;
            });
        require(warnsAbout(tapToClickOn, @"Secondary click"),
                @"secondary click must warn while tap to click is on");

        // A disqualifier takes a claim away only when macOS wrote it. Secondary
        // click moved to a corner is the case it describes, and a Mac that never
        // wrote that preference has not moved it.
        NSArray *cornerUnwritten = MGSystemGestureConflicts(none, trackpadTwoFingerTap,
            ^NSNumber *(NSString *domains, NSString *key) {
                return [key isEqualToString:@"TrackpadCornerSecondaryClick"] ? nil : @1;
            });
        require(warnsAbout(cornerUnwritten, @"Secondary click"),
                @"an unwritten disqualifier must not take a claim away");

        NSArray *cornerSet = MGSystemGestureConflicts(none, trackpadTwoFingerTap,
            ^NSNumber *(NSString *domains, NSString *key) { return @1; });
        require(!warnsAbout(cornerSet, @"Secondary click"),
                @"secondary click moved to a corner must not warn");

        // An absent prerequisite leaves the overlap unproven, and an unproven
        // overlap is not a finding.
        NSArray *tapToClickUnwritten = MGSystemGestureConflicts(none, trackpadTwoFingerTap,
            ^NSNumber *(NSString *domains, NSString *key) {
                return [key isEqualToString:@"TrackpadRightClick"] ? @1 : nil;
            });
        require(!warnsAbout(tapToClickUnwritten, @"Secondary click"),
                @"an unwritten prerequisite must not prove a claim");

        // The two devices keep separate vocabularies, so a trackpad claim must
        // not reach an identically named mouse binding.
        NSArray *crossed = MGSystemGestureConflicts(twoFingerTap, none,
            ^NSNumber *(NSString *domains, NSString *key) {
                return [key hasPrefix:@"Trackpad"] ? @1 : nil; });
        require([crossed count] == 0, @"a trackpad claim must not warn about a mouse binding");

        // macOS assigns trackpad gestures in more than one place, so one slug
        // can collide with two separate settings. Both belong under the one
        // binding they concern, because two near-identical paragraphs read as a
        // rendering fault rather than as two findings.
        NSSet *threeFingerTap = [NSSet setWithObject:@"three-finger-tap"];
        NSArray *twoPlaces = MGSystemGestureConflicts(none, threeFingerTap,
            ^NSNumber *(NSString *domains, NSString *key) { return @1; });
        require([twoPlaces count] == 1, @"one binding must produce one grouped finding");
        require(warnsAbout(twoPlaces, @"Trackpad > Point & Click") &&
                warnsAbout(twoPlaces, @"Accessibility > Zoom"),
                @"both settings that claim one binding must name where they live");
        require([[twoPlaces firstObject] componentsSeparatedByString:@"  • "].count == 3,
                @"each built-in gesture claiming the binding needs its own line");

        // Secondary click stays on while moving to a corner, so the setting
        // being enabled does not by itself mean it uses a two-finger tap.
        NSSet *twoFingerTrackpad = [NSSet setWithObject:@"two-finger-tap"];
        NSArray *corner = MGSystemGestureConflicts(none, twoFingerTrackpad,
            ^NSNumber *(NSString *domains, NSString *key) {
                if ([key isEqualToString:@"TrackpadRightClick"]) return @1;
                if ([key isEqualToString:@"TrackpadCornerSecondaryClick"]) return @1;
                return nil;
            });
        require(![corner count], @"secondary click moved to a corner must not warn");

        // Accessibility zoom lives outside the Trackpad domain entirely, so a
        // lookup that ignores the entry's own domain would miss it.
        NSArray *outsideDomain = MGSystemGestureConflicts(none, threeFingerTap,
            ^NSNumber *(NSString *domains, NSString *key) {
                return [domains isEqualToString:@"com.apple.universalaccess"] ? @1 : nil;
            });
        require([outsideDomain count] == 1,
                @"a claim outside the device preference domain was not read");

        require([MGSystemGestureSettingsProvenance() rangeOfString:@"macOS"].location
                != NSNotFound,
                @"the warnings must record which macOS release supplied the setting names");

        printf("system gesture claims: all checks passed\n");
    }
    return 0;
}
