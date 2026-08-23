// Checks that a physical mouse event can become a marked numbered-button copy
// without changing the original event seen by earlier event taps.

#import <ApplicationServices/ApplicationServices.h>
#import "MouseButtonEventReplacement.h"

static int failures = 0;

static void require(bool condition, const char *message) {
    if (!condition) {
        fprintf(stderr, "FAIL  %s\n", message);
        failures++;
    }
}

static void checkReplacement(CGEventType sourceType,
                             CGEventType replacementType,
                             CGMouseButton sourceButton,
                             int64_t replacementButton) {
    CGPoint location = CGPointMake(123.5, 456.25);
    CGEventRef source = CGEventCreateMouseEvent(
        NULL, sourceType, location, sourceButton);
    CGEventSetTimestamp(source, 987654321);
    CGEventSetFlags(source, kCGEventFlagMaskShift);
    CGEventSetIntegerValueField(source, kCGMouseEventDeltaX, 7);
    CGEventSetIntegerValueField(source, kCGMouseEventDeltaY, -4);

    CGEventRef replacement = MGCreateMouseButtonReplacementEvent(
        source, replacementType, replacementButton);

    require(replacement != NULL, "replacement event was not created");
    if (replacement != NULL) {
        CGPoint replacementLocation = CGEventGetLocation(replacement);
        require(CGEventGetType(replacement) == replacementType,
                "replacement kept the physical event type");
        require(CGEventGetIntegerValueField(
                    replacement, kCGMouseEventButtonNumber) == replacementButton,
                "replacement did not carry the numbered mouse button");
        require(CGEventGetIntegerValueField(
                    replacement, kCGEventSourceUserData) ==
                    MGTrickpadReplayedMouseEventMarker,
                "replacement was not marked to bypass Trickpad");
        require(replacementLocation.x == location.x &&
                    replacementLocation.y == location.y,
                "replacement did not preserve the pointer location");
        require(CGEventGetTimestamp(replacement) == 987654321,
                "replacement did not preserve the event timestamp");
        require(CGEventGetFlags(replacement) == kCGEventFlagMaskShift,
                "replacement did not preserve event flags");
        require(CGEventGetIntegerValueField(
                    replacement, kCGMouseEventDeltaX) == 7 &&
                    CGEventGetIntegerValueField(
                    replacement, kCGMouseEventDeltaY) == -4,
                "replacement did not preserve pointer movement");
        CFRelease(replacement);
    }

    require(CGEventGetType(source) == sourceType,
            "creating a replacement changed the physical event type");
    require(CGEventGetIntegerValueField(source, kCGMouseEventButtonNumber) ==
                sourceButton,
            "creating a replacement changed the physical button number");
    require(CGEventGetIntegerValueField(source, kCGEventSourceUserData) == 0,
            "creating a replacement marked the physical event");
    CFRelease(source);
}

int main(void) {
    checkReplacement(kCGEventLeftMouseDown, kCGEventOtherMouseDown,
                     kCGMouseButtonLeft, 2);
    checkReplacement(kCGEventLeftMouseDragged, kCGEventOtherMouseDragged,
                     kCGMouseButtonLeft, 3);
    checkReplacement(kCGEventLeftMouseUp, kCGEventOtherMouseUp,
                     kCGMouseButtonLeft, 31);

    if (failures == 0) {
        printf("mouse button event replacement: all checks passed\n");
        return 0;
    }
    fprintf(stderr, "mouse button event replacement: %d failure(s)\n", failures);
    return 1;
}
