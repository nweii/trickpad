// Checks that configured chords become complete keyboard sequences without
// releasing modifier keys that the user is physically holding.

#import <ApplicationServices/ApplicationServices.h>
#import <IOKit/hidsystem/IOLLEvent.h>
#import "KeyEventSequence.h"

static int failures = 0;

static void expectStep(const char *label, MGKeyEventStep actual,
                       CGKeyCode keyCode, bool keyDown, CGEventFlags flags) {
    if (actual.keyCode == keyCode && actual.keyDown == keyDown && actual.flags == flags)
        return;
    fprintf(stderr, "FAIL  %s\n", label);
    failures++;
}

int main(void) {
    MGKeyEventStep steps[18];
    CGEventFlags control = kCGEventFlagMaskControl | NX_DEVICELCTLKEYMASK;
    CGEventFlags command = kCGEventFlagMaskCommand | NX_DEVICELCMDKEYMASK;
    CGEventFlags chord = control | command;

    size_t count = MGPlanKeyEventSequence(2, true, chord, 0, steps);
    if (count != 6) {
        fprintf(stderr, "FAIL  control-command-D event count\n");
        failures++;
    } else {
        expectStep("control down", steps[0], 59, true, control);
        expectStep("command down", steps[1], 55, true, chord);
        expectStep("D down", steps[2], 2, true, chord);
        expectStep("D up", steps[3], 2, false, chord);
        expectStep("command up", steps[4], 55, false, control);
        expectStep("control up", steps[5], 59, false, 0);
    }

    count = MGPlanKeyEventSequence(2, true, chord, kCGEventFlagMaskControl, steps);
    if (count != 4) {
        fprintf(stderr, "FAIL  physically held control event count\n");
        failures++;
    } else {
        expectStep("held control is not pressed", steps[0], 55, true, chord);
        expectStep("held control chord down", steps[1], 2, true, chord);
        expectStep("held control chord up", steps[2], 2, false, chord);
        expectStep("held control is not released", steps[3], 55, false, control);
    }

    count = MGPlanKeyEventSequence(53, true, 0, 0, steps);
    if (count != 2) {
        fprintf(stderr, "FAIL  bare Escape event count\n");
        failures++;
    } else {
        expectStep("Escape down", steps[0], 53, true, 0);
        expectStep("Escape up", steps[1], 53, false, 0);
    }

    CGEventFlags rightControl = kCGEventFlagMaskControl | NX_DEVICERCTLKEYMASK;
    count = MGPlanKeyEventSequence(49, true, rightControl, 0, steps);
    if (count != 4) {
        fprintf(stderr, "FAIL  right-control-Space event count\n");
        failures++;
    } else {
        expectStep("right control down", steps[0], 62, true, rightControl);
        expectStep("Space with right control down", steps[1], 49, true, rightControl);
        expectStep("Space with right control up", steps[2], 49, false, rightControl);
        expectStep("right control up", steps[3], 62, false, 0);
    }

    count = MGPlanKeyEventSequence(49, true, rightControl, rightControl, steps);
    if (count != 2) {
        fprintf(stderr, "FAIL  physically held right control event count\n");
        failures++;
    } else {
        expectStep("held right control chord down", steps[0], 49, true, rightControl);
        expectStep("held right control chord up", steps[1], 49, false, rightControl);
    }

    CGEventFlags bothCommands = kCGEventFlagMaskCommand |
        NX_DEVICELCMDKEYMASK | NX_DEVICERCMDKEYMASK;
    count = MGPlanKeyEventSequence(0, false, bothCommands, 0, steps);
    if (count != 4) {
        fprintf(stderr, "FAIL  left-command-right-command event count\n");
        failures++;
    } else {
        CGEventFlags leftCommand = kCGEventFlagMaskCommand | NX_DEVICELCMDKEYMASK;
        expectStep("left command down", steps[0], 55, true, leftCommand);
        expectStep("right command down", steps[1], 54, true, bothCommands);
        expectStep("right command up", steps[2], 54, false, leftCommand);
        expectStep("left command up", steps[3], 55, false, 0);
    }

    CGEventFlags leftCommand = kCGEventFlagMaskCommand | NX_DEVICELCMDKEYMASK;
    count = MGPlanKeyEventSequence(0, false, bothCommands, leftCommand, steps);
    if (count != 2) {
        fprintf(stderr, "FAIL  physically held left command event count\n");
        failures++;
    } else {
        expectStep("held left command is not pressed", steps[0], 54, true, bothCommands);
        expectStep("held left command is not released", steps[1], 54, false, leftCommand);
    }

    if (failures == 0) {
        printf("key event sequence: all checks passed\n");
        return 0;
    }
    fprintf(stderr, "key event sequence: %d failure(s)\n", failures);
    return 1;
}
