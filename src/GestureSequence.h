// Declares the small ownership primitive that keeps one touch sequence from dispatching competing gestures.

#import <Foundation/Foundation.h>

typedef struct {
    NSUInteger owner;
    BOOL suppressNativeScroll;
    // One latch bit per required contact count, not one for the sequence. A
    // hand that reaches three fingers and continues to four must still let the
    // four-finger family resolve.
    unsigned int scrollFamiliesResolved;
} MGGestureSequence;

void MGGestureSequenceInitialize(MGGestureSequence *sequence);
BOOL MGGestureSequenceTryClaim(MGGestureSequence *sequence, NSUInteger owner);
void MGGestureSequenceObserveBoundScrollFamily(MGGestureSequence *sequence,
                                               int activeContactCount,
                                               int requiredContactCount,
                                               BOOL (^resolveBinding)(void));
BOOL MGGestureSequenceSuppressesNativeScroll(const MGGestureSequence *sequence);
void MGGestureSequenceFinishFrame(MGGestureSequence *sequence, int activeContactCount);
