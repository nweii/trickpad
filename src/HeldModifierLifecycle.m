// Plans modifier transitions held between a physical click's down and up edges.

#import "HeldModifierLifecycle.h"
#import <Carbon/Carbon.h>
#import <IOKit/hidsystem/IOLLEvent.h>

typedef struct {
    CGKeyCode keyCode;
    CGEventFlags genericFlag;
    CGEventFlags sideFlag;
    CGEventFlags sideMask;
    CGEventFlags flags;
    BOOL isLeftSide;
} MGHeldModifier;

static const MGHeldModifier kHeldModifiers[] = {
    {kVK_Function, kCGEventFlagMaskSecondaryFn, kCGEventFlagMaskSecondaryFn,
        kCGEventFlagMaskSecondaryFn, kCGEventFlagMaskSecondaryFn, NO},
    {56, kCGEventFlagMaskShift, NX_DEVICELSHIFTKEYMASK,
        NX_DEVICELSHIFTKEYMASK | NX_DEVICERSHIFTKEYMASK,
        kCGEventFlagMaskShift | NX_DEVICELSHIFTKEYMASK, YES},
    {60, kCGEventFlagMaskShift, NX_DEVICERSHIFTKEYMASK,
        NX_DEVICELSHIFTKEYMASK | NX_DEVICERSHIFTKEYMASK,
        kCGEventFlagMaskShift | NX_DEVICERSHIFTKEYMASK, NO},
    {59, kCGEventFlagMaskControl, NX_DEVICELCTLKEYMASK,
        NX_DEVICELCTLKEYMASK | NX_DEVICERCTLKEYMASK,
        kCGEventFlagMaskControl | NX_DEVICELCTLKEYMASK, YES},
    {62, kCGEventFlagMaskControl, NX_DEVICERCTLKEYMASK,
        NX_DEVICELCTLKEYMASK | NX_DEVICERCTLKEYMASK,
        kCGEventFlagMaskControl | NX_DEVICERCTLKEYMASK, NO},
    {58, kCGEventFlagMaskAlternate, NX_DEVICELALTKEYMASK,
        NX_DEVICELALTKEYMASK | NX_DEVICERALTKEYMASK,
        kCGEventFlagMaskAlternate | NX_DEVICELALTKEYMASK, YES},
    {61, kCGEventFlagMaskAlternate, NX_DEVICERALTKEYMASK,
        NX_DEVICELALTKEYMASK | NX_DEVICERALTKEYMASK,
        kCGEventFlagMaskAlternate | NX_DEVICERALTKEYMASK, NO},
    {55, kCGEventFlagMaskCommand, NX_DEVICELCMDKEYMASK,
        NX_DEVICELCMDKEYMASK | NX_DEVICERCMDKEYMASK,
        kCGEventFlagMaskCommand | NX_DEVICELCMDKEYMASK, YES},
    {54, kCGEventFlagMaskCommand, NX_DEVICERCMDKEYMASK,
        NX_DEVICELCMDKEYMASK | NX_DEVICERCMDKEYMASK,
        kCGEventFlagMaskCommand | NX_DEVICERCMDKEYMASK, NO},
};

static BOOL modifierIsRequested(MGHeldModifier modifier,
                                CGEventFlags requestedFlags) {
    return (requestedFlags & modifier.genericFlag) &&
        (requestedFlags & modifier.sideFlag);
}

static BOOL modifierIsPhysicallyHeld(MGHeldModifier modifier,
                                     CGEventFlags physicalFlags) {
    if (physicalFlags & modifier.sideFlag)
        return YES;
    BOOL physicalSideIsUnknown = (physicalFlags & modifier.genericFlag) &&
        !(physicalFlags & modifier.sideMask);
    return physicalSideIsUnknown && modifier.isLeftSide;
}

void MGHeldModifierLifecycleInitialize(MGHeldModifierLifecycle *lifecycle) {
    lifecycle->active = NO;
    lifecycle->owner = 0;
    lifecycle->ownedFlags = 0;
}

size_t MGHeldModifierLifecycleBegin(MGHeldModifierLifecycle *lifecycle,
                                    int owner,
                                    CGEventFlags requestedFlags,
                                    CGEventFlags physicalFlags,
                                    MGKeyEventStep steps[9]) {
    if (lifecycle->active || owner == 0 || requestedFlags == 0)
        return 0;

    BOOL hasRequestedModifier = NO;
    for (size_t i = 0; i < sizeof(kHeldModifiers) / sizeof(kHeldModifiers[0]); i++) {
        if (modifierIsRequested(kHeldModifiers[i], requestedFlags)) {
            hasRequestedModifier = YES;
            break;
        }
    }
    if (!hasRequestedModifier)
        return 0;

    lifecycle->active = YES;
    lifecycle->owner = owner;
    size_t count = 0;
    for (size_t i = 0; i < sizeof(kHeldModifiers) / sizeof(kHeldModifiers[0]); i++) {
        MGHeldModifier modifier = kHeldModifiers[i];
        if (!modifierIsRequested(modifier, requestedFlags) ||
            modifierIsPhysicallyHeld(modifier, physicalFlags))
            continue;
        lifecycle->ownedFlags |= modifier.flags;
        steps[count++] = (MGKeyEventStep){
            modifier.keyCode, true, physicalFlags | lifecycle->ownedFlags};
    }
    return count;
}

size_t MGHeldModifierLifecycleEnd(MGHeldModifierLifecycle *lifecycle,
                                  int owner,
                                  CGEventFlags physicalFlags,
                                  MGKeyEventStep steps[9]) {
    if (!lifecycle->active || lifecycle->owner != owner)
        return 0;
    size_t count = 0;
    CGEventFlags remainingOwnedFlags = lifecycle->ownedFlags;
    for (size_t i = sizeof(kHeldModifiers) / sizeof(kHeldModifiers[0]); i > 0; i--) {
        MGHeldModifier modifier = kHeldModifiers[i - 1];
        if (!(remainingOwnedFlags & modifier.sideFlag))
            continue;
        remainingOwnedFlags &= ~modifier.sideFlag;
        if (!(remainingOwnedFlags & modifier.sideMask))
            remainingOwnedFlags &= ~modifier.genericFlag;
        if (!modifierIsPhysicallyHeld(modifier, physicalFlags)) {
            steps[count++] = (MGKeyEventStep){
                modifier.keyCode, false,
                physicalFlags | remainingOwnedFlags};
        }
    }
    MGHeldModifierLifecycleInitialize(lifecycle);
    return count;
}

size_t MGHeldModifierLifecycleCancel(MGHeldModifierLifecycle *lifecycle,
                                     CGEventFlags physicalFlags,
                                     MGKeyEventStep steps[9]) {
    return lifecycle->active
        ? MGHeldModifierLifecycleEnd(lifecycle, lifecycle->owner,
                                     physicalFlags, steps)
        : 0;
}

BOOL MGHeldModifierLifecycleIsActiveForOwner(
    const MGHeldModifierLifecycle *lifecycle,
    int owner) {
    return lifecycle->active && lifecycle->owner == owner;
}
