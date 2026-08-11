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

// One setting behind two surfaces. Sparkle asks about automatic updates once,
// in the permission request on second launch, and this is the same state. That
// request never appears again, so without a menu row the answer given there
// could never be revisited.
//
// Downloading implies checking, since an update cannot be fetched without
// noticing it exists. Both move together rather than exposing an arrangement
// where the app checks but never acts on the answer.
BOOL MGUpdaterUpdatesAutomatically(void) {
    SPUUpdater *updater = [sharedUpdaterController() updater];
    return [updater automaticallyChecksForUpdates] && [updater automaticallyDownloadsUpdates];
}

void MGUpdaterSetUpdatesAutomatically(BOOL updatesAutomatically) {
    SPUUpdater *updater = [sharedUpdaterController() updater];
    [updater setAutomaticallyChecksForUpdates:updatesAutomatically];
    [updater setAutomaticallyDownloadsUpdates:updatesAutomatically];
}

#else

// A build with no signing key carries no updater. These stand in so the menu
// code compiles unchanged and simply has nothing to show.
BOOL MGUpdaterIsAvailable(void) { return NO; }
void MGUpdaterCheckForUpdates(void) {}
BOOL MGUpdaterUpdatesAutomatically(void) { return NO; }
void MGUpdaterSetUpdatesAutomatically(BOOL updatesAutomatically) { (void)updatesAutomatically; }

#endif
