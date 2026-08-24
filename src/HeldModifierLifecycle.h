// Declares modifier state held for the lifetime of one configured physical click.

#import <ApplicationServices/ApplicationServices.h>
#import "KeyEventSequence.h"

typedef struct {
    BOOL active;
    int owner;
    CGEventFlags ownedFlags;
} MGHeldModifierLifecycle;

void MGHeldModifierLifecycleInitialize(MGHeldModifierLifecycle *lifecycle);
size_t MGHeldModifierLifecycleBegin(MGHeldModifierLifecycle *lifecycle,
                                    int owner,
                                    CGEventFlags requestedFlags,
                                    CGEventFlags physicalFlags,
                                    MGKeyEventStep steps[9]);
size_t MGHeldModifierLifecycleEnd(MGHeldModifierLifecycle *lifecycle,
                                  int owner,
                                  CGEventFlags physicalFlags,
                                  MGKeyEventStep steps[9]);
size_t MGHeldModifierLifecycleCancel(MGHeldModifierLifecycle *lifecycle,
                                     CGEventFlags physicalFlags,
                                     MGKeyEventStep steps[9]);
BOOL MGHeldModifierLifecycleIsActiveForOwner(
    const MGHeldModifierLifecycle *lifecycle,
    int owner);
