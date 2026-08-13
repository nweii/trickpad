// Posts one right-Control-plus-Space chord using Magic Gestures' event planner.

#import <ApplicationServices/ApplicationServices.h>
#import <IOKit/hidsystem/IOLLEvent.h>
#import "KeyEventSequence.h"

int main(void) {
    CGEventFlags flags = kCGEventFlagMaskControl | NX_DEVICERCTLKEYMASK;
    MGKeyEventStep steps[18];
    size_t count = MGPlanKeyEventSequence(49, true, flags, 0, steps);
    CGEventSourceRef source = CGEventSourceCreate(kCGEventSourceStateHIDSystemState);
    if (source == NULL)
        return 1;
    for (size_t i = 0; i < count; i++) {
        CGEventRef event = CGEventCreateKeyboardEvent(
            source, steps[i].keyCode, steps[i].keyDown);
        if (event == NULL) {
            CFRelease(source);
            return 1;
        }
        CGEventSetFlags(event, steps[i].flags);
        CGEventPost(kCGSessionEventTap, event);
        CFRelease(event);
    }
    CFRelease(source);
    return 0;
}
