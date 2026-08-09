// Owns exclusive gesture dispatch within one continuous touch sequence.

#import "GestureSequence.h"

void MGGestureSequenceInitialize(MGGestureSequence *sequence) {
    sequence->owner = 0;
    sequence->suppressNativeScroll = NO;
    sequence->scrollFamiliesResolved = 0;
}

BOOL MGGestureSequenceTryClaim(MGGestureSequence *sequence, NSUInteger owner) {
    if (owner == 0)
        return NO;
    if (sequence->owner == 0)
        sequence->owner = owner;
    return sequence->owner == owner;
}

// Suppression is decided at most once per swipe family per contact sequence, so
// the binding resolver runs only on a frame that can still change that family's
// answer. Resolving a binding costs a window-server round trip per call, which
// per-frame callers must not pay.
//
// The latch is per family because one sequence observes several. Latching the
// whole sequence on the first family to resolve would leave a hand that passes
// through three fingers on its way to four never evaluating the four-finger
// family, so suppression would never arm for it.
void MGGestureSequenceObserveBoundScrollFamily(MGGestureSequence *sequence,
                                               int activeContactCount,
                                               int requiredContactCount,
                                               BOOL (^resolveBinding)(void)) {
    if (requiredContactCount < 1 || requiredContactCount > 5)
        return;
    unsigned int family = 1u << requiredContactCount;
    if (sequence->scrollFamiliesResolved & family)
        return;
    if (activeContactCount != requiredContactCount || resolveBinding == NULL)
        return;
    sequence->scrollFamiliesResolved |= family;
    if (resolveBinding())
        sequence->suppressNativeScroll = YES;
}

BOOL MGGestureSequenceSuppressesNativeScroll(const MGGestureSequence *sequence) {
    return sequence->suppressNativeScroll;
}

void MGGestureSequenceFinishFrame(MGGestureSequence *sequence, int activeContactCount) {
    if (activeContactCount == 0)
        MGGestureSequenceInitialize(sequence);
}
