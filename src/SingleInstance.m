// Keeps one copy of the app running when the updater and launchd both start one.

#import "SingleInstance.h"
#import <AppKit/AppKit.h>
#import <sys/file.h>
#import <fcntl.h>
#import <errno.h>

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

BOOL MGAnotherInstanceOwnsThisBundle(void) {
    const char *path = [instanceLockPath() fileSystemRepresentation];
    instanceLockDescriptor = open(path, O_CREAT | O_RDWR, 0600);
    if (instanceLockDescriptor < 0) {
        // Without a lock the app still runs. A duplicate is a worse outcome
        // than a missing guard, but refusing to start at all is worse than both.
        NSLog(@"Could not open the instance lock at %s: %s", path, strerror(errno));
        return NO;
    }

    if (flock(instanceLockDescriptor, LOCK_EX | LOCK_NB) == 0) {
        NSLog(@"Instance lock acquired by pid %d", getpid());
        return NO;
    }

    if (errno == EWOULDBLOCK) {
        NSLog(@"Standing down, another instance holds the lock; pid %d", getpid());
        return YES;
    }

    NSLog(@"Instance lock failed at %s: %s", path, strerror(errno));
    close(instanceLockDescriptor);
    instanceLockDescriptor = -1;
    return NO;
}
