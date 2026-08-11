// Classifies a trackpad contact sequence and arbitrates among recognizers that could claim it.

#import <Foundation/Foundation.h>
#import "ContactOnsetTracker.h"
#import "GestureSequence.h"

typedef struct {
    int identifier;
    float x;
    float y;
    float majorAxis;
} MGTrackpadContact;

typedef struct {
    BOOL broadContact;
    BOOL physicalClick;
    BOOL physicalDrag;
    BOOL rawContactsObserved;
    MGGestureSequence sequence;
    int previousContactCount;
    int previousActiveContactCount;
    int currentContactCount;
    int maximumContactCount;
    int pendingClickContactCount;
    float lastContactX;
    float lastContactY;
    float pendingClickX;
    float pendingClickY;
    double physicalClickContactsLiftedAt;
    MGContactOnsetTracker rawContactOnsets;
} MGTrackpadInteraction;

void MGTrackpadInteractionInitialize(MGTrackpadInteraction *interaction);
void MGTrackpadInteractionObserveRawContacts(MGTrackpadInteraction *interaction,
                                             const MGTrackpadContact *contacts,
                                             int contactCount,
                                             double timestamp);
void MGTrackpadInteractionObserveContacts(MGTrackpadInteraction *interaction,
                                          const MGTrackpadContact *contacts,
                                          int contactCount,
                                          double timestamp);
int MGTrackpadInteractionFingertipScaleContactCount(const MGTrackpadContact *contacts,
                                                    int contactCount);
BOOL MGTrackpadInteractionContactsAreEligible(const float *majorAxes,
                                              int contactCount);
BOOL MGTrackpadInteractionContactsFormHoldTapPair(float firstX,
                                                  float firstY,
                                                  float secondX,
                                                  float secondY);
BOOL MGTrackpadInteractionContactsFormTapGroup(const MGTrackpadContact *contacts,
                                               int contactCount);
BOOL MGTrackpadInteractionFiveFingerContactsAreEligible(const float *majorAxes,
                                                        const float *ys,
                                                        int contactCount);
BOOL MGTrackpadInteractionBeginPhysicalClick(MGTrackpadInteraction *interaction,
                                             double pressure,
                                             NSUInteger owner);
BOOL MGTrackpadInteractionHasPhysicalClick(const MGTrackpadInteraction *interaction);
BOOL MGTrackpadInteractionShouldPreservePrimaryClick(const MGTrackpadInteraction *interaction,
                                                     BOOL threeFingerBindingAvailable,
                                                     BOOL fourFingerBindingAvailable);
BOOL MGTrackpadInteractionPendingSingleContactClickPosition(const MGTrackpadInteraction *interaction,
                                                            float *outX,
                                                            float *outY);
void MGTrackpadInteractionRecordPhysicalDrag(MGTrackpadInteraction *interaction);
int MGTrackpadInteractionFinishPhysicalClick(MGTrackpadInteraction *interaction);
BOOL MGTrackpadInteractionContactsArrivedWithin(const MGTrackpadInteraction *interaction,
                                                const int *identifiers, int contactCount,
                                                double maximumInterval);
BOOL MGTrackpadInteractionClaimGesture(MGTrackpadInteraction *interaction,
                                       NSUInteger owner);
BOOL MGTrackpadInteractionClaimPalmSafeGesture(MGTrackpadInteraction *interaction,
                                               NSUInteger owner);
BOOL MGTrackpadInteractionClaimTap(MGTrackpadInteraction *interaction,
                                   NSUInteger owner);
void MGTrackpadInteractionObserveBoundScrollFamily(MGTrackpadInteraction *interaction,
                                                   int activeContactCount,
                                                   int requiredContactCount,
                                                   BOOL (^resolveBinding)(void));
BOOL MGTrackpadInteractionSuppressesNativeScroll(const MGTrackpadInteraction *interaction);
void MGTrackpadInteractionFinishFrame(MGTrackpadInteraction *interaction,
                                      int activeContactCount);
void MGTrackpadInteractionExpireStalePhysicalClick(MGTrackpadInteraction *interaction,
                                                   double timestamp);
