// Creates numbered-button event copies that retain the physical event's
// metadata and bypass Trickpad when reposted through its session event tap.

#import "MouseButtonEventReplacement.h"

const int64_t MGTrickpadReplayedMouseEventMarker = 0x545249434b504144;

CGEventRef MGCreateMouseButtonReplacementEvent(
    CGEventRef source,
    CGEventType replacementType,
    int64_t buttonNumber) {
    CGEventRef replacement = CGEventCreateCopy(source);
    if (replacement == NULL)
        return NULL;
    CGEventSetType(replacement, replacementType);
    CGEventSetIntegerValueField(replacement, kCGMouseEventButtonNumber,
                                buttonNumber);
    CGEventSetIntegerValueField(replacement, kCGEventSourceUserData,
                                MGTrickpadReplayedMouseEventMarker);
    return replacement;
}
