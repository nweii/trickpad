// Owns exclusive gesture dispatch within one continuous touch sequence.

#import "GestureSequence.h"

void MGGestureSequenceInitialize(MGGestureSequence *sequence) {
    sequence->owner = 0;
    sequence->suppressNativeScroll = NO;
    sequence->scrollFamiliesResolved = 0;
    sequence->suppressMomentumScroll = NO;
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

// A sequence that suppressed the driven scroll hands that suppression to its
// momentum on the way out. Full lift ends the gesture, but macOS delivers the
// inertia a few milliseconds later, so lift cannot also end suppression without
// releasing that whole tail into the application.
//
// Idempotent, because lift is reported on every frame that follows it rather
// than once. Carrying an existing latch as well as a freshly earned one is what
// stops the second zero-contact frame overwriting what the first one set.
void MGGestureSequenceFinishFrame(MGGestureSequence *sequence, int activeContactCount) {
    if (activeContactCount == 0) {
        BOOL carryToMomentum = sequence->suppressNativeScroll ||
                               sequence->suppressMomentumScroll;
        MGGestureSequenceInitialize(sequence);
        sequence->suppressMomentumScroll = carryToMomentum;
    }
}

// Decides one scroll event. While contacts are down this follows the armed
// state. After full lift it keeps dropping the momentum the gesture generated,
// until that momentum ends or the user starts a new scroll.
//
// A new scroll wins over a retained latch: someone who swipes and then
// immediately scrolls for real must not have that scroll eaten. Events that
// carry neither a new scroll nor momentum, such as the zero-delta bookkeeping
// macOS emits between the two, pass through without clearing the latch.
BOOL MGGestureSequenceSuppressesScrollEvent(MGGestureSequence *sequence,
                                            int64_t scrollPhase,
                                            int64_t momentumPhase) {
    if (sequence->suppressNativeScroll)
        return YES;
    if (!sequence->suppressMomentumScroll)
        return NO;
    if (scrollPhase == MGScrollPhaseBegan) {
        sequence->suppressMomentumScroll = NO;
        return NO;
    }
    if (momentumPhase == MGMomentumPhaseNone)
        return NO;
    if (momentumPhase == MGMomentumPhaseEnd)
        sequence->suppressMomentumScroll = NO;
    return YES;
}
