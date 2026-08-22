// Tracks physical input-modifier transitions so repeated gestures can require
// one continuous hold without depending on when their delayed action runs.

#import <Foundation/Foundation.h>
#import <stdatomic.h>

typedef struct {
    BOOL functionDown;
    uint64_t functionGeneration;
} MGInputModifierSnapshot;

typedef struct {
    atomic_bool functionDown;
    atomic_uint_fast64_t functionGeneration;
} MGInputModifierState;

void MGInputModifierStateInit(MGInputModifierState *state, BOOL functionDown);
void MGInputModifierStateObserveFunction(MGInputModifierState *state, BOOL functionDown);
MGInputModifierSnapshot MGInputModifierStateSnapshot(MGInputModifierState *state);
