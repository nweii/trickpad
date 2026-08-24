// Verifies that Fn transitions change the repetition generation while stable
// observations preserve it.

#import <Foundation/Foundation.h>
#import "InputModifierState.h"

static void fail(NSString *message) {
    NSLog(@"input modifier state: %@", message);
    exit(1);
}

int main(void) {
    @autoreleasepool {
        MGInputModifierState state;
        MGInputModifierStateInit(&state, NO);
        MGInputModifierSnapshot initial = MGInputModifierStateSnapshot(&state);
        if (initial.functionDown)
            fail(@"initial up state was lost");

        MGInputModifierStateObserveFunction(&state, NO);
        MGInputModifierSnapshot repeatedUp = MGInputModifierStateSnapshot(&state);
        if (repeatedUp.functionGeneration != initial.functionGeneration)
            fail(@"a repeated state changed the generation");

        MGInputModifierStateObserveFlagsChanged(&state, 96, YES, NO);
        MGInputModifierSnapshot functionKey = MGInputModifierStateSnapshot(&state);
        if (functionKey.functionDown ||
            functionKey.functionGeneration != initial.functionGeneration)
            fail(@"F5 was mistaken for physical Fn");

        MGInputModifierStateObserveFlagsChanged(&state, 63, YES, YES);
        MGInputModifierSnapshot syntheticDown = MGInputModifierStateSnapshot(&state);
        if (syntheticDown.functionDown ||
            syntheticDown.functionGeneration != initial.functionGeneration)
            fail(@"a synthetic Fn action changed physical input state");

        MGInputModifierStateObserveFlagsChanged(&state, 63, YES, NO);
        MGInputModifierSnapshot down = MGInputModifierStateSnapshot(&state);
        if (!down.functionDown || down.functionGeneration == initial.functionGeneration)
            fail(@"Fn down did not advance the generation");

        MGInputModifierStateObserveFunction(&state, NO);
        MGInputModifierStateObserveFunction(&state, YES);
        MGInputModifierSnapshot repressed = MGInputModifierStateSnapshot(&state);
        if (!repressed.functionDown || repressed.functionGeneration <= down.functionGeneration + 1)
            fail(@"release and re-press did not break the repetition generation");

        NSLog(@"input modifier state: all checks passed");
    }
    return 0;
}
