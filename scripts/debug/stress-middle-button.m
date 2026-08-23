// Measures Trickpad DEV CPU use and validates the Mouse3 event lifecycle during
// one sustained physical press-drag-release test.

#import <AppKit/AppKit.h>
#import <ApplicationServices/ApplicationServices.h>
#import <libproc.h>

typedef struct {
    pid_t trickpadPID;
    BOOL held;
    int failures;
    long dragCount;
    BOOL waitingForCleanDown;
    CFAbsoluteTime downAt;
    uint64_t cpuAtDown;
    double idleCPUPercent;
} StressState;

static BOOL processCPUTime(pid_t pid, uint64_t *nanoseconds) {
    struct rusage_info_v4 usage = {0};
    if (proc_pid_rusage(pid, RUSAGE_INFO_V4, (rusage_info_t *)&usage) != 0)
        return NO;
    *nanoseconds = usage.ri_user_time + usage.ri_system_time;
    return YES;
}

static CGEventRef observe(CGEventTapProxy proxy, CGEventType type,
                          CGEventRef event, void *refcon) {
    StressState *state = refcon;
    if (CGEventGetIntegerValueField(event, kCGMouseEventButtonNumber) != 2)
        return event;

    if (type == kCGEventOtherMouseDown) {
        if (state->held) {
            state->failures++;
            printf("FAIL  duplicate Mouse3 down before its up\n");
            fflush(stdout);
            return event;
        }
        state->held = YES;
        state->dragCount = 0;
        state->downAt = CFAbsoluteTimeGetCurrent();
        if (!processCPUTime(state->trickpadPID, &state->cpuAtDown)) {
            state->failures++;
            printf("FAIL  could not read Trickpad DEV CPU time\n");
        }
        printf("DOWN  Hold the gesture and drag continuously for 10 seconds.\n");
    } else if (type == kCGEventOtherMouseDragged) {
        if (!state->held) {
            if (!state->waitingForCleanDown) {
                state->waitingForCleanDown = YES;
                printf("WAIT  The monitor attached during an existing press. Release it before starting the test.\n");
            }
        } else {
            state->dragCount++;
        }
    } else if (type == kCGEventOtherMouseUp) {
        if (!state->held) {
            if (state->waitingForCleanDown) {
                state->waitingForCleanDown = NO;
                printf("READY  The earlier press is released. Start the 10-second test.\n");
            } else {
                state->failures++;
                printf("FAIL  Mouse3 up arrived without a down\n");
            }
            fflush(stdout);
            return event;
        }

        CFAbsoluteTime duration = CFAbsoluteTimeGetCurrent() - state->downAt;
        uint64_t cpuAtUp = 0;
        double cpuPercent = 0;
        if (!processCPUTime(state->trickpadPID, &cpuAtUp) ||
            cpuAtUp < state->cpuAtDown || duration <= 0) {
            state->failures++;
            printf("FAIL  could not finish the Trickpad DEV CPU measurement\n");
        } else {
            cpuPercent = ((double)(cpuAtUp - state->cpuAtDown) / 1e9) /
                duration * 100.0;
        }

        state->held = NO;
        double dragRate = duration > 0 ? state->dragCount / duration : 0;
        printf("UP    %.1f seconds, %ld drags (%.1f per second)\n",
               duration, state->dragCount, dragRate);
        printf("CPU   %.2f%% during drag; %.2f%% idle baseline\n",
               cpuPercent, state->idleCPUPercent);
        if (duration < 8.0 || state->dragCount < 40) {
            printf("REPEAT  Hold and move continuously for at least 10 seconds.\n");
        } else if (state->failures == 0) {
            printf("PASS  One down and one up, with no duplicate or orphaned events.\n");
            printf("      Confirm the pointer stayed smooth, then press Control-C.\n");
        } else {
            printf("FAIL  %d lifecycle problem%s detected.\n", state->failures,
                   state->failures == 1 ? "" : "s");
        }
    }
    fflush(stdout);
    return event;
}

int main(void) {
    @autoreleasepool {
        NSArray *apps = [NSRunningApplication
            runningApplicationsWithBundleIdentifier:@"fyi.thirdwind.trickpad.dev"];
        NSRunningApplication *trickpad = [apps firstObject];
        if (trickpad == nil) {
            fprintf(stderr, "Trickpad DEV is not running from an application bundle.\n");
            return 1;
        }

        StressState state = {0};
        state.trickpadPID = [trickpad processIdentifier];
        uint64_t idleStart = 0, idleEnd = 0;
        if (!processCPUTime(state.trickpadPID, &idleStart)) {
            fprintf(stderr, "Could not read Trickpad DEV CPU time.\n");
            return 1;
        }
        printf("Measuring Trickpad DEV idle CPU for 2 seconds...\n");
        fflush(stdout);
        [NSThread sleepForTimeInterval:2.0];
        if (!processCPUTime(state.trickpadPID, &idleEnd)) {
            fprintf(stderr, "Could not finish the idle CPU measurement.\n");
            return 1;
        }
        state.idleCPUPercent = ((double)(idleEnd - idleStart) / 1e9) / 2.0 * 100.0;

        CGEventMask mask = CGEventMaskBit(kCGEventOtherMouseDown) |
                           CGEventMaskBit(kCGEventOtherMouseUp) |
                           CGEventMaskBit(kCGEventOtherMouseDragged);
        CFMachPortRef tap = CGEventTapCreate(
            kCGSessionEventTap, kCGTailAppendEventTap,
            kCGEventTapOptionListenOnly, mask, observe, &state);
        if (tap == NULL) {
            fprintf(stderr, "Could not observe mouse events. Allow your terminal or agent application in Accessibility settings, then retry.\n");
            return 1;
        }
        CFRunLoopSourceRef source = CFMachPortCreateRunLoopSource(
            kCFAllocatorDefault, tap, 0);
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source,
                           kCFRunLoopCommonModes);
        CGEventTapEnable(tap, true);
        printf("Idle baseline: %.2f%% CPU. Ready for one Mouse3 drag.\n",
               state.idleCPUPercent);
        printf("Press and hold the bound physical gesture, move continuously for 10 seconds, then release.\n");
        fflush(stdout);
        CFRunLoopRun();
        CFRelease(source);
        CFRelease(tap);
    }
    return 0;
}
