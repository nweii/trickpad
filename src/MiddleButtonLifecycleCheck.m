// Checks that a held middle-button press produces one down and one up, survives its drags, and is never left down.

#import <Foundation/Foundation.h>
#import "MiddleButtonLifecycle.h"

static const int kTrackpad = 1;
static const int kMagicMouse = 2;

static int failures = 0;

static void require(BOOL condition, NSString *message) {
    if (!condition) {
        fprintf(stderr, "FAIL  %s\n", [message UTF8String]);
        failures++;
    }
}

int main(void) {
    @autoreleasepool {
        MGMiddleButtonLifecycle lifecycle;
        MGMiddleButtonLifecycleInitialize(&lifecycle);

        require(MGMiddleButtonLifecycleCommandHoldsButton(@"Middle Click"),
                @"a middle-click binding did not hold the button");
        require(!MGMiddleButtonLifecycleCommandHoldsButton(@"Mission Control"),
                @"a binding to another action held the button");
        require(!MGMiddleButtonLifecycleCommandHoldsButton(nil),
                @"an unbound gesture held the button");

        // A stationary trackpad click: one down, one up, nothing left held.
        require(MGMiddleButtonLifecycleBegin(&lifecycle, kTrackpad),
                @"a trackpad click did not press the button");
        require(MGMiddleButtonLifecycleIsHeld(&lifecycle) &&
                    MGMiddleButtonLifecycleHoldingDevice(&lifecycle) == kTrackpad,
                @"the pressed button did not report the trackpad as its holder");
        require(MGMiddleButtonLifecycleEnd(&lifecycle),
                @"the release of a pressed button owed no middle-button up");
        require(!MGMiddleButtonLifecycleIsHeld(&lifecycle) &&
                    MGMiddleButtonLifecycleHoldingDevice(&lifecycle) == 0,
                @"the button stayed down after its release");
        require(!MGMiddleButtonLifecycleEnd(&lifecycle),
                @"a second release posted another middle-button up");

        // Movement while the button is held rewrites drags for the whole press,
        // and the press still ends once.
        MGMiddleButtonLifecycleBegin(&lifecycle, kTrackpad);
        for (int move = 0; move < 5; move++)
            require(MGMiddleButtonLifecycleIsHeld(&lifecycle),
                    @"a drag during the press did not stay a middle-button drag");
        require(MGMiddleButtonLifecycleEnd(&lifecycle),
                @"a dragged press owed no middle-button up");
        require(!MGMiddleButtonLifecycleIsHeld(&lifecycle),
                @"a dragged press left the button down");

        // Gesture ambiguity: a second gesture cannot press a button the first
        // one still owes an up for, and the first release still ends the press.
        MGMiddleButtonLifecycleBegin(&lifecycle, kTrackpad);
        require(!MGMiddleButtonLifecycleBegin(&lifecycle, kMagicMouse),
                @"a second gesture pressed an already-held button");
        require(MGMiddleButtonLifecycleHoldingDevice(&lifecycle) == kTrackpad,
                @"a second gesture took over the held button");
        require(MGMiddleButtonLifecycleEnd(&lifecycle),
                @"the first gesture's release owed no middle-button up");
        require(!MGMiddleButtonLifecycleIsHeld(&lifecycle),
                @"an ambiguous press left the button down");

        // Cancellation and every reset (a reload, wake, or turning gestures
        // off) end the press first, so nothing resets over a held button.
        MGMiddleButtonLifecycleBegin(&lifecycle, kMagicMouse);
        require(MGMiddleButtonLifecycleEnd(&lifecycle),
                @"cancellation owed no middle-button up");
        MGMiddleButtonLifecycleInitialize(&lifecycle);
        require(!MGMiddleButtonLifecycleIsHeld(&lifecycle),
                @"a reset left the button down");
        require(!MGMiddleButtonLifecycleEnd(&lifecycle),
                @"a reset after a release posted another middle-button up");

        require(!MGMiddleButtonLifecycleBegin(&lifecycle, 0),
                @"a press without a device was claimed");

        if (failures == 0) {
            printf("middle button lifecycle: all checks passed\n");
            return 0;
        }
        fprintf(stderr, "middle button lifecycle: %d failure(s)\n", failures);
        return 1;
    }
}
