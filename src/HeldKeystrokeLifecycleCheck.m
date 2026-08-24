// Verifies that a physical click holds a configured keystroke between its edges.

#import <Carbon/Carbon.h>
#import "HeldKeystrokeLifecycle.h"

static int failures = 0;

static void require(BOOL condition, const char *message) {
    if (condition)
        return;
    fprintf(stderr, "FAIL  %s\n", message);
    failures++;
}

int main(void) {
    MGHeldKeystrokeLifecycle lifecycle;
    MGHeldKeystrokeLifecycleInitialize(&lifecycle);
    MGKeyEventStep steps[MG_HELD_KEYSTROKE_MAX_STEPS];

    size_t count = MGHeldKeystrokeLifecycleBegin(
        &lifecycle, 1, kVK_F5, YES, 0, 0, NO, steps);
    require(count == 1, "F5 click posts one down edge");
    if (count == 1)
        require(steps[0].keyCode == kVK_F5 && steps[0].keyDown,
                "F5 click begins with F5 down");
    require(MGHeldKeystrokeLifecycleIsActiveForOwner(&lifecycle, 1),
            "click owns its held F5 key");
    CGKeyCode heldKeyCode = 0;
    require(MGHeldKeystrokeLifecycleHeldKeyCode(&lifecycle, &heldKeyCode) &&
                heldKeyCode == kVK_F5,
            "active click exposes its held key through the lifecycle API");

    count = MGHeldKeystrokeLifecycleEnd(
        &lifecycle, 1, 0, NO, steps);
    require(count == 1, "F5 click posts one up edge");
    if (count == 1)
        require(steps[0].keyCode == kVK_F5 && !steps[0].keyDown,
                "F5 click ends with F5 up");
    require(!MGHeldKeystrokeLifecycleIsActiveForOwner(&lifecycle, 1),
            "F5 click releases its ownership");
    require(!MGHeldKeystrokeLifecycleHeldKeyCode(&lifecycle, &heldKeyCode),
            "ended click no longer exposes a held key");

    CGEventFlags function = kCGEventFlagMaskSecondaryFn;
    count = MGHeldKeystrokeLifecycleBegin(
        &lifecycle, 1, 0, NO, function, 0, NO, steps);
    require(count == 1 && steps[0].keyCode == kVK_Function &&
                steps[0].keyDown,
            "modifier-only Fn still begins on click-down");
    count = MGHeldKeystrokeLifecycleEnd(
        &lifecycle, 1, 0, NO, steps);
    require(count == 1 && steps[0].keyCode == kVK_Function &&
                !steps[0].keyDown,
            "modifier-only Fn still ends on click-up");

    count = MGHeldKeystrokeLifecycleBegin(
        &lifecycle, 2, kVK_ANSI_E, YES, function, 0, NO, steps);
    require(count == 2, "Fn-E click posts two down edges");
    if (count == 2) {
        require(steps[0].keyCode == kVK_Function && steps[0].keyDown,
                "Fn-E presses Fn first");
        require(steps[1].keyCode == kVK_ANSI_E && steps[1].keyDown &&
                    steps[1].flags == function,
                "Fn-E presses E with Fn active");
    }
    require(MGHeldKeystrokeLifecycleEnd(
                &lifecycle, 1, 0, NO, steps) == 0,
            "another device cannot end the held chord");
    count = MGHeldKeystrokeLifecycleEnd(
        &lifecycle, 2, 0, NO, steps);
    require(count == 2, "Fn-E click posts two up edges");
    if (count == 2) {
        require(steps[0].keyCode == kVK_ANSI_E && !steps[0].keyDown &&
                    steps[0].flags == function,
                "Fn-E releases E before Fn");
        require(steps[1].keyCode == kVK_Function && !steps[1].keyDown,
                "Fn-E releases Fn last");
    }

    count = MGHeldKeystrokeLifecycleBegin(
        &lifecycle, 1, kVK_F5, YES, 0, 0, YES, steps);
    require(count == 0,
            "a physically held F5 needs no synthetic down edge");
    require(MGHeldKeystrokeLifecycleIsActiveForOwner(&lifecycle, 1),
            "physical F5 still owns the click lifecycle");
    require(MGHeldKeystrokeLifecycleCancel(
                &lifecycle, 0, YES, steps) == 0,
            "cancellation does not release a physical F5");

    count = MGHeldKeystrokeLifecycleBegin(
        &lifecycle, 1, kVK_F5, YES, 0, 0, NO, steps);
    require(count == 1, "cancellable F5 begins with one down edge");
    count = MGHeldKeystrokeLifecycleCancel(
        &lifecycle, 0, NO, steps);
    require(count == 1 && steps[0].keyCode == kVK_F5 &&
                !steps[0].keyDown,
            "cancellation releases synthetic F5 once");
    require(MGHeldKeystrokeLifecycleCancel(
                &lifecycle, 0, NO, steps) == 0,
            "repeated cancellation posts no second F5 release");

    if (failures == 0) {
        printf("held keystroke lifecycle: all checks passed\n");
        return 0;
    }
    fprintf(stderr, "held keystroke lifecycle: %d failure(s)\n", failures);
    return 1;
}
