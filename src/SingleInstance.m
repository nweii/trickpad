// Keeps one copy of the app running when the updater and launchd both start
// one, and lets whichever channel was opened last take over from the other.

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

NSString *const MGLoginAgentLabel = @"fyi.thirdwind.trickpad.agent";

NSString *MGLoginAgentPlistPath(void) {
    NSString *name = [MGLoginAgentLabel stringByAppendingPathExtension:@"plist"];
    return [[NSHomeDirectory() stringByAppendingPathComponent:@"Library/LaunchAgents"]
        stringByAppendingPathComponent:name];
}

// Trickpad Dev carries the release identifier with a ".dev" suffix and installs
// beside the released copy. Both read one configuration folder, so the lock
// stays shared and keyed on that folder: two copies running at once would
// dispatch every gesture twice, whichever channels they come from.
static NSString *const kDevelopmentSuffix = @".dev";

BOOL MGIsDevelopmentBundleIdentifier(NSString *bundleID) {
    return [bundleID hasSuffix:kDevelopmentSuffix] && [bundleID length] > [kDevelopmentSuffix length];
}

NSString *MGOtherChannelBundleIdentifier(NSString *bundleID) {
    if ([bundleID length] == 0)
        return nil;
    if (MGIsDevelopmentBundleIdentifier(bundleID))
        return [bundleID substringToIndex:[bundleID length] - [kDevelopmentSuffix length]];
    return [bundleID stringByAppendingString:kDevelopmentSuffix];
}

BOOL MGIsDevelopmentBundle(void) {
    return MGIsDevelopmentBundleIdentifier([[NSBundle mainBundle] bundleIdentifier]);
}

static BOOL runLaunchctl(NSArray *arguments) {
    NSTask *task = [[[NSTask alloc] init] autorelease];
    [task setLaunchPath:@"/bin/launchctl"];
    [task setArguments:arguments];
    [task setStandardOutput:[NSFileHandle fileHandleWithNullDevice]];
    [task setStandardError:[NSFileHandle fileHandleWithNullDevice]];
    @try {
        [task launch];
        [task waitUntilExit];
    } @catch (NSException *exception) {
        return NO;
    }
    return [task terminationStatus] == 0;
}

static NSString *loginAgentTarget(void) {
    return [NSString stringWithFormat:@"gui/%d/%@", (int)getuid(), MGLoginAgentLabel];
}

static NSArray<NSRunningApplication *> *otherCopies(NSString *bundleID) {
    NSMutableArray *copies = [NSMutableArray array];
    for (NSRunningApplication *app in [NSRunningApplication runningApplicationsWithBundleIdentifier:bundleID]) {
        if (app.processIdentifier != getpid())
            [copies addObject:app];
    }
    return copies;
}

// Opening one channel while the other runs is a deliberate switch, and this app
// has no window in which to explain standing down, so the copy just opened
// takes the lock: ask the other channel to quit, then wait for the lock the
// kernel releases when it exits. A copy of the same channel never takes over,
// because the updater and the login agent can each start one moments after the
// other, and taking over there would leave the two trading the lock forever.
//
// Trickpad Dev also stops the release channel's login agent. Its job would
// otherwise restart the released copy as soon as it exits, and that copy would
// take the lock straight back. Quitting Dev starts the job again; see
// MGHandBackToReleaseChannel.
static BOOL seizeInstanceLock(NSString *otherID) {
    if (MGIsDevelopmentBundle())
        runLaunchctl(@[@"bootout", loginAgentTarget()]);

    // The terminate request is repeated because a holder that started moments
    // ago may not yet be registered with the workspace.
    for (int attempt = 0; attempt < 5; attempt++) {
        for (NSRunningApplication *app in otherCopies(otherID)) {
            NSLog(@"Taking over from pid %d (%@)", app.processIdentifier, otherID);
            [app terminate];
        }
        for (int i = 0; i < 10; i++) {
            usleep(100000);
            if (flock(instanceLockDescriptor, LOCK_EX | LOCK_NB) == 0) {
                NSLog(@"Instance lock seized by pid %d", getpid());
                return YES;
            }
        }
    }
    NSLog(@"Could not take the instance lock from %@; standing down", otherID);
    return NO;
}

void MGHandBackToReleaseChannel(void) {
    NSString *releaseID = MGOtherChannelBundleIdentifier([[NSBundle mainBundle] bundleIdentifier]);
    if (!MGIsDevelopmentBundle() || releaseID == nil)
        return;

    // The login agent supervises the released copy, so starting the job brings
    // it back with its restart-on-exit behavior intact. Bootstrapping fails when
    // the job is already loaded, which kickstart then covers.
    NSString *plist = MGLoginAgentPlistPath();
    if ([[NSFileManager defaultManager] fileExistsAtPath:plist]) {
        NSString *domain = [NSString stringWithFormat:@"gui/%d", (int)getuid()];
        if (runLaunchctl(@[@"bootstrap", domain, plist]) ||
            runLaunchctl(@[@"kickstart", loginAgentTarget()]))
            return;
    }

    // Without a login agent the released copy was opened by hand, so it is
    // opened again the same way, if it is installed at all.
    NSURL *releaseURL = [[NSWorkspace sharedWorkspace] URLForApplicationWithBundleIdentifier:releaseID];
    if (releaseURL == nil)
        return;
    NSWorkspaceOpenConfiguration *configuration = [NSWorkspaceOpenConfiguration configuration];
    [configuration setActivates:NO];
    [[NSWorkspace sharedWorkspace] openApplicationAtURL:releaseURL
                                          configuration:configuration
                                      completionHandler:nil];
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

        case MGInstanceLockHeldByAnother: {
            NSString *otherID = MGOtherChannelBundleIdentifier([[NSBundle mainBundle] bundleIdentifier]);
            if (otherID != nil && [otherCopies(otherID) count] > 0 && seizeInstanceLock(otherID))
                return NO;
            NSLog(@"Standing down, another instance holds the lock; pid %d", getpid());
            return YES;
        }

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
