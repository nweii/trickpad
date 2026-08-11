// Drives Sparkle for an update the user asked for, and never for one they did not.

#import "UpdaterController.h"

#if TRICKPAD_SPARKLE
#import <Sparkle/Sparkle.h>

static SPUStandardUpdaterController *updaterController = nil;

// Created on first use rather than at launch. The controller reads its
// configuration and touches user defaults when it starts, and an app that has
// not been asked to do anything about updates should not be doing that work.
static SPUStandardUpdaterController *sharedUpdaterController(void) {
    if (updaterController == nil) {
        updaterController =
            [[SPUStandardUpdaterController alloc] initWithStartingUpdater:YES
                                                          updaterDelegate:nil
                                                       userDriverDelegate:nil];
        // Downloading an update without being asked can install it on the next
        // launch, which on an unnotarized build means a Gatekeeper warning that
        // follows no action the user took. Checking is offered; downloading is
        // not, and this line is the constraint rather than a default.
        [[updaterController updater] setAutomaticallyDownloadsUpdates:NO];
    }
    return updaterController;
}

BOOL MGUpdaterIsAvailable(void) {
    return YES;
}

void MGUpdaterCheckForUpdates(void) {
    // The app has no dock icon, so its windows do not come forward on their
    // own. Sparkle's dialogs would otherwise open behind whatever the user is
    // looking at, from an app they cannot click to focus.
    [NSApp activateIgnoringOtherApps:YES];
    [sharedUpdaterController() checkForUpdates:nil];
}

BOOL MGUpdaterChecksAutomatically(void) {
    return [[sharedUpdaterController() updater] automaticallyChecksForUpdates];
}

void MGUpdaterSetChecksAutomatically(BOOL checksAutomatically) {
    [[sharedUpdaterController() updater] setAutomaticallyChecksForUpdates:checksAutomatically];
}

#else

// A build with no signing key carries no updater. These stand in so the menu
// code compiles unchanged and simply has nothing to show.
BOOL MGUpdaterIsAvailable(void) { return NO; }
void MGUpdaterCheckForUpdates(void) {}
BOOL MGUpdaterChecksAutomatically(void) { return NO; }
void MGUpdaterSetChecksAutomatically(BOOL checksAutomatically) { (void)checksAutomatically; }

#endif
