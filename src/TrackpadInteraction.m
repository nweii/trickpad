// Implements shared contact-quality, physical-click, drag, claiming, and lifecycle rules for trackpad gestures.

#import "TrackpadInteraction.h"

static const float kTrackpadBroadContactMajorAxis = 10.5;
static const float kTrackpadThumbMaximumY = 0.35;
static const float kTrackpadHoldTapMinimumDistanceSquared = 0.0036;
static const float kTrackpadHoldTapMaximumDistanceSquared = 0.0625;
static const float kTrackpadPalmPatchMaximumDistanceSquared = 0.0036;
static const float kTrackpadTapGroupMaximumDistanceSquared = 0.16;
static const float kTrackpadTapGroupThumbMaximumDistanceSquared = 0.4225;
static const float kTrackpadTapGroupThumbMaximumY = 0.35;
static const double kTrackpadPhysicalClickReleaseGrace = 0.5;

static BOOL contactsContainPalmPatchCluster(const MGTrackpadContact *contacts,
                                            int contactCount) {
    for (int i = 0; i < contactCount; i++) {
        for (int j = i + 1; j < contactCount; j++) {
            float dx = contacts[i].x - contacts[j].x;
            float dy = contacts[i].y - contacts[j].y;
            if (dx * dx + dy * dy <= kTrackpadPalmPatchMaximumDistanceSquared)
                return YES;
        }
    }
    return NO;
}

// Counts contacts at fingertip scale, so a resting palm inflates no
// finger-count decision that reads this instead of the raw count.
int MGTrackpadInteractionFingertipScaleContactCount(const MGTrackpadContact *contacts,
                                                    int contactCount) {
    int fingertips = 0;
    for (int i = 0; i < contactCount; i++) {
        if (contacts[i].majorAxis <= kTrackpadBroadContactMajorAxis)
            fingertips++;
    }
    return fingertips;
}

BOOL MGTrackpadInteractionContactsAreEligible(const float *majorAxes,
                                              int contactCount) {
    for (int i = 0; i < contactCount; i++) {
        if (majorAxes[i] > kTrackpadBroadContactMajorAxis)
            return NO;
    }
    return YES;
}

BOOL MGTrackpadInteractionContactsFormHoldTapPair(float firstX,
                                                  float firstY,
                                                  float secondX,
                                                  float secondY) {
    float dx = firstX - secondX;
    float dy = firstY - secondY;
    float distanceSquared = dx * dx + dy * dy;
    return distanceSquared > kTrackpadHoldTapMinimumDistanceSquared &&
           distanceSquared <= kTrackpadHoldTapMaximumDistanceSquared;
}

BOOL MGTrackpadInteractionContactsFormTapGroup(const MGTrackpadContact *contacts,
                                               int contactCount) {
    int thumbCount = 0;
    for (int i = 0; i < contactCount; i++) {
        if (contacts[i].y <= kTrackpadTapGroupThumbMaximumY)
            thumbCount++;
    }
    if (thumbCount > 1)
        return NO;

    for (int i = 0; i < contactCount; i++) {
        for (int j = i + 1; j < contactCount; j++) {
            float dx = contacts[i].x - contacts[j].x;
            float dy = contacts[i].y - contacts[j].y;
            BOOL includesThumb = contacts[i].y <= kTrackpadTapGroupThumbMaximumY ||
                contacts[j].y <= kTrackpadTapGroupThumbMaximumY;
            float maximumDistanceSquared = includesThumb
                ? kTrackpadTapGroupThumbMaximumDistanceSquared
                : kTrackpadTapGroupMaximumDistanceSquared;
            if (dx * dx + dy * dy > maximumDistanceSquared)
                return NO;
        }
    }
    return YES;
}

BOOL MGTrackpadInteractionFiveFingerContactsAreEligible(const float *majorAxes,
                                                        const float *ys,
                                                        int contactCount) {
    int broadContactCount = 0;
    for (int i = 0; i < contactCount; i++) {
        if (majorAxes[i] > kTrackpadBroadContactMajorAxis) {
            broadContactCount++;
            if (broadContactCount > 1 || ys[i] > kTrackpadThumbMaximumY)
                return NO;
        }
    }
    return YES;
}

// Everything the interaction owns itself, leaving the sequence alone. Split out
// because a full lift resets these fields while the sequence keeps state that
// deliberately outlives the contacts.
static void resetInteractionFields(MGTrackpadInteraction *interaction) {
    interaction->broadContact = NO;
    interaction->physicalClick = NO;
    interaction->physicalDrag = NO;
    interaction->rawContactsObserved = NO;
    interaction->previousContactCount = 0;
    interaction->previousActiveContactCount = 0;
    interaction->currentContactCount = 0;
    interaction->maximumContactCount = 0;
    interaction->pendingClickContactCount = 0;
    interaction->lastContactX = 0;
    interaction->lastContactY = 0;
    interaction->pendingClickX = 0;
    interaction->pendingClickY = 0;
    interaction->physicalClickContactsLiftedAt = -1;
    interaction->rawContactOnsets = (MGContactOnsetTracker){0};
}

void MGTrackpadInteractionInitialize(MGTrackpadInteraction *interaction) {
    resetInteractionFields(interaction);
    MGGestureSequenceInitialize(&interaction->sequence);
}

void MGTrackpadInteractionObserveRawContacts(MGTrackpadInteraction *interaction,
                                             const MGTrackpadContact *contacts,
                                             int contactCount,
                                             double timestamp) {
    if (interaction->previousActiveContactCount == 0 && contactCount > 0)
        MGTrackpadInteractionInitialize(interaction);

    interaction->rawContactsObserved = YES;
    int identifiers[16];
    int limitedCount = MIN(contactCount, 16);
    for (int i = 0; i < limitedCount; i++)
        identifiers[i] = contacts[i].identifier;
    MGContactOnsetTrackerObserve(&interaction->rawContactOnsets, identifiers,
                                 limitedCount, timestamp);
    if (contactsContainPalmPatchCluster(contacts, contactCount))
        interaction->broadContact = YES;
    for (int i = 0; i < contactCount; i++) {
        if (contacts[i].majorAxis > kTrackpadBroadContactMajorAxis)
            interaction->broadContact = YES;
    }
}

void MGTrackpadInteractionObserveContacts(MGTrackpadInteraction *interaction,
                                          const MGTrackpadContact *contacts,
                                          int contactCount,
                                          double timestamp) {
    BOOL rawContactsObserved = interaction->rawContactsObserved;
    if (!rawContactsObserved && interaction->previousActiveContactCount == 0 && contactCount > 0) {
        MGTrackpadInteractionInitialize(interaction);
        rawContactsObserved = NO;
    }
    if (contactCount > interaction->maximumContactCount)
        interaction->maximumContactCount = contactCount;

    if (!rawContactsObserved) {
        for (int i = 0; i < contactCount; i++) {
            if (contacts[i].majorAxis > kTrackpadBroadContactMajorAxis)
                interaction->broadContact = YES;
        }
    }
    if (contactCount > 0) {
        interaction->lastContactX = contacts[0].x;
        interaction->lastContactY = contacts[0].y;
    }
    interaction->previousContactCount = contactCount;
    interaction->currentContactCount = contactCount;
    interaction->rawContactsObserved = NO;
}

BOOL MGTrackpadInteractionBeginPhysicalClick(MGTrackpadInteraction *interaction,
                                             double pressure,
                                             NSUInteger owner) {
    if (interaction->currentContactCount <= 0 || pressure <= 0 || interaction->broadContact ||
        !MGGestureSequenceTryClaim(&interaction->sequence, owner))
        return NO;

    interaction->physicalClick = YES;
    interaction->physicalDrag = NO;
    interaction->physicalClickContactsLiftedAt = -1;
    interaction->pendingClickContactCount = MAX(interaction->currentContactCount,
                                                 interaction->maximumContactCount);
    interaction->pendingClickX = interaction->lastContactX;
    interaction->pendingClickY = interaction->lastContactY;
    return YES;
}

// Reports the normalized position of a physical click whose whole contact
// sequence has held one contact, the shape an area-click recognizer needs.
BOOL MGTrackpadInteractionPendingSingleContactClickPosition(const MGTrackpadInteraction *interaction,
                                                            float *outX,
                                                            float *outY) {
    if (!interaction->physicalClick || interaction->pendingClickContactCount != 1)
        return NO;
    *outX = interaction->pendingClickX;
    *outY = interaction->pendingClickY;
    return YES;
}

BOOL MGTrackpadInteractionHasPhysicalClick(const MGTrackpadInteraction *interaction) {
    return interaction->physicalClick;
}

BOOL MGTrackpadInteractionShouldPreservePrimaryClick(const MGTrackpadInteraction *interaction,
                                                     BOOL threeFingerBindingAvailable,
                                                     BOOL fourFingerBindingAvailable) {
    return interaction->physicalClick &&
        ((interaction->pendingClickContactCount == 3 && threeFingerBindingAvailable) ||
         (interaction->pendingClickContactCount == 4 && fourFingerBindingAvailable));
}

void MGTrackpadInteractionRecordPhysicalDrag(MGTrackpadInteraction *interaction) {
    if (interaction->physicalClick)
        interaction->physicalDrag = YES;
}

int MGTrackpadInteractionFinishPhysicalClick(MGTrackpadInteraction *interaction) {
    int contactCount = interaction->physicalClick && !interaction->physicalDrag
        ? interaction->pendingClickContactCount
        : 0;
    BOOL contactsAlreadyLifted = interaction->previousActiveContactCount == 0;
    interaction->physicalClick = NO;
    interaction->physicalDrag = NO;
    interaction->maximumContactCount = interaction->currentContactCount;
    interaction->pendingClickContactCount = 0;
    if (contactsAlreadyLifted)
        MGTrackpadInteractionInitialize(interaction);
    return contactCount;
}

BOOL MGTrackpadInteractionContactsArrivedWithin(const MGTrackpadInteraction *interaction,
                                                const int *identifiers, int contactCount,
                                                double maximumInterval) {
    return MGContactOnsetTrackerContactsArrivedWithin(&interaction->rawContactOnsets,
                                                      identifiers, contactCount,
                                                      maximumInterval);
}

BOOL MGTrackpadInteractionClaimGesture(MGTrackpadInteraction *interaction,
                                       NSUInteger owner) {
    return MGGestureSequenceTryClaim(&interaction->sequence, owner);
}

BOOL MGTrackpadInteractionClaimPalmSafeGesture(MGTrackpadInteraction *interaction,
                                               NSUInteger owner) {
    if (interaction->broadContact || interaction->physicalClick)
        return NO;
    return MGTrackpadInteractionClaimGesture(interaction, owner);
}

BOOL MGTrackpadInteractionClaimTap(MGTrackpadInteraction *interaction,
                                   NSUInteger owner) {
    return MGTrackpadInteractionClaimPalmSafeGesture(interaction, owner);
}

void MGTrackpadInteractionObserveBoundScrollFamily(MGTrackpadInteraction *interaction,
                                                   int activeContactCount,
                                                   int requiredContactCount,
                                                   BOOL (^resolveBinding)(void)) {
    MGGestureSequenceObserveBoundScrollFamily(&interaction->sequence,
                                              activeContactCount,
                                              requiredContactCount,
                                              resolveBinding);
}

BOOL MGTrackpadInteractionSuppressesNativeScroll(const MGTrackpadInteraction *interaction) {
    return MGGestureSequenceSuppressesNativeScroll(&interaction->sequence);
}

BOOL MGTrackpadInteractionSuppressesScrollEvent(MGTrackpadInteraction *interaction,
                                                int64_t scrollPhase,
                                                int64_t momentumPhase) {
    return MGGestureSequenceSuppressesScrollEvent(&interaction->sequence,
                                                  scrollPhase,
                                                  momentumPhase);
}

void MGTrackpadInteractionFinishFrame(MGTrackpadInteraction *interaction,
                                      int activeContactCount) {
    interaction->previousActiveContactCount = activeContactCount;
    if (activeContactCount == 0 && !interaction->physicalClick &&
        interaction->pendingClickContactCount == 0) {
        // The interaction's own fields reset here, but what survives a lift is
        // the sequence's business, so that transition is delegated rather than
        // repeated. Doing both by hand is how the momentum latch got cleared a
        // frame after it was set.
        resetInteractionFields(interaction);
        MGGestureSequenceFinishFrame(&interaction->sequence, 0);
    }
}

void MGTrackpadInteractionExpireStalePhysicalClick(MGTrackpadInteraction *interaction,
                                                   double timestamp) {
    if (!interaction->physicalClick || interaction->previousActiveContactCount > 0) {
        interaction->physicalClickContactsLiftedAt = -1;
        return;
    }
    if (interaction->physicalClickContactsLiftedAt < 0) {
        interaction->physicalClickContactsLiftedAt = timestamp;
        return;
    }
    if (timestamp - interaction->physicalClickContactsLiftedAt >=
        kTrackpadPhysicalClickReleaseGrace) {
        MGTrackpadInteractionInitialize(interaction);
    }
}
