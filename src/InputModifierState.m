// Maintains the current Fn state and a generation that changes on every Fn
// transition, including a release and re-press between repeated taps.

#import "InputModifierState.h"

void MGInputModifierStateInit(MGInputModifierState *state, BOOL functionDown) {
    atomic_init(&state->functionDown, functionDown);
    atomic_init(&state->functionGeneration, 1);
}

void MGInputModifierStateObserveFunction(MGInputModifierState *state, BOOL functionDown) {
    BOOL previous = atomic_exchange(&state->functionDown, functionDown);
    if (previous != functionDown)
        atomic_fetch_add(&state->functionGeneration, 1);
}

MGInputModifierSnapshot MGInputModifierStateSnapshot(MGInputModifierState *state) {
    MGInputModifierSnapshot snapshot = {
        .functionDown = atomic_load(&state->functionDown),
        .functionGeneration = atomic_load(&state->functionGeneration),
    };
    return snapshot;
}
