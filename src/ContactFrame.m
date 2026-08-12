// Builds one owned contact snapshot per hardware frame without changing the callback's input buffer.

#import "ContactFrame.h"

#import "MouseContactFilter.h"

#include <math.h>

#define px normalized.pos.x
#define py normalized.pos.y

static const float kTrackpadEdgeInset = 0.10f;
static const float kTrackpadEdgeSeparation = 0.25f;
static const float kTrackpadThumbMaximumY = 0.10f;
static const float kTrackpadThumbMinimumElongation = 5.5f;
static const float kTrackpadThumbMinimumSeparation = 0.40f;
static const float kTrackpadFingertipMaximumMajorAxis = 10.5f;
static const float kMagicMousePalmMinimumSize = 5.5f;

static MGContactList copyContacts(const Finger *contacts, int contactCount) {
    MGContactList list = {NULL, MAX(contactCount, 0)};
    if (list.count > 0) {
        Finger *copy = malloc(sizeof(Finger) * list.count);
        memcpy(copy, contacts, sizeof(Finger) * list.count);
        list.contacts = copy;
    }
    return list;
}

static BOOL contactIsActive(const Finger *contact) {
    return contact->state == MTTouchStateMakeTouch ||
        contact->state == MTTouchStateTouching ||
        contact->state == MTTouchStateBreakTouch;
}

static void mirrorContactsForLeftHand(MGContactList list, BOOL leftHanded) {
    if (!leftHanded)
        return;
    Finger *contacts = (Finger *)list.contacts;
    for (int i = 0; i < list.count; i++)
        contacts[i].px = 1.0f - contacts[i].px;
}

static MGContactList trackpadRawContacts(
    const Finger *contacts, int contactCount,
    MGContactFrameFilterObserver observer, void *context) {
    MGContactList list = copyContacts(contacts, contactCount);
    Finger *filtered = (Finger *)list.contacts;
    for (int i = 0; i < list.count; i++) {
        if (!contactIsActive(&filtered[i])) {
            if (observer)
                observer(&filtered[i], @"inactive-state", NO, context);
            filtered[i--] = filtered[--list.count];
        }
    }
    return list;
}

static MGContactList trackpadThumbFilteredContacts(
    MGTrackpadContactFrameBuilder *builder, const Finger *contacts,
    int contactCount, int hardwareContactCount, BOOL leftHanded,
    MGContactFrameFilterObserver observer, void *context) {
    MGContactList list = copyContacts(contacts, contactCount);
    Finger *filtered = (Finger *)list.contacts;
    if (hardwareContactCount == 0)
        builder->thumbIdentifier = -1;

    int edgeCount = 0;
    int edgeIndex = -1;
    float nearestInteriorX = leftHanded ? 0.0f : 1.0f;
    for (int i = 0; i < list.count; i++) {
        if (leftHanded) {
            if (filtered[i].px > 1.0f - kTrackpadEdgeInset) {
                edgeCount++;
                edgeIndex = i;
            } else if (filtered[i].px > nearestInteriorX) {
                nearestInteriorX = filtered[i].px;
            }
        } else {
            if (filtered[i].px < kTrackpadEdgeInset) {
                edgeCount++;
                edgeIndex = i;
            } else if (filtered[i].px < nearestInteriorX) {
                nearestInteriorX = filtered[i].px;
            }
        }
    }
    if (edgeCount == 1 && list.count > 1 &&
        fabsf(nearestInteriorX - filtered[edgeIndex].px) >=
            kTrackpadEdgeSeparation) {
        if (observer)
            observer(&filtered[edgeIndex], @"side-edge", NO, context);
        filtered[edgeIndex] = filtered[--list.count];
    }

    if (builder->thumbIdentifier != -1) {
        BOOL foundThumb = NO;
        for (int i = 0; i < list.count; i++) {
            if (filtered[i].identifier == builder->thumbIdentifier) {
                if (observer)
                    observer(&filtered[i], @"thumb-id", NO, context);
                filtered[i] = filtered[--list.count];
                foundThumb = YES;
                break;
            }
        }
        if (!foundThumb)
            builder->thumbIdentifier = -1;
    } else {
        int candidateCount = 0;
        int candidateIndex = -1;
        float nextLowestY = 1.0f;
        for (int i = 0; i < list.count; i++) {
            if (filtered[i].py < kTrackpadThumbMaximumY ||
                filtered[i].majorAxis - filtered[i].minorAxis >=
                    kTrackpadThumbMinimumElongation) {
                candidateCount++;
                candidateIndex = i;
            } else if (filtered[i].py < nextLowestY) {
                nextLowestY = filtered[i].py;
            }
        }
        if (candidateCount == 1 && list.count > 1 &&
            nextLowestY - filtered[candidateIndex].py >=
                kTrackpadThumbMinimumSeparation) {
            builder->thumbIdentifier = filtered[candidateIndex].identifier;
            if (observer)
                observer(&filtered[candidateIndex], @"thumb-candidate", NO,
                         context);
            filtered[candidateIndex] = filtered[--list.count];
        }
    }

    mirrorContactsForLeftHand(list, leftHanded);
    return list;
}

static MGContactList fingertipScaleTrackpadContacts(MGContactList source) {
    MGContactList result = copyContacts(source.contacts, source.count);
    Finger *contacts = (Finger *)result.contacts;
    int destination = 0;
    for (int i = 0; i < source.count; i++) {
        if (source.contacts[i].majorAxis <= kTrackpadFingertipMaximumMajorAxis)
            contacts[destination++] = source.contacts[i];
    }
    result.count = destination;
    return result;
}

static int magicMouseThumbIndex(const MGContactList contacts) {
    if (contacts.count == 0)
        return -1;
    int lowestIndex = 0;
    for (int i = 1; i < contacts.count; i++) {
        if (contacts.contacts[i].py < contacts.contacts[lowestIndex].py)
            lowestIndex = i;
    }
    float nextLowestY = 1.0f;
    for (int i = 0; i < contacts.count; i++) {
        if (i != lowestIndex && contacts.contacts[i].py < nextLowestY)
            nextLowestY = contacts.contacts[i].py;
    }
    return MGMagicMouseLowestContactIsThumb(
        contacts.contacts[lowestIndex].px, contacts.contacts[lowestIndex].py,
        nextLowestY, contacts.count) ? lowestIndex : -1;
}

static MGContactList fingertipScaleMagicMouseContacts(MGContactList source) {
    MGContactList result = copyContacts(source.contacts, source.count);
    Finger *contacts = (Finger *)result.contacts;
    int destination = 0;
    for (int i = 0; i < source.count; i++) {
        if (source.contacts[i].size <= kMagicMousePalmMinimumSize)
            contacts[destination++] = source.contacts[i];
    }
    result.count = destination;
    return result;
}

void MGTrackpadContactFrameBuilderInitialize(MGTrackpadContactFrameBuilder *builder) {
    builder->thumbIdentifier = -1;
}

MGContactFrame MGTrackpadContactFrameCreate(MGTrackpadContactFrameBuilder *builder,
                                            const Finger *contacts,
                                            int contactCount,
                                            BOOL leftHanded) {
    return MGTrackpadContactFrameCreateObserved(builder, contacts, contactCount,
                                                leftHanded, NULL, NULL);
}

MGContactFrame MGTrackpadContactFrameCreateObserved(
    MGTrackpadContactFrameBuilder *builder, const Finger *contacts,
    int contactCount, BOOL leftHanded, MGContactFrameFilterObserver observer,
    void *context) {
    MGContactFrame frame = {0};
    frame.hardware = copyContacts(contacts, contactCount);
    frame.raw = trackpadRawContacts(contacts, contactCount, observer, context);
    frame.thumbFiltered = trackpadThumbFilteredContacts(
        builder, frame.raw.contacts, frame.raw.count, contactCount, leftHanded,
        observer, context);
    frame.fingertipScale = fingertipScaleTrackpadContacts(frame.thumbFiltered);
    return frame;
}

MGContactFrame MGMagicMouseContactFrameCreate(const Finger *contacts,
                                              int contactCount,
                                              BOOL leftHanded) {
    MGContactFrame frame = {0};
    frame.hardware = copyContacts(contacts, contactCount);
    frame.raw = copyContacts(contacts, contactCount);
    mirrorContactsForLeftHand(frame.raw, leftHanded);
    int thumbIndex = magicMouseThumbIndex(frame.raw);

    frame.thumbFiltered = copyContacts(frame.raw.contacts, frame.raw.count);
    frame.fingertipScale = (MGContactList){0};
    Finger *filteredContacts = (Finger *)frame.thumbFiltered.contacts;
    int filteredDestination = 0;
    for (int i = 0; i < frame.raw.count; i++) {
        if (i == thumbIndex)
            continue;
        Finger candidate = frame.raw.contacts[i];
        if (!MGMagicMouseContactShouldBeExcluded(candidate.px, candidate.py,
                                                  candidate.size,
                                                  candidate.minorAxis))
            filteredContacts[filteredDestination++] = candidate;
    }
    frame.thumbFiltered.count = filteredDestination;
    frame.fingertipScale = fingertipScaleMagicMouseContacts(frame.thumbFiltered);
    return frame;
}

void MGContactFrameDestroy(MGContactFrame *frame) {
    free((void *)frame->hardware.contacts);
    free((void *)frame->raw.contacts);
    free((void *)frame->thumbFiltered.contacts);
    free((void *)frame->fingertipScale.contacts);
    *frame = (MGContactFrame){0};
}
