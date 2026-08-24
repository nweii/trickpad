// Verifies that a physical click holds only synthetic modifier ownership and releases it once.

#import <Carbon/Carbon.h>
#import <IOKit/hidsystem/IOLLEvent.h>
#import "HeldModifierLifecycle.h"

static int failures = 0;

static void require(BOOL condition, const char *message) {
    if (condition)
        return;
    fprintf(stderr, "FAIL  %s\n", message);
    failures++;
}

int main(void) {
    MGHeldModifierLifecycle lifecycle;
    MGHeldModifierLifecycleInitialize(&lifecycle);
    MGKeyEventStep steps[9];
    CGEventFlags function = kCGEventFlagMaskSecondaryFn;

    size_t count = MGHeldModifierLifecycleBegin(
        &lifecycle, 1, function, 0, steps);
    require(count == 1, "Fn click posts one down edge");
    if (count == 1) {
        require(steps[0].keyCode == kVK_Function && steps[0].keyDown,
                "Fn click begins with Fn down");
        require(steps[0].flags == function,
                "Fn down carries the Fn flag");
    }
    require(MGHeldModifierLifecycleIsActiveForOwner(&lifecycle, 1),
            "click owns its held modifier");

    count = MGHeldModifierLifecycleEnd(&lifecycle, 1, 0, steps);
    require(count == 1, "Fn click posts one up edge");
    if (count == 1) {
        require(steps[0].keyCode == kVK_Function && !steps[0].keyDown,
                "Fn click ends with Fn up");
        require(steps[0].flags == 0,
                "Fn up clears the Fn flag");
    }
    require(!MGHeldModifierLifecycleIsActiveForOwner(&lifecycle, 1),
            "Fn click releases its ownership");

    CGEventFlags leftCommand =
        kCGEventFlagMaskCommand | NX_DEVICELCMDKEYMASK;
    count = MGHeldModifierLifecycleBegin(
        &lifecycle, 2, leftCommand, 0, steps);
    require(count == 1 && steps[0].keyCode == 55 && steps[0].keyDown,
            "Command click posts Command down");
    require(MGHeldModifierLifecycleEnd(&lifecycle, 1, 0, steps) == 0,
            "another device cannot end the held modifier");
    require(MGHeldModifierLifecycleIsActiveForOwner(&lifecycle, 2),
            "wrong-owner mouse-up preserves ownership");
    count = MGHeldModifierLifecycleCancel(&lifecycle, 0, steps);
    require(count == 1 && steps[0].keyCode == 55 && !steps[0].keyDown,
            "cancellation releases Command once");
    require(MGHeldModifierLifecycleCancel(&lifecycle, 0, steps) == 0,
            "repeated cancellation posts no second release");

    count = MGHeldModifierLifecycleBegin(
        &lifecycle, 1, function, function, steps);
    require(count == 0,
            "physical Fn needs no synthetic down edge");
    require(MGHeldModifierLifecycleIsActiveForOwner(&lifecycle, 1),
            "physical Fn still owns the click lifecycle");
    require(MGHeldModifierLifecycleEnd(&lifecycle, 1, function, steps) == 0,
            "physical Fn receives no synthetic up edge");

    count = MGHeldModifierLifecycleBegin(
        &lifecycle, 1, function, 0, steps);
    require(count == 1, "synthetic Fn starts before physical takeover");
    require(MGHeldModifierLifecycleEnd(&lifecycle, 1, function, steps) == 0,
            "physical Fn takeover prevents a synthetic release");

    CGEventFlags leftShift =
        kCGEventFlagMaskShift | NX_DEVICELSHIFTKEYMASK;
    CGEventFlags leftOption =
        kCGEventFlagMaskAlternate | NX_DEVICELALTKEYMASK;
    count = MGHeldModifierLifecycleBegin(
        &lifecycle, 1, leftShift | leftOption, 0, steps);
    require(count == 2,
            "a modifier-only combination presses each modifier");
    if (count == 2) {
        require(steps[0].keyCode == 56 && steps[0].keyDown,
                "combination presses Shift first");
        require(steps[1].keyCode == 58 && steps[1].keyDown,
                "combination presses Option second");
        require((steps[1].flags & (leftShift | leftOption)) ==
                    (leftShift | leftOption),
                "second down carries both active modifiers");
    }
    count = MGHeldModifierLifecycleEnd(&lifecycle, 1, 0, steps);
    require(count == 2,
            "a modifier-only combination releases each modifier");
    if (count == 2) {
        require(steps[0].keyCode == 58 && !steps[0].keyDown,
                "combination releases Option first");
        require(steps[1].keyCode == 56 && !steps[1].keyDown,
                "combination releases Shift second");
        require(steps[1].flags == 0,
                "last release clears synthetic modifier flags");
    }

    if (failures == 0) {
        printf("held modifier lifecycle: all checks passed\n");
        return 0;
    }
    fprintf(stderr, "held modifier lifecycle: %d failure(s)\n", failures);
    return 1;
}
