// Decides which copy of the app survives when two start at once.

#import <Foundation/Foundation.h>
#import <unistd.h>

// What asking for the lock at one path produced.
typedef enum {
    MGInstanceLockAcquired,
    MGInstanceLockHeldByAnother,
    MGInstanceLockCouldNotOpen,
    MGInstanceLockFailed,
} MGInstanceLockOutcome;

// Opens path and asks for an exclusive lock on it without waiting. The
// descriptor is stored in *descriptor whenever the file opened, and is -1
// otherwise; closing it releases the lock, so an acquired one stays open for as
// long as the caller wants to hold it. errno describes either failure.
MGInstanceLockOutcome MGTakeInstanceLockAtPath(const char *path, int *descriptor);

// The launchd job that starts the released copy at login, and its plist.
extern NSString *const MGLoginAgentLabel;
NSString *MGLoginAgentPlistPath(void);

// Trickpad Dev's bundle identifier is the release identifier plus ".dev". These
// name a bundle's channel and the identifier of the other channel, or nil for
// an empty identifier.
BOOL MGIsDevelopmentBundleIdentifier(NSString *bundleID);
NSString *MGOtherChannelBundleIdentifier(NSString *bundleID);
BOOL MGIsDevelopmentBundle(void);

// Starts the released copy again after Trickpad Dev quits: its login agent when
// one is installed, otherwise the installed app. Does nothing outside Dev.
void MGHandBackToReleaseChannel(void);

// Whether this process should stand down because another copy already holds the
// lock. Takes the lock for the life of the process when it is free.
BOOL MGAnotherInstanceOwnsThisBundle(void);
