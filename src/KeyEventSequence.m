// Plans a complete keyboard event sequence for one configured keystroke.
// Requested modifiers already held by the user are never pressed or released.

#import "KeyEventSequence.h"
#import <Carbon/Carbon.h>
#import <IOKit/hidsystem/IOLLEvent.h>

typedef struct {
    CGKeyCode keyCode;
    CGEventFlags genericFlag;
    CGEventFlags sideFlag;
    CGEventFlags sideMask;
    CGEventFlags flags;
} MGModifier;

size_t MGPlanKeyEventSequence(CGKeyCode keyCode,
                              bool hasKey,
                              CGEventFlags requestedFlags,
                              CGEventFlags physicalFlags,
                              MGKeyEventStep steps[20]) {
    static const MGModifier modifiers[] = {
        {kVK_Function, kCGEventFlagMaskSecondaryFn, kCGEventFlagMaskSecondaryFn,
            kCGEventFlagMaskSecondaryFn, kCGEventFlagMaskSecondaryFn},
        {56, kCGEventFlagMaskShift, NX_DEVICELSHIFTKEYMASK,
            NX_DEVICELSHIFTKEYMASK | NX_DEVICERSHIFTKEYMASK,
            kCGEventFlagMaskShift | NX_DEVICELSHIFTKEYMASK},
        {60, kCGEventFlagMaskShift, NX_DEVICERSHIFTKEYMASK,
            NX_DEVICELSHIFTKEYMASK | NX_DEVICERSHIFTKEYMASK,
            kCGEventFlagMaskShift | NX_DEVICERSHIFTKEYMASK},
        {59, kCGEventFlagMaskControl, NX_DEVICELCTLKEYMASK,
            NX_DEVICELCTLKEYMASK | NX_DEVICERCTLKEYMASK,
            kCGEventFlagMaskControl | NX_DEVICELCTLKEYMASK},
        {62, kCGEventFlagMaskControl, NX_DEVICERCTLKEYMASK,
            NX_DEVICELCTLKEYMASK | NX_DEVICERCTLKEYMASK,
            kCGEventFlagMaskControl | NX_DEVICERCTLKEYMASK},
        {58, kCGEventFlagMaskAlternate, NX_DEVICELALTKEYMASK,
            NX_DEVICELALTKEYMASK | NX_DEVICERALTKEYMASK,
            kCGEventFlagMaskAlternate | NX_DEVICELALTKEYMASK},
        {61, kCGEventFlagMaskAlternate, NX_DEVICERALTKEYMASK,
            NX_DEVICELALTKEYMASK | NX_DEVICERALTKEYMASK,
            kCGEventFlagMaskAlternate | NX_DEVICERALTKEYMASK},
        {55, kCGEventFlagMaskCommand, NX_DEVICELCMDKEYMASK,
            NX_DEVICELCMDKEYMASK | NX_DEVICERCMDKEYMASK,
            kCGEventFlagMaskCommand | NX_DEVICELCMDKEYMASK},
        {54, kCGEventFlagMaskCommand, NX_DEVICERCMDKEYMASK,
            NX_DEVICELCMDKEYMASK | NX_DEVICERCMDKEYMASK,
            kCGEventFlagMaskCommand | NX_DEVICERCMDKEYMASK},
    };
    size_t count = 0;
    size_t pressed[9];
    size_t pressedCount = 0;
    CGEventFlags activeFlags = 0;

    for (size_t i = 0; i < sizeof(modifiers) / sizeof(modifiers[0]); i++) {
        MGModifier modifier = modifiers[i];
        if (!(requestedFlags & modifier.genericFlag) ||
            !(requestedFlags & modifier.sideFlag))
            continue;
        BOOL physicalSideIsUnknown = (physicalFlags & modifier.genericFlag) &&
            !(physicalFlags & modifier.sideMask);
        if ((physicalFlags & modifier.sideFlag) ||
            (physicalSideIsUnknown && (modifier.sideFlag == NX_DEVICELSHIFTKEYMASK ||
                                       modifier.sideFlag == NX_DEVICELCTLKEYMASK ||
                                       modifier.sideFlag == NX_DEVICELALTKEYMASK ||
                                       modifier.sideFlag == NX_DEVICELCMDKEYMASK))) {
            activeFlags |= modifier.flags;
            continue;
        }
        activeFlags |= modifier.flags;
        steps[count++] = (MGKeyEventStep){modifier.keyCode, true, activeFlags};
        pressed[pressedCount++] = i;
    }

    if (hasKey) {
        steps[count++] = (MGKeyEventStep){keyCode, true, requestedFlags};
        steps[count++] = (MGKeyEventStep){keyCode, false, requestedFlags};
    }

    while (pressedCount > 0) {
        MGModifier modifier = modifiers[pressed[--pressedCount]];
        activeFlags &= ~modifier.sideFlag;
        if (!(activeFlags & modifier.sideMask))
            activeFlags &= ~modifier.genericFlag;
        steps[count++] = (MGKeyEventStep){modifier.keyCode, false, activeFlags};
    }

    return count;
}
