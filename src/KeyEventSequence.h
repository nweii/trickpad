// Defines the keyboard-event sequence used to represent one configured keystroke.
// The planner is separate from event posting so its modifier ownership is testable.

#import <ApplicationServices/ApplicationServices.h>

typedef struct {
    CGKeyCode keyCode;
    bool keyDown;
    CGEventFlags flags;
} MGKeyEventStep;

size_t MGPlanKeyEventSequence(CGKeyCode keyCode,
                              bool hasKey,
                              CGEventFlags requestedFlags,
                              CGEventFlags physicalFlags,
                              MGKeyEventStep steps[18]);
