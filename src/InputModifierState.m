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

static void observeFunctionEvent(MGInputModifierState *state,
                                 BOOL functionDown,
                                 BOOL synthesizedByTrickpad) {
    if (!synthesizedByTrickpad)
        MGInputModifierStateObserveFunction(state, functionDown);
}

void MGInputModifierStateObserveFlagsChanged(MGInputModifierState *state,
                                             uint16_t keyCode,
                                             BOOL functionDown,
                                             BOOL synthesizedByTrickpad) {
    // Only the physical Fn virtual key may change this state. Other function
    // keys can carry the same device-independent function flag.
    if (keyCode != 63)
        return;
    observeFunctionEvent(state, functionDown, synthesizedByTrickpad);
}

MGInputModifierSnapshot MGInputModifierStateSnapshot(MGInputModifierState *state) {
    MGInputModifierSnapshot snapshot = {
        .functionDown = atomic_load(&state->functionDown),
        .functionGeneration = atomic_load(&state->functionGeneration),
    };
    return snapshot;
}
