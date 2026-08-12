// Keeps one copy of the app running when the updater and launchd both start
// one, and lets a development build take over from a running release copy.

#import "SingleInstance.h"
#import <AppKit/AppKit.h>
#import <sys/file.h>
#import <fcntl.h>
#import <errno.h>

// Held for the life of the process. A lock is what makes this reliable: asking
// macOS which applications are running depends on each copy having registered
// itself, and a copy that has started but not yet registered is invisible to
// the other. Two copies can pass that check at once. Only one can hold a lock.
//
// The descriptor is deliberately never closed. The kernel releases the lock
// when the process ends, however it ends, so a crash cannot leave it held.
static int instanceLockDescriptor = -1;

static NSString *instanceLockPath(void) {
    NSString *folder = [NSHomeDirectory() stringByAppendingPathComponent:@".config/trickpad"];
    [[NSFileManager defaultManager] createDirectoryAtPath:folder
                             withIntermediateDirectories:YES
                                              attributes:nil
                                                   error:NULL];
    // Outside the bundle, which is replaced wholesale during an update.
    return [folder stringByAppendingPathComponent:@".instance.lock"];
}

// A development build carries the release identifier with a ".dev" suffix and
// installs beside the released copy. Both read one configuration folder, so
// the lock stays shared and keyed on that folder: two copies running at once
// would dispatch every gesture twice, whichever builds they are.
static BOOL isDevelopmentBundle(void) {
    return [[[NSBundle mainBundle] bundleIdentifier] hasSuffix:@".dev"];
}

// The development build is the copy someone just launched deliberately, and
// this app has no window in which to explain standing down, so it takes the
// lock instead: ask every other running copy to quit, then wait for the lock
// the kernel releases when the holder exits. The released copy never does
// this in reverse. The terminate request is repeated because a holder that
// started moments ago may not yet be registered with the workspace.
static BOOL seizeInstanceLock(void) {
    NSString *devID = [[NSBundle mainBundle] bundleIdentifier];
    NSString *releaseID = [devID substringToIndex:devID.length - [@".dev" length]];
    for (int attempt = 0; attempt < 5; attempt++) {
        for (NSString *bundleID in @[releaseID, devID]) {
            for (NSRunningApplication *app in [NSRunningApplication runningApplicationsWithBundleIdentifier:bundleID]) {
                if (app.processIdentifier == getpid())
                    continue;
                NSLog(@"Development build asking pid %d (%@) to quit", app.processIdentifier, bundleID);
                [app terminate];
            }
        }
        for (int i = 0; i < 10; i++) {
            usleep(100000);
            if (flock(instanceLockDescriptor, LOCK_EX | LOCK_NB) == 0) {
                NSLog(@"Instance lock seized by pid %d", getpid());
                return YES;
            }
        }
    }
    NSLog(@"Development build could not take the instance lock; standing down");
    return NO;
}

MGInstanceLockOutcome MGTakeInstanceLockAtPath(const char *path, int *descriptor) {
    *descriptor = -1;

    int fd = open(path, O_CREAT | O_RDWR, 0600);
    if (fd < 0)
        return MGInstanceLockCouldNotOpen;

    if (flock(fd, LOCK_EX | LOCK_NB) == 0) {
        *descriptor = fd;
        return MGInstanceLockAcquired;
    }

    if (errno == EWOULDBLOCK) {
        *descriptor = fd;
        return MGInstanceLockHeldByAnother;
    }

    int failure = errno;
    close(fd);
    errno = failure;
    return MGInstanceLockFailed;
}

BOOL MGAnotherInstanceOwnsThisBundle(void) {
    const char *path = [instanceLockPath() fileSystemRepresentation];

    switch (MGTakeInstanceLockAtPath(path, &instanceLockDescriptor)) {
        case MGInstanceLockAcquired:
            NSLog(@"Instance lock acquired by pid %d", getpid());
            return NO;

        case MGInstanceLockHeldByAnother:
            if (isDevelopmentBundle() && seizeInstanceLock())
                return NO;
            NSLog(@"Standing down, another instance holds the lock; pid %d", getpid());
            return YES;

        case MGInstanceLockCouldNotOpen:
            // Without a lock the app still runs. A duplicate is a worse outcome
            // than a missing guard, but refusing to start at all is worse than both.
            NSLog(@"Could not open the instance lock at %s: %s", path, strerror(errno));
            return NO;

        case MGInstanceLockFailed:
            NSLog(@"Instance lock failed at %s: %s", path, strerror(errno));
            return NO;
    }
}
