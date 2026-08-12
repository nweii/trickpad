// Asserts that only one process at a time holds the instance lock, and that a
// holder that dies releases it.

#import <Foundation/Foundation.h>
#import <sys/wait.h>
#import <signal.h>
#import <unistd.h>
#import <errno.h>

#import "SingleInstance.h"

static int failures = 0;

static void require(BOOL condition, NSString *message) {
    if (!condition) {
        NSLog(@"%@", message);
        failures++;
    }
}

// Runs in a forked child. Asks for the lock, reports what it got down report,
// then blocks until the parent closes hold, so a child that acquired the lock
// keeps holding it while the next contender tries.
static void contendForLock(const char *path, int report, int hold) {
    int descriptor = -1;
    unsigned char outcome = (unsigned char)MGTakeInstanceLockAtPath(path, &descriptor);
    write(report, &outcome, 1);

    unsigned char release;
    read(hold, &release, 1);
    _exit(0);
}

// Forks a contender and waits for its answer. The child is still alive and
// still holding whatever it took when this returns; *release closes it down.
static MGInstanceLockOutcome startContender(const char *path, pid_t *child, int *release) {
    int report[2], hold[2];
    if (pipe(report) != 0 || pipe(hold) != 0) {
        NSLog(@"could not create the contender pipes: %s", strerror(errno));
        exit(1);
    }

    pid_t pid = fork();
    if (pid < 0) {
        NSLog(@"could not fork a contender: %s", strerror(errno));
        exit(1);
    }
    if (pid == 0) {
        close(report[0]);
        close(hold[1]);
        contendForLock(path, report[1], hold[0]);
    }

    close(report[1]);
    close(hold[0]);

    unsigned char outcome = 0;
    if (read(report[0], &outcome, 1) != 1) {
        NSLog(@"a contender reported nothing: %s", strerror(errno));
        exit(1);
    }
    close(report[0]);

    *child = pid;
    *release = hold[1];
    return (MGInstanceLockOutcome)outcome;
}

static void stopContender(pid_t child, int release) {
    close(release);
    waitpid(child, NULL, 0);
}

int main(void) {
    @autoreleasepool {
        char folder[] = "/tmp/trickpad-single-instance-XXXXXX";
        if (mkdtemp(folder) == NULL) {
            NSLog(@"could not create a temporary folder: %s", strerror(errno));
            return 1;
        }
        NSString *lock = [NSString stringWithFormat:@"%s/.instance.lock", folder];
        const char *path = [lock fileSystemRepresentation];

        // Two processes, one lock file, and the first is still holding when the
        // second asks. The second must be told the lock is taken rather than
        // handed one of its own: were the lock a no-op, it would report
        // MGInstanceLockAcquired here and the survivor count below would be two.
        pid_t first = 0, second = 0;
        int releaseFirst = -1, releaseSecond = -1;
        MGInstanceLockOutcome firstOutcome = startContender(path, &first, &releaseFirst);
        MGInstanceLockOutcome secondOutcome = startContender(path, &second, &releaseSecond);

        require(firstOutcome == MGInstanceLockAcquired,
                @"the first copy could not take a free lock");
        require(secondOutcome == MGInstanceLockHeldByAnother,
                @"the second copy was not told the lock is held");

        int acquired = (firstOutcome == MGInstanceLockAcquired) +
                       (secondOutcome == MGInstanceLockAcquired);
        require(acquired == 1, @"two copies contending for one lock did not leave one holder");

        stopContender(second, releaseSecond);

        // A copy that dies without unwinding still releases the lock, because
        // the kernel closes its descriptor. Killing outright is the case that
        // matters: no code of ours runs on the way out.
        require(kill(first, SIGKILL) == 0,
                @"could not kill the instance lock holder");
        close(releaseFirst);
        int firstStatus = 0;
        pid_t waitedForFirst = waitpid(first, &firstStatus, 0);
        require(waitedForFirst == first,
                @"could not wait for the killed instance lock holder");
        require(waitedForFirst == first && WIFSIGNALED(firstStatus) &&
                    WTERMSIG(firstStatus) == SIGKILL,
                @"the instance lock holder did not terminate by SIGKILL");

        pid_t successor = 0;
        int releaseSuccessor = -1;
        MGInstanceLockOutcome successorOutcome =
            startContender(path, &successor, &releaseSuccessor);
        require(successorOutcome == MGInstanceLockAcquired,
                @"a killed holder left the lock held");
        stopContender(successor, releaseSuccessor);

        // A lock the process cannot open is reported as such rather than read
        // as a rival, which is what keeps the app starting when the folder is
        // unwritable.
        int descriptor = 0;
        require(MGTakeInstanceLockAtPath("/no-such-folder/.instance.lock", &descriptor) ==
                    MGInstanceLockCouldNotOpen,
                @"an unopenable lock path was not reported as unopenable");
        require(descriptor == -1, @"a failed lock left a descriptor behind");

        unlink(path);
        rmdir(folder);

        if (failures == 0)
            NSLog(@"single instance: all checks passed");
    }
    return failures == 0 ? 0 : 1;
}
