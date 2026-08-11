// Declares the small ownership primitive that keeps one touch sequence from dispatching competing gestures.

#import <Foundation/Foundation.h>

// Mirrors the CoreGraphics scroll phase fields, kept as plain values so this
// primitive stays testable without CoreGraphics.
enum {
    MGScrollPhaseNone = 0,
    MGScrollPhaseBegan = 1,
};
enum {
    MGMomentumPhaseNone = 0,
    MGMomentumPhaseEnd = 3,
};

typedef struct {
    NSUInteger owner;
    BOOL suppressNativeScroll;
    // One latch bit per required contact count, not one for the sequence. A
    // hand that reaches three fingers and continues to four must still let the
    // four-finger family resolve.
    unsigned int scrollFamiliesResolved;
    // Outlives the contacts. macOS delivers momentum events after the fingers
    // leave the device, so a sequence that suppressed the driven scroll must
    // keep suppressing its inertia.
    BOOL suppressMomentumScroll;
} MGGestureSequence;

void MGGestureSequenceInitialize(MGGestureSequence *sequence);
BOOL MGGestureSequenceTryClaim(MGGestureSequence *sequence, NSUInteger owner);
void MGGestureSequenceObserveBoundScrollFamily(MGGestureSequence *sequence,
                                               int activeContactCount,
                                               int requiredContactCount,
                                               BOOL (^resolveBinding)(void));
BOOL MGGestureSequenceSuppressesNativeScroll(const MGGestureSequence *sequence);
BOOL MGGestureSequenceSuppressesScrollEvent(MGGestureSequence *sequence,
                                            int64_t scrollPhase,
                                            int64_t momentumPhase);
void MGGestureSequenceFinishFrame(MGGestureSequence *sequence, int activeContactCount);
