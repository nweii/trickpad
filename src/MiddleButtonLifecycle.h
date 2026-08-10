// Declares the one held middle-button press a gesture can start, so a press produces a single down, the drags it holds through, and a single up.

#import <Foundation/Foundation.h>

typedef struct {
    BOOL held;
    int device;
} MGMiddleButtonLifecycle;

void MGMiddleButtonLifecycleInitialize(MGMiddleButtonLifecycle *lifecycle);

// Reports whether a binding's action holds the button down for the length of
// the press. Every other action stays momentary.
BOOL MGMiddleButtonLifecycleCommandHoldsButton(NSString *command);

// Claims the press for a device, identified by a caller-owned nonzero number.
// Returns NO when a press is already held, so an ambiguous second gesture
// cannot press a button the first one still owes an up for.
BOOL MGMiddleButtonLifecycleBegin(MGMiddleButtonLifecycle *lifecycle, int device);

BOOL MGMiddleButtonLifecycleIsHeld(const MGMiddleButtonLifecycle *lifecycle);

// The device holding the press, or zero when no press is held.
int MGMiddleButtonLifecycleHoldingDevice(const MGMiddleButtonLifecycle *lifecycle);

// Ends the press. Returns YES exactly once per press, telling the caller it
// owes a middle-button up: either the release it is handling or one it posts
// itself. Every path that abandons a press calls this, so no path can leave the
// button down.
BOOL MGMiddleButtonLifecycleEnd(MGMiddleButtonLifecycle *lifecycle);
