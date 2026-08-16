// Prints the middle-button events applications receive after other event taps
// rewrite them, so a binding's down, drag, and up can be checked directly.

#import <ApplicationServices/ApplicationServices.h>

static CFAbsoluteTime downAt = 0;
static long dragCount = 0;

static CGEventRef observe(CGEventTapProxy proxy, CGEventType type, CGEventRef event, void *refcon) {
    int64_t button = CGEventGetIntegerValueField(event, kCGMouseEventButtonNumber);
    // Button 2 is the middle button. Other-button events for any other button
    // belong to a different device and are not what this tool watches.
    if (button != 2)
        return event;

    CGPoint at = CGEventGetLocation(event);
    if (type == kCGEventOtherMouseDown) {
        downAt = CFAbsoluteTimeGetCurrent();
        dragCount = 0;
        printf("DOWN   at %.0f,%.0f\n", at.x, at.y);
    } else if (type == kCGEventOtherMouseDragged) {
        dragCount++;
        // One line per drag would bury the down and up in a long press.
        if (dragCount % 10 == 1)
            printf("DRAG   at %.0f,%.0f (%ld so far)\n", at.x, at.y, dragCount);
    } else if (type == kCGEventOtherMouseUp) {
        printf("UP     at %.0f,%.0f after %.0f ms and %ld drags\n",
               at.x, at.y, (CFAbsoluteTimeGetCurrent() - downAt) * 1000.0, dragCount);
        printf("       %s\n", dragCount > 0 ? "press held and dragged" : "press was stationary");
    }
    fflush(stdout);
    return event;
}

int main(void) {
    CGEventMask mask = CGEventMaskBit(kCGEventOtherMouseDown) |
                       CGEventMaskBit(kCGEventOtherMouseUp) |
                       CGEventMaskBit(kCGEventOtherMouseDragged);
    // A listen-only tap: it reports what happened and changes nothing, so a
    // stuck button stays visible rather than being papered over.
    CFMachPortRef tap = CGEventTapCreate(kCGSessionEventTap, kCGTailAppendEventTap,
                                         kCGEventTapOptionListenOnly, mask, observe, NULL);
    if (tap == NULL) {
        fprintf(stderr, "Could not create the event tap. Grant this program Accessibility access.\n");
        return 1;
    }
    CFRunLoopSourceRef source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0);
    CFRunLoopAddSource(CFRunLoopGetCurrent(), source, kCFRunLoopCommonModes);
    CGEventTapEnable(tap, true);
    printf("Watching middle-button events. Press Control-C to stop.\n");
    fflush(stdout);
    CFRunLoopRun();
    return 0;
}
