// Keeps one copy of the app running when the updater and launchd both start one.

#import "SingleInstance.h"
#import <AppKit/AppKit.h>

// The lowest process identifier wins. Both copies see the same set and compare
// the same way, so the rule picks one survivor without either needing to talk
// to the other. Deciding by launch time would not do that: two copies started
// in the same instant can read identical times and both stand down.
BOOL MGShouldYieldToExistingInstance(pid_t mine, const pid_t *others, int count) {
    for (int i = 0; i < count; i++) {
        if (others[i] == mine)
            continue;
        if (others[i] < mine)
            return YES;
    }
    return NO;
}

BOOL MGAnotherInstanceOwnsThisBundle(void) {
    NSRunningApplication *me = [NSRunningApplication currentApplication];
    NSString *bundleIdentifier = [me bundleIdentifier];
    if (bundleIdentifier == nil)
        return NO;

    NSArray *running =
        [NSRunningApplication runningApplicationsWithBundleIdentifier:bundleIdentifier];
    // A copy on its way out is not an owner. During an update the outgoing copy
    // can still be listed while it finishes quitting, and yielding to it would
    // leave nothing running.
    pid_t others[64];
    int count = 0;
    for (NSRunningApplication *application in running) {
        if (count >= 64)
            break;
        if ([application isTerminated])
            continue;
        others[count++] = [application processIdentifier];
    }
    return MGShouldYieldToExistingInstance([me processIdentifier], others, count);
}
