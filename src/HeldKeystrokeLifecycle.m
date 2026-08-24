// Holds one configured regular key between a physical click's down and up edges.

#import "HeldKeystrokeLifecycle.h"

void MGHeldKeystrokeLifecycleInitialize(MGHeldKeystrokeLifecycle *lifecycle) {
    lifecycle->active = NO;
    lifecycle->owner = 0;
    lifecycle->hasKey = NO;
    lifecycle->ownsKey = NO;
    lifecycle->keyCode = 0;
    lifecycle->requestedFlags = 0;
    MGHeldModifierLifecycleInitialize(&lifecycle->modifiers);
}

size_t MGHeldKeystrokeLifecycleBegin(
    MGHeldKeystrokeLifecycle *lifecycle,
    int owner,
    CGKeyCode keyCode,
    BOOL hasKey,
    CGEventFlags requestedFlags,
    CGEventFlags physicalFlags,
    BOOL physicalKeyDown,
    MGKeyEventStep steps[MG_HELD_KEYSTROKE_MAX_STEPS]) {
    if (lifecycle->active || owner == 0 || (!hasKey && requestedFlags == 0))
        return 0;
    lifecycle->active = YES;
    lifecycle->owner = owner;
    lifecycle->hasKey = hasKey;
    lifecycle->ownsKey = hasKey && !physicalKeyDown;
    lifecycle->keyCode = keyCode;
    lifecycle->requestedFlags = requestedFlags;
    size_t count = requestedFlags == 0 ? 0 :
        MGHeldModifierLifecycleBegin(
            &lifecycle->modifiers, owner, requestedFlags, physicalFlags, steps);
    if (lifecycle->ownsKey) {
        CGEventFlags keyFlags = requestedFlags != 0
            ? requestedFlags : physicalFlags;
        steps[count++] = (MGKeyEventStep){keyCode, true, keyFlags};
    }
    return count;
}

size_t MGHeldKeystrokeLifecycleEnd(
    MGHeldKeystrokeLifecycle *lifecycle,
    int owner,
    CGEventFlags physicalFlags,
    BOOL physicalKeyDown,
    MGKeyEventStep steps[MG_HELD_KEYSTROKE_MAX_STEPS]) {
    if (!lifecycle->active || lifecycle->owner != owner)
        return 0;
    size_t count = 0;
    if (lifecycle->ownsKey && !physicalKeyDown) {
        CGEventFlags keyFlags = lifecycle->requestedFlags != 0
            ? lifecycle->requestedFlags : physicalFlags;
        steps[count++] = (MGKeyEventStep){
            lifecycle->keyCode, false, keyFlags};
    }
    count += MGHeldModifierLifecycleEnd(
        &lifecycle->modifiers, owner, physicalFlags, steps + count);
    MGHeldKeystrokeLifecycleInitialize(lifecycle);
    return count;
}

size_t MGHeldKeystrokeLifecycleCancel(
    MGHeldKeystrokeLifecycle *lifecycle,
    CGEventFlags physicalFlags,
    BOOL physicalKeyDown,
    MGKeyEventStep steps[MG_HELD_KEYSTROKE_MAX_STEPS]) {
    return lifecycle->active
        ? MGHeldKeystrokeLifecycleEnd(
            lifecycle, lifecycle->owner, physicalFlags, physicalKeyDown, steps)
        : 0;
}

BOOL MGHeldKeystrokeLifecycleIsActiveForOwner(
    const MGHeldKeystrokeLifecycle *lifecycle,
    int owner) {
    return lifecycle->active && lifecycle->owner == owner;
}

BOOL MGHeldKeystrokeLifecycleHeldKeyCode(
    const MGHeldKeystrokeLifecycle *lifecycle,
    CGKeyCode *keyCode) {
    if (!lifecycle->active || !lifecycle->hasKey)
        return NO;
    if (keyCode != NULL)
        *keyCode = lifecycle->keyCode;
    return YES;
}
