// Owns the held middle-button state shared by the Magic Mouse and trackpad click paths.

#import "MiddleButtonLifecycle.h"

void MGMiddleButtonLifecycleInitialize(MGMiddleButtonLifecycle *lifecycle) {
    lifecycle->held = NO;
    lifecycle->device = 0;
}

BOOL MGMiddleButtonLifecycleCommandHoldsButton(NSString *command) {
    return [command isEqualToString:@"Middle Click"];
}

BOOL MGMiddleButtonLifecycleBegin(MGMiddleButtonLifecycle *lifecycle, int device) {
    if (lifecycle->held || device == 0)
        return NO;
    lifecycle->held = YES;
    lifecycle->device = device;
    return YES;
}

BOOL MGMiddleButtonLifecycleIsHeld(const MGMiddleButtonLifecycle *lifecycle) {
    return lifecycle->held;
}

int MGMiddleButtonLifecycleHoldingDevice(const MGMiddleButtonLifecycle *lifecycle) {
    return lifecycle->held ? lifecycle->device : 0;
}

BOOL MGMiddleButtonLifecycleEnd(MGMiddleButtonLifecycle *lifecycle) {
    BOOL held = lifecycle->held;
    MGMiddleButtonLifecycleInitialize(lifecycle);
    return held;
}
