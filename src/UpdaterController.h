// Owns the opt-in update check, keeping Sparkle's lifetime and policy out of the menu code.

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>

// Whether this build carries an updater at all. A build with no signing key is
// built without Sparkle, so the menu must not offer what cannot run.
BOOL MGUpdaterIsAvailable(void);

// Starts a check the user asked for. No-op when the updater is absent.
void MGUpdaterCheckForUpdates(void);

// Whether the app looks for updates on its own. Sparkle owns this setting in
// the host bundle's user defaults, so it is read back rather than mirrored.
BOOL MGUpdaterChecksAutomatically(void);
void MGUpdaterSetChecksAutomatically(BOOL checksAutomatically);
