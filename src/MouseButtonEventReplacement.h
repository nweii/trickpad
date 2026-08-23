// Declares the marked event copy Trickpad uses when a physical click becomes
// a numbered macOS mouse button.

#import <ApplicationServices/ApplicationServices.h>

extern const int64_t MGTrickpadReplayedMouseEventMarker;

CGEventRef MGCreateMouseButtonReplacementEvent(
    CGEventRef source,
    CGEventType replacementType,
    int64_t buttonNumber);
