// Declares one keystroke held for the lifetime of a configured physical click.

#import <ApplicationServices/ApplicationServices.h>
#import "HeldModifierLifecycle.h"

#define MG_HELD_KEYSTROKE_MAX_STEPS 10

typedef struct {
    BOOL active;
    int owner;
    BOOL hasKey;
    BOOL ownsKey;
    CGKeyCode keyCode;
    CGEventFlags requestedFlags;
    MGHeldModifierLifecycle modifiers;
} MGHeldKeystrokeLifecycle;

void MGHeldKeystrokeLifecycleInitialize(MGHeldKeystrokeLifecycle *lifecycle);
size_t MGHeldKeystrokeLifecycleBegin(
    MGHeldKeystrokeLifecycle *lifecycle,
    int owner,
    CGKeyCode keyCode,
    BOOL hasKey,
    CGEventFlags requestedFlags,
    CGEventFlags physicalFlags,
    BOOL physicalKeyDown,
    MGKeyEventStep steps[MG_HELD_KEYSTROKE_MAX_STEPS]);
size_t MGHeldKeystrokeLifecycleEnd(
    MGHeldKeystrokeLifecycle *lifecycle,
    int owner,
    CGEventFlags physicalFlags,
    BOOL physicalKeyDown,
    MGKeyEventStep steps[MG_HELD_KEYSTROKE_MAX_STEPS]);
size_t MGHeldKeystrokeLifecycleCancel(
    MGHeldKeystrokeLifecycle *lifecycle,
    CGEventFlags physicalFlags,
    BOOL physicalKeyDown,
    MGKeyEventStep steps[MG_HELD_KEYSTROKE_MAX_STEPS]);
BOOL MGHeldKeystrokeLifecycleIsActiveForOwner(
    const MGHeldKeystrokeLifecycle *lifecycle,
    int owner);
BOOL MGHeldKeystrokeLifecycleHeldKeyCode(
    const MGHeldKeystrokeLifecycle *lifecycle,
    CGKeyCode *keyCode);
