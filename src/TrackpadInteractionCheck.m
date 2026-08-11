// Checks trackpad tap classification and arbitration against intentional and palm-contact sequences.

#import <Foundation/Foundation.h>

#import "TrackpadInteraction.h"

static void require(BOOL condition, NSString *message) {
    if (!condition) {
        NSLog(@"%@", message);
        exit(1);
    }
}

int main(void) {
    @autoreleasepool {
        MGTrackpadInteraction interaction;
        MGTrackpadInteractionInitialize(&interaction);

        float fingertip[] = {8.95};
        MGTrackpadContact oneFinger[] = {{1, 0.30, 0.60, 8.95}};
        MGTrackpadContact threeFingers[] = {
            {1, 0.30, 0.60, 8.95},
            {2, 0.50, 0.60, 8.72},
            {3, 0.70, 0.60, 8.51},
        };
        MGTrackpadInteractionObserveRawContacts(&interaction, oneFinger, 1, 1.000);
        MGTrackpadInteractionObserveContacts(&interaction, oneFinger, 1, 1.000);
        MGTrackpadInteractionFinishFrame(&interaction, 1);
        float fingertips[] = {8.95, 8.72, 8.51};
        MGTrackpadInteractionObserveRawContacts(&interaction, threeFingers, 3, 1.008);
        MGTrackpadInteractionObserveContacts(&interaction, threeFingers, 3, 1.008);
        int threeFingerIdentifiers[] = {1, 2, 3};
        require(MGTrackpadInteractionContactsArrivedWithin(
                    &interaction, threeFingerIdentifiers, 3, 0.05),
                @"intentional three-finger arrival was rejected");
        require(MGTrackpadInteractionClaimGesture(&interaction, 1), @"intentional tap could not claim sequence");
        require(!MGTrackpadInteractionClaimGesture(&interaction, 2), @"two gestures claimed one sequence");
        MGTrackpadInteractionFinishFrame(&interaction, 0);

        MGTrackpadInteractionObserveRawContacts(&interaction, oneFinger, 1, 1.100);
        MGTrackpadInteractionObserveContacts(&interaction, oneFinger, 1, 1.100);
        MGTrackpadInteractionFinishFrame(&interaction, 1);
        MGTrackpadInteractionObserveRawContacts(&interaction, threeFingers, 3, 1.160);
        MGTrackpadInteractionObserveContacts(&interaction, threeFingers, 3, 1.160);
        require(!MGTrackpadInteractionContactsArrivedWithin(
                    &interaction, threeFingerIdentifiers, 3, 0.05),
                @"resting trackpad contact and later fingers were accepted as simultaneous");
        MGTrackpadInteractionFinishFrame(&interaction, 0);

        float palms[] = {17.62, 18.27, 14.68};
        require(MGTrackpadInteractionContactsAreEligible(fingertips, 3),
                @"ordinary fingertips were classified as broad contacts");
        require(!MGTrackpadInteractionContactsAreEligible(palms, 3),
                @"broad palm contacts were classified as eligible");
        require(MGTrackpadInteractionContactsFormHoldTapPair(0.30, 0.60, 0.50, 0.60),
                @"adjacent fingertips were rejected as a hold-tap pair");
        require(!MGTrackpadInteractionContactsFormHoldTapPair(0.30, 0.60, 0.35, 0.60),
                @"two patches from one palm were accepted as a hold-tap pair");
        require(!MGTrackpadInteractionContactsFormHoldTapPair(0.30, 0.60, 0.70, 0.60),
                @"widely separated contacts were accepted as a hold-tap pair");
        MGTrackpadContact ordinaryTapGroup[] = {
            {1, 0.30, 0.60, 8.40},
            {2, 0.46, 0.62, 8.20},
            {3, 0.62, 0.60, 8.30},
        };
        require(MGTrackpadInteractionContactsFormTapGroup(ordinaryTapGroup, 3),
                @"normally spaced fingertips were rejected as a tap group");
        MGTrackpadContact spreadTapGroup[] = {
            {1, 0.10, 0.65, 8.40},
            {2, 0.50, 0.65, 8.20},
            {3, 0.90, 0.65, 8.30},
        };
        require(!MGTrackpadInteractionContactsFormTapGroup(spreadTapGroup, 3),
                @"widely separated contacts were accepted as a tap group");
        MGTrackpadContact thumbTapGroup[] = {
            {1, 0.18, 0.24, 9.20},
            {2, 0.48, 0.65, 8.20},
            {3, 0.63, 0.65, 8.30},
        };
        require(MGTrackpadInteractionContactsFormTapGroup(thumbTapGroup, 3),
                @"one natural thumb contact was rejected by fingertip spacing");
        MGTrackpadContact palmPatches[] = {
            {1, 0.30, 0.60, 8.40},
            {2, 0.35, 0.60, 8.20},
        };
        MGTrackpadInteractionObserveRawContacts(&interaction, palmPatches, 2, 1.500);
        MGTrackpadInteractionObserveContacts(&interaction, palmPatches, 2, 1.500);
        require(!MGTrackpadInteractionClaimTap(&interaction, 1),
                @"clustered fingertip-sized palm patches claimed a tap");
        MGTrackpadInteractionFinishFrame(&interaction, 0);
        MGTrackpadContact normalTwoFingerTap[] = {
            {1, 0.30, 0.60, 8.40},
            {2, 0.42, 0.60, 8.20},
        };
        MGTrackpadInteractionObserveRawContacts(&interaction, normalTwoFingerTap, 2, 1.700);
        MGTrackpadInteractionObserveContacts(&interaction, normalTwoFingerTap, 2, 1.700);
        require(MGTrackpadInteractionClaimTap(&interaction, 1),
                @"normally spaced fingertips were rejected as palm patches");
        MGTrackpadInteractionFinishFrame(&interaction, 0);
        float fiveFingerAxes[] = {15.63, 8.63, 7.55, 7.72, 7.39};
        float fiveFingerYs[] = {0.2774, 0.7786, 0.7832, 0.7079, 0.5340};
        require(MGTrackpadInteractionFiveFingerContactsAreEligible(
                    fiveFingerAxes, fiveFingerYs, 5),
                @"measured five-finger tap thumb was classified as a palm");
        fiveFingerYs[0] = 0.60;
        require(!MGTrackpadInteractionFiveFingerContactsAreEligible(
                    fiveFingerAxes, fiveFingerYs, 5),
                @"broad central contact was classified as a thumb");
        fiveFingerYs[0] = 0.2774;
        fiveFingerAxes[1] = 14.0;
        require(!MGTrackpadInteractionFiveFingerContactsAreEligible(
                    fiveFingerAxes, fiveFingerYs, 5),
                @"two broad contacts were classified as a five-finger tap");
        MGTrackpadContact palmContacts[] = {
            {1, 0.30, 0.60, 17.62},
            {2, 0.50, 0.60, 18.27},
            {3, 0.70, 0.60, 14.68},
        };
        MGTrackpadInteractionObserveContacts(&interaction, palmContacts, 3, 2.000);
        require(!MGTrackpadInteractionClaimTap(&interaction, 1), @"broad palm contacts claimed a tap");
        require(!MGTrackpadInteractionBeginPhysicalClick(&interaction, 1.0, 2),
                @"broad palm contacts claimed a physical click");
        require(MGTrackpadInteractionClaimGesture(&interaction, 3),
                @"palm eligibility blocked a non-tap gesture from owning the sequence");
        MGTrackpadInteractionFinishFrame(&interaction, 0);

        MGTrackpadInteractionObserveRawContacts(&interaction, palmContacts, 3, 2.500);
        MGTrackpadInteractionObserveContacts(&interaction, NULL, 0, 2.500);
        require(!MGTrackpadInteractionClaimTap(&interaction, 1),
                @"a palm removed by contact filtering claimed a hold-tap");
        MGTrackpadInteractionFinishFrame(&interaction, 0);

        MGTrackpadInteractionObserveContacts(&interaction, oneFinger, 1, 3.000);
        MGTrackpadInteractionFinishFrame(&interaction, 1);
        MGTrackpadInteractionObserveContacts(&interaction, threeFingers, 3, 3.010);
        require(MGTrackpadInteractionBeginPhysicalClick(&interaction, 1.0, 2),
                @"physical click could not claim an idle sequence");
        require(MGTrackpadInteractionShouldPreservePrimaryClick(&interaction, YES, NO),
                @"configured three-finger click allowed native secondary-click classification");
        require(!MGTrackpadInteractionShouldPreservePrimaryClick(&interaction, NO, YES),
                @"three-finger click borrowed the four-finger binding");
        require(!MGTrackpadInteractionShouldPreservePrimaryClick(&interaction, NO, NO),
                @"unbound physical click changed native click behavior");
        require(!MGTrackpadInteractionClaimGesture(&interaction, 1),
                @"physical click also claimed a tap gesture");
        require(MGTrackpadInteractionFinishPhysicalClick(&interaction) == 3,
                @"stationary physical click did not finish with its contact count");
        MGTrackpadInteractionFinishFrame(&interaction, 0);

        MGTrackpadInteractionObserveContacts(&interaction, threeFingers, 3, 4.000);
        require(MGTrackpadInteractionClaimGesture(&interaction, 1), @"full lift did not reset interaction");

        MGTrackpadContact fourFingers[] = {
            {1, 0.30, 0.60, 8.95},
            {2, 0.50, 0.60, 8.72},
            {3, 0.70, 0.60, 8.51},
            {4, 0.85, 0.60, 8.30},
        };
        MGTrackpadInteractionFinishFrame(&interaction, 0);
        MGTrackpadInteractionObserveContacts(&interaction, fourFingers, 4, 5.000);
        MGTrackpadInteractionFinishFrame(&interaction, 4);
        MGTrackpadInteractionObserveContacts(&interaction, threeFingers, 3, 5.010);
        require(MGTrackpadInteractionBeginPhysicalClick(&interaction, 1.0, 2),
                @"click classification forgot a briefly missing fourth contact");
        require(MGTrackpadInteractionFinishPhysicalClick(&interaction) == 4,
                @"click finish forgot a briefly missing fourth contact");
        MGTrackpadInteractionObserveContacts(&interaction, threeFingers, 3, 5.020);
        require(MGTrackpadInteractionBeginPhysicalClick(&interaction, 1.0, 2),
                @"the next three-finger click inherited the previous four-finger peak");
        require(MGTrackpadInteractionFinishPhysicalClick(&interaction) == 3,
                @"the next three-finger click finished with the previous four-finger peak");

        MGTrackpadInteractionFinishFrame(&interaction, 0);
        MGTrackpadInteractionObserveContacts(&interaction, threeFingers, 3, 6.000);
        require(MGTrackpadInteractionClaimGesture(&interaction, 3),
                @"swipe could not claim an idle sequence");
        require(!MGTrackpadInteractionBeginPhysicalClick(&interaction, 1.0, 2),
                @"physical click displaced the gesture that already owned the sequence");

        MGTrackpadInteractionFinishFrame(&interaction, 0);
        MGTrackpadInteractionObserveContacts(&interaction, threeFingers, 3, 6.500);
        MGTrackpadInteractionFinishFrame(&interaction, 4);
        require(MGTrackpadInteractionBeginPhysicalClick(&interaction, 1.0, 2),
                @"filtered click contacts were rejected by a larger raw count");
        require(MGTrackpadInteractionFinishPhysicalClick(&interaction) == 3,
                @"raw contact count promoted a filtered three-finger click");

        MGTrackpadInteractionFinishFrame(&interaction, 0);
        MGTrackpadInteractionObserveContacts(&interaction, threeFingers, 3, 7.000);
        require(MGTrackpadInteractionBeginPhysicalClick(&interaction, 1.0, 2),
                @"stationary start could not begin a physical click");
        MGTrackpadInteractionRecordPhysicalDrag(&interaction);
        require(MGTrackpadInteractionFinishPhysicalClick(&interaction) == 0,
                @"three-finger drag was classified as a physical click");

        MGTrackpadInteractionFinishFrame(&interaction, 0);
        MGTrackpadInteractionObserveContacts(&interaction, threeFingers, 3, 8.000);
        require(!MGTrackpadInteractionBeginPhysicalClick(&interaction, 0.0, 2),
                @"zero-pressure event was classified as a physical click");

        MGTrackpadInteractionFinishFrame(&interaction, 0);
        MGTrackpadInteractionObserveContacts(&interaction, threeFingers, 3, 9.000);
        MGTrackpadInteractionFinishFrame(&interaction, 3);
        require(MGTrackpadInteractionBeginPhysicalClick(&interaction, 1.0, 2),
                @"finger placement before pressing rejected a physical click");
        require(MGTrackpadInteractionFinishPhysicalClick(&interaction) == 3,
                @"finger placement before pressing canceled a stationary click");

        MGTrackpadInteractionFinishFrame(&interaction, 0);
        MGTrackpadInteractionObserveContacts(&interaction, threeFingers, 3, 9.500);
        require(MGTrackpadInteractionBeginPhysicalClick(&interaction, 1.0, 2),
                @"physical click could not begin before contacts lifted");
        MGTrackpadInteractionFinishFrame(&interaction, 0);
        require(MGTrackpadInteractionFinishPhysicalClick(&interaction) == 3,
                @"contact lift before mouse-up lost the physical click result");
        require(MGTrackpadInteractionClaimGesture(&interaction, 4),
                @"contact lift before mouse-up left stale click ownership");

        MGTrackpadInteractionFinishFrame(&interaction, 0);
        MGTrackpadInteractionObserveContacts(&interaction, threeFingers, 3, 9.750);
        require(MGTrackpadInteractionBeginPhysicalClick(&interaction, 1.0, 2),
                @"physical click could not begin before a lost mouse-up");
        MGTrackpadInteractionFinishFrame(&interaction, 0);
        require(MGTrackpadInteractionHasPhysicalClick(&interaction),
                @"one empty frame discarded a click before mouse-up arrived");
        MGTrackpadInteractionFinishFrame(&interaction, 0);
        require(MGTrackpadInteractionHasPhysicalClick(&interaction),
                @"two empty contact frames discarded a click before mouse-up arrived");
        MGTrackpadInteractionExpireStalePhysicalClick(&interaction, 9.800);
        MGTrackpadInteractionExpireStalePhysicalClick(&interaction, 10.290);
        require(MGTrackpadInteractionHasPhysicalClick(&interaction),
                @"physical click expired before the mouse-up grace period elapsed");
        MGTrackpadInteractionExpireStalePhysicalClick(&interaction, 10.310);
        require(!MGTrackpadInteractionHasPhysicalClick(&interaction) &&
                MGTrackpadInteractionClaimGesture(&interaction, 4),
                @"a lost mouse-up left trackpad ownership stuck after its grace period");

        MGTrackpadInteractionFinishFrame(&interaction, 0);
        MGTrackpadInteractionObserveContacts(&interaction, threeFingers, 3, 10.000);
        require(MGTrackpadInteractionClaimGesture(&interaction, 3),
                @"gesture could not claim the sequence before filtered contacts disappeared");
        MGTrackpadInteractionObserveContacts(&interaction, NULL, 0, 10.010);
        MGTrackpadInteractionFinishFrame(&interaction, 1);
        require(!MGTrackpadInteractionClaimGesture(&interaction, 4),
                @"filtered zero contacts manufactured a sequence reset");
        MGTrackpadInteractionFinishFrame(&interaction, 0);
        require(MGTrackpadInteractionClaimGesture(&interaction, 4),
                @"raw full lift did not reset trackpad ownership");

        MGTrackpadInteractionFinishFrame(&interaction, 0);
        // Two fingertips plus a palm-scale heel count as two, so a resting
        // palm cannot arm three-finger scroll suppression at scroll start.
        MGTrackpadContact palmScroll[3] = {
            {1, 0.51f, 0.52f, 7.4f},
            {2, 0.42f, 0.39f, 7.9f},
            {3, 0.96f, 0.06f, 15.0f},
        };
        require(MGTrackpadInteractionFingertipScaleContactCount(palmScroll, 3) == 2,
                @"palm-scale contact counted toward the swipe family's fingertips");
        MGTrackpadInteractionObserveBoundScrollFamily(
            &interaction, MGTrackpadInteractionFingertipScaleContactCount(palmScroll, 3),
            3, ^BOOL{ return YES; });
        require(!MGTrackpadInteractionSuppressesNativeScroll(&interaction),
                @"two fingertips plus a resting palm armed scroll suppression");
        MGTrackpadInteractionObserveBoundScrollFamily(&interaction, 3, 3, ^BOOL{ return YES; });
        require(MGTrackpadInteractionSuppressesNativeScroll(&interaction),
                @"bound trackpad swipe family did not suppress native scrolling");
        // Full lift resets this whole interaction, not just its sequence, so
        // the momentum latch has to survive that reset. The mouse reaches the
        // sequence's own lift path; the trackpad does not.
        require(MGTrackpadInteractionSuppressesScrollEvent(&interaction, 2, 0),
                @"a driven trackpad scroll survived an armed swipe family");
        // The trackpad keeps delivering zero-contact frames after a lift, which
        // is how this reset runs repeatedly. Each repeat must leave the carried
        // latch alone.
        MGTrackpadInteractionFinishFrame(&interaction, 0);
        MGTrackpadInteractionFinishFrame(&interaction, 0);
        MGTrackpadInteractionFinishFrame(&interaction, 0);
        require(MGTrackpadInteractionSuppressesScrollEvent(&interaction, 0, 1),
                @"trackpad momentum was delivered after the full-lift reset");
        require(MGTrackpadInteractionSuppressesScrollEvent(&interaction, 0, 3),
                @"the final trackpad momentum event was delivered");
        require(!MGTrackpadInteractionSuppressesScrollEvent(&interaction, 0, 2),
                @"trackpad suppression outlived the momentum that ended it");
        MGTrackpadInteractionFinishFrame(&interaction, 0);
        MGTrackpadInteractionObserveBoundScrollFamily(&interaction, 3, 3, ^BOOL{ return YES; });
        MGTrackpadInteractionFinishFrame(&interaction, 2);
        require(MGTrackpadInteractionSuppressesNativeScroll(&interaction),
                @"trackpad contact dropout leaked native scrolling before full lift");
        MGTrackpadInteractionFinishFrame(&interaction, 0);
        require(!MGTrackpadInteractionSuppressesNativeScroll(&interaction),
                @"trackpad scrolling remained suppressed after full lift");

        NSLog(@"trackpad interaction: all checks passed");
    }
    return 0;
}
