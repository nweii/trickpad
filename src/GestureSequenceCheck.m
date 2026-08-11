// Checks that competing gestures cannot claim the same touch sequence and that lift permits the next gesture.

#import <Foundation/Foundation.h>

#import "GestureSequence.h"

static void require(BOOL condition, NSString *message) {
    if (!condition) {
        NSLog(@"%@", message);
        exit(1);
    }
}

int main(void) {
    @autoreleasepool {
        MGGestureSequence sequence;
        MGGestureSequenceInitialize(&sequence);

        require(MGGestureSequenceTryClaim(&sequence, 1), @"first gesture could not claim sequence");
        require(MGGestureSequenceTryClaim(&sequence, 1), @"owning gesture could not repeat");
        require(!MGGestureSequenceTryClaim(&sequence, 2), @"competing gesture claimed the same sequence");

        MGGestureSequenceFinishFrame(&sequence, 1);
        require(!MGGestureSequenceTryClaim(&sequence, 2),
                @"a filtered contact manufactured a full lift");

        MGGestureSequenceFinishFrame(&sequence, 0);
        require(MGGestureSequenceTryClaim(&sequence, 2),
                @"raw full lift did not release sequence ownership");

        __block int resolveCount = 0;
        BOOL (^boundResolver)(void) = ^BOOL{ resolveCount++; return YES; };
        BOOL (^unboundResolver)(void) = ^BOOL{ resolveCount++; return NO; };

        MGGestureSequenceInitialize(&sequence);
        MGGestureSequenceObserveBoundScrollFamily(&sequence, 2, 3, boundResolver);
        require(resolveCount == 0,
                @"the binding resolver ran on a frame below the required contact count");
        MGGestureSequenceObserveBoundScrollFamily(&sequence, 3, 3, boundResolver);
        require(MGGestureSequenceSuppressesNativeScroll(&sequence),
                @"a bound three-contact swipe family did not suppress native scrolling");
        require(resolveCount == 1, @"the binding resolver did not run when the third contact arrived");
        MGGestureSequenceObserveBoundScrollFamily(&sequence, 3, 3, boundResolver);
        require(resolveCount == 1, @"the binding resolver ran more than once in one contact sequence");
        MGGestureSequenceObserveBoundScrollFamily(&sequence, 2, 3, boundResolver);
        require(MGGestureSequenceSuppressesNativeScroll(&sequence),
                @"a brief contact dropout leaked native scrolling before full lift");
        MGGestureSequenceFinishFrame(&sequence, 0);
        require(!MGGestureSequenceSuppressesNativeScroll(&sequence),
                @"native scrolling remained suppressed after full lift");

        resolveCount = 0;
        MGGestureSequenceInitialize(&sequence);
        MGGestureSequenceObserveBoundScrollFamily(&sequence, 3, 3, unboundResolver);
        require(!MGGestureSequenceSuppressesNativeScroll(&sequence),
                @"an unbound swipe family suppressed native scrolling");
        MGGestureSequenceObserveBoundScrollFamily(&sequence, 3, 3, unboundResolver);
        require(resolveCount == 1,
                @"an unbound swipe family re-ran the binding resolver every frame");
        MGGestureSequenceFinishFrame(&sequence, 0);
        MGGestureSequenceObserveBoundScrollFamily(&sequence, 3, 3, unboundResolver);
        require(resolveCount == 2,
                @"a new contact sequence did not re-resolve the binding");

        // A hand that passes through the lower family's count on its way to the
        // higher one must still let the higher family resolve. A single latch
        // for the whole sequence passes every check above and fails this one.
        __block int lowerResolves = 0;
        __block int higherResolves = 0;
        BOOL (^lowerUnbound)(void) = ^BOOL{ lowerResolves++; return NO; };
        BOOL (^higherBound)(void) = ^BOOL{ higherResolves++; return YES; };

        lowerResolves = higherResolves = 0;
        MGGestureSequenceInitialize(&sequence);
        MGGestureSequenceObserveBoundScrollFamily(&sequence, 3, 3, lowerUnbound);
        MGGestureSequenceObserveBoundScrollFamily(&sequence, 3, 4, higherBound);
        require(lowerResolves == 1 && higherResolves == 0,
                @"three contacts resolved the four-contact swipe family");
        MGGestureSequenceObserveBoundScrollFamily(&sequence, 4, 3, lowerUnbound);
        MGGestureSequenceObserveBoundScrollFamily(&sequence, 4, 4, higherBound);
        require(higherResolves == 1,
                @"a fourth contact never resolved the four-contact swipe family");
        require(MGGestureSequenceSuppressesNativeScroll(&sequence),
                @"a bound four-contact swipe family did not suppress native scrolling "
                 "after passing through three contacts");
        require(lowerResolves == 1,
                @"the three-contact swipe family re-ran its resolver in one sequence");

        // The Magic Mouse mirror: it scrolls with one finger, so its families
        // are two and three rather than three and four.
        lowerResolves = higherResolves = 0;
        MGGestureSequenceInitialize(&sequence);
        MGGestureSequenceObserveBoundScrollFamily(&sequence, 2, 2, lowerUnbound);
        MGGestureSequenceObserveBoundScrollFamily(&sequence, 2, 3, higherBound);
        require(lowerResolves == 1 && higherResolves == 0,
                @"two contacts resolved the three-contact swipe family");
        MGGestureSequenceObserveBoundScrollFamily(&sequence, 3, 2, lowerUnbound);
        MGGestureSequenceObserveBoundScrollFamily(&sequence, 3, 3, higherBound);
        require(higherResolves == 1 && MGGestureSequenceSuppressesNativeScroll(&sequence),
                @"a bound three-contact mouse swipe family did not arm after two contacts");

        // Every family latch clears on full lift, not just the one that armed.
        MGGestureSequenceFinishFrame(&sequence, 0);
        MGGestureSequenceObserveBoundScrollFamily(&sequence, 2, 2, lowerUnbound);
        MGGestureSequenceObserveBoundScrollFamily(&sequence, 3, 3, higherBound);
        require(lowerResolves == 2 && higherResolves == 2,
                @"a full lift did not clear every swipe family latch");

        // Replays the event order captured from a real three-finger swipe:
        // arm, drop the driven scroll, full lift, then momentum beginning about
        // four milliseconds later. Releasing suppression at lift delivers the
        // whole inertia tail, which is what the user sees as the page moving.
        MGGestureSequenceInitialize(&sequence);
        MGGestureSequenceObserveBoundScrollFamily(&sequence, 3, 3, ^BOOL{ return YES; });
        require(MGGestureSequenceSuppressesScrollEvent(&sequence, 1, 0),
                @"a driven scroll survived an armed swipe family");
        require(MGGestureSequenceSuppressesScrollEvent(&sequence, 2, 0),
                @"a driven scroll update survived an armed swipe family");
        MGGestureSequenceFinishFrame(&sequence, 0);
        require(!MGGestureSequenceSuppressesNativeScroll(&sequence),
                @"full lift did not end contact-driven suppression");
        // Lift is reported on every following frame, so the transition must be
        // idempotent. A second zero-contact frame reads a sequence that is
        // already reset, and must not write that over the carried latch.
        MGGestureSequenceFinishFrame(&sequence, 0);
        MGGestureSequenceFinishFrame(&sequence, 0);
        require(MGGestureSequenceSuppressesScrollEvent(&sequence, 0, 1),
                @"momentum began after full lift and was delivered");
        require(MGGestureSequenceSuppressesScrollEvent(&sequence, 0, 2),
                @"momentum continued after full lift and was delivered");
        // macOS interleaves a zero-delta MayBegin event during the tail. It
        // carries no momentum phase and must not be read as a new scroll.
        require(!MGGestureSequenceSuppressesScrollEvent(&sequence, 128, 0),
                @"a zero-delta bookkeeping event was dropped");
        require(MGGestureSequenceSuppressesScrollEvent(&sequence, 0, 2),
                @"bookkeeping between momentum events cleared the momentum latch");
        require(MGGestureSequenceSuppressesScrollEvent(&sequence, 0, 3),
                @"the final momentum event was delivered");
        require(!MGGestureSequenceSuppressesScrollEvent(&sequence, 0, 2),
                @"suppression outlived the momentum that ended it");

        // A real scroll started right after a swipe belongs to the user.
        MGGestureSequenceInitialize(&sequence);
        MGGestureSequenceObserveBoundScrollFamily(&sequence, 3, 3, ^BOOL{ return YES; });
        MGGestureSequenceFinishFrame(&sequence, 0);
        require(!MGGestureSequenceSuppressesScrollEvent(&sequence, 1, 0),
                @"a new scroll after a swipe was eaten by the momentum latch");
        require(!MGGestureSequenceSuppressesScrollEvent(&sequence, 0, 2),
                @"a new scroll did not clear the momentum latch");

        // An unarmed sequence has no momentum to hold onto.
        MGGestureSequenceInitialize(&sequence);
        MGGestureSequenceObserveBoundScrollFamily(&sequence, 3, 3, ^BOOL{ return NO; });
        MGGestureSequenceFinishFrame(&sequence, 0);
        require(!MGGestureSequenceSuppressesScrollEvent(&sequence, 0, 1),
                @"an unbound swipe family suppressed momentum");

        MGGestureSequenceInitialize(&sequence);
        require(MGGestureSequenceTryClaim(&sequence, 2), @"full lift did not release sequence ownership");

        NSLog(@"gesture sequence: all checks passed");
    }
    return 0;
}
