// Replays trace fixture geometry and checks that contact-frame views preserve the callback's established derivations.

#import <Foundation/Foundation.h>

#import "ContactFrame.h"
#import "MouseContactFilter.h"

#define px normalized.pos.x
#define py normalized.pos.y

static void require(BOOL condition, NSString *message) {
    if (!condition) {
        fprintf(stderr, "FAIL  %s\n", [message UTF8String]);
        exit(1);
    }
}

static Finger contact(int identifier, int state, float x, float y,
                      float size, float majorAxis, float minorAxis) {
    Finger result = {0};
    result.identifier = identifier;
    result.state = state;
    result.px = x;
    result.py = y;
    result.size = size;
    result.majorAxis = majorAxis;
    result.minorAxis = minorAxis;
    return result;
}

static void requireIdentifiers(MGContactList list, const int *identifiers,
                               int count, NSString *message) {
    require(list.count == count, message);
    for (int i = 0; i < count; i++)
        require(list.contacts[i].identifier == identifiers[i], message);
}

static void requireSameList(MGContactList actual, MGContactList expected,
                            NSString *message) {
    require(actual.count == expected.count, message);
    for (int i = 0; i < expected.count; i++)
        require(actual.contacts[i].identifier == expected.contacts[i].identifier,
                message);
}

static BOOL contactIsActive(Finger contact) {
    return contact.state == MTTouchStateMakeTouch ||
        contact.state == MTTouchStateTouching ||
        contact.state == MTTouchStateBreakTouch;
}

static MGContactList legacyTrackpadRawContacts(MGContactList hardware) {
    MGContactList result = {NULL, hardware.count};
    if (result.count > 0) {
        result.contacts = calloc(result.count, sizeof(Finger));
        memcpy((void *)result.contacts, hardware.contacts,
               result.count * sizeof(Finger));
    }
    Finger *contacts = (Finger *)result.contacts;
    for (int i = 0; i < result.count; i++) {
        if (!contactIsActive(contacts[i]))
            contacts[i--] = contacts[--result.count];
    }
    return result;
}

static MGContactList legacyTrackpadThumbFilteredContacts(
    MGContactList raw, int *thumbIdentifier, BOOL leftHanded) {
    MGContactList result = {NULL, raw.count};
    if (result.count > 0) {
        result.contacts = calloc(result.count, sizeof(Finger));
        memcpy((void *)result.contacts, raw.contacts,
               result.count * sizeof(Finger));
    }
    Finger *contacts = (Finger *)result.contacts;

    int edgeCount = 0;
    int edgeIndex = -1;
    float nearestInteriorX = leftHanded ? 0.0f : 1.0f;
    for (int i = 0; i < result.count; i++) {
        if ((leftHanded && contacts[i].px > 0.9f) ||
            (!leftHanded && contacts[i].px < 0.1f)) {
            edgeCount++;
            edgeIndex = i;
        } else if ((leftHanded && contacts[i].px > nearestInteriorX) ||
                   (!leftHanded && contacts[i].px < nearestInteriorX)) {
            nearestInteriorX = contacts[i].px;
        }
    }
    if (edgeCount == 1 && result.count > 1 &&
        fabsf(nearestInteriorX - contacts[edgeIndex].px) >= 0.25f)
        contacts[edgeIndex] = contacts[--result.count];

    if (*thumbIdentifier != -1) {
        BOOL foundThumb = NO;
        for (int i = 0; i < result.count; i++) {
            if (contacts[i].identifier == *thumbIdentifier) {
                contacts[i] = contacts[--result.count];
                foundThumb = YES;
                break;
            }
        }
        if (!foundThumb)
            *thumbIdentifier = -1;
    } else {
        int candidateCount = 0;
        int candidateIndex = -1;
        float nextLowestY = 1.0f;
        for (int i = 0; i < result.count; i++) {
            if (contacts[i].py < 0.1f ||
                contacts[i].majorAxis - contacts[i].minorAxis >= 5.5f) {
                candidateCount++;
                candidateIndex = i;
            } else if (contacts[i].py < nextLowestY) {
                nextLowestY = contacts[i].py;
            }
        }
        if (candidateCount == 1 && result.count > 1 &&
            nextLowestY - contacts[candidateIndex].py >= 0.4f) {
            *thumbIdentifier = contacts[candidateIndex].identifier;
            contacts[candidateIndex] = contacts[--result.count];
        }
    }

    if (leftHanded) {
        for (int i = 0; i < result.count; i++)
            contacts[i].px = 1.0f - contacts[i].px;
    }
    return result;
}

static MGContactList legacyMouseFilteredContacts(MGContactList raw) {
    MGContactList result = {NULL, 0};
    if (raw.count > 0)
        result.contacts = calloc(raw.count, sizeof(Finger));
    Finger *filtered = (Finger *)result.contacts;
    int thumbIndex = -1;
    if (raw.count > 0) {
        int lowest = 0;
        for (int i = 1; i < raw.count; i++)
            if (raw.contacts[i].py < raw.contacts[lowest].py)
                lowest = i;
        float nextLowestY = 1.0f;
        for (int i = 0; i < raw.count; i++)
            if (i != lowest && raw.contacts[i].py < nextLowestY)
                nextLowestY = raw.contacts[i].py;
        if (MGMagicMouseLowestContactIsThumb(raw.contacts[lowest].px,
                                             raw.contacts[lowest].py,
                                             nextLowestY, raw.count))
            thumbIndex = lowest;
    }
    for (int i = 0; i < raw.count; i++) {
        Finger candidate = raw.contacts[i];
        if (i != thumbIndex && !MGMagicMouseContactShouldBeExcluded(
                candidate.px, candidate.py, candidate.size, candidate.minorAxis))
            filtered[result.count++] = candidate;
    }
    return result;
}

static MGContactList legacyFingertipScaleContacts(MGContactList raw,
                                                  BOOL mouse) {
    MGContactList result = {NULL, 0};
    if (raw.count > 0)
        result.contacts = calloc(raw.count, sizeof(Finger));
    Finger *fingertips = (Finger *)result.contacts;
    for (int i = 0; i < raw.count; i++) {
        BOOL fingertip = mouse ? raw.contacts[i].size <= 5.5f
                               : raw.contacts[i].majorAxis <= 10.5f;
        if (fingertip)
            fingertips[result.count++] = raw.contacts[i];
    }
    return result;
}

static NSArray *frameEventsAtPath(NSString *path) {
    NSString *contents = [NSString stringWithContentsOfFile:path
                                                   encoding:NSUTF8StringEncoding
                                                      error:nil];
    require(contents != nil, [NSString stringWithFormat:@"could not read %@", path]);
    NSMutableArray *events = [NSMutableArray array];
    [contents enumerateLinesUsingBlock:^(NSString *line, BOOL *stop) {
        (void)stop;
        NSDictionary *event = [NSJSONSerialization JSONObjectWithData:
            [line dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
        if ([[event objectForKey:@"event"] isEqualToString:@"frame"])
            [events addObject:event];
    }];
    return events;
}

static MGContactList contactsFromEvent(NSDictionary *event) {
    NSArray *values = [[event objectForKey:@"data"] objectForKey:@"contacts"];
    MGContactList list = {NULL, (int)[values count]};
    if (list.count > 0)
        list.contacts = calloc(list.count, sizeof(Finger));
    Finger *contacts = (Finger *)list.contacts;
    for (int i = 0; i < list.count; i++) {
        NSDictionary *value = [values objectAtIndex:i];
        contacts[i] = contact([[value objectForKey:@"id"] intValue],
            [[value objectForKey:@"state"] intValue],
            [[value objectForKey:@"x"] floatValue], [[value objectForKey:@"y"] floatValue],
            [[value objectForKey:@"size"] floatValue], [[value objectForKey:@"major"] floatValue],
            [[value objectForKey:@"minor"] floatValue]);
    }
    return list;
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        require(argc > 1, @"at least one trace fixture is required");

        Finger trackpad[] = {
            contact(1, MTTouchStateTouching, 0.35, 0.70, 1.0, 8.0, 6.0),
            contact(2, MTTouchStateHoverInRange, 0.50, 0.70, 1.0, 8.0, 6.0),
            contact(3, MTTouchStateTouching, 0.02, 0.65, 1.0, 8.0, 6.0),
            contact(4, MTTouchStateTouching, 0.65, 0.65, 1.0, 12.0, 8.0),
        };
        MGTrackpadContactFrameBuilder trackpadBuilder;
        MGTrackpadContactFrameBuilderInitialize(&trackpadBuilder);
        MGContactFrame trackpadFrame = MGTrackpadContactFrameCreate(
            &trackpadBuilder, trackpad, 4, NO);
        const int rawIdentifiers[] = {1, 4, 3};
        const int trackpadFilteredIdentifiers[] = {1, 4};
        const int fingertipIdentifiers[] = {1};
        requireIdentifiers(trackpadFrame.raw, rawIdentifiers, 3,
                           @"trackpad raw view retained an inactive contact");
        requireIdentifiers(trackpadFrame.thumbFiltered,
                           trackpadFilteredIdentifiers, 2,
                           @"trackpad filtered view retained hover or edge contacts");
        requireIdentifiers(trackpadFrame.fingertipScale, fingertipIdentifiers, 1,
                           @"trackpad fingertip-scale view retained hover or palm-scale contacts");
        MGContactFrameDestroy(&trackpadFrame);

        Finger fiveFingerEdge[] = {
            contact(20, MTTouchStateTouching, 0.02, 0.55, 1.0, 8.0, 6.0),
            contact(21, MTTouchStateTouching, 0.30, 0.55, 1.0, 8.0, 6.0),
            contact(22, MTTouchStateTouching, 0.42, 0.55, 1.0, 8.0, 6.0),
            contact(23, MTTouchStateTouching, 0.54, 0.55, 1.0, 8.0, 6.0),
            contact(24, MTTouchStateTouching, 0.66, 0.55, 1.0, 8.0, 6.0),
        };
        MGTrackpadContactFrameBuilderInitialize(&trackpadBuilder);
        trackpadFrame = MGTrackpadContactFrameCreate(
            &trackpadBuilder, fiveFingerEdge, 5, NO);
        require(trackpadFrame.raw.count == 5,
                @"trackpad raw view removed a five-finger tap contact");
        require(trackpadFrame.thumbFiltered.count == 4,
                @"trackpad thumb-filtered view retained the side-edge contact");
        MGContactFrameDestroy(&trackpadFrame);

        Finger leftTrackpad[] = {
            contact(30, MTTouchStateTouching, 0.20, 0.55, 1.0, 8.0, 6.0),
            contact(31, MTTouchStateTouching, 0.70, 0.55, 1.0, 8.0, 6.0),
        };
        MGTrackpadContactFrameBuilderInitialize(&trackpadBuilder);
        trackpadFrame = MGTrackpadContactFrameCreate(
            &trackpadBuilder, leftTrackpad, 2, YES);
        require(fabsf(trackpadFrame.raw.contacts[0].px - 0.20f) < 0.0001f,
                @"trackpad raw view changed the physical x coordinate");
        require(fabsf(trackpadFrame.thumbFiltered.contacts[0].px - 0.80f) < 0.0001f,
                @"trackpad thumb-filtered view did not mirror recognizer x");
        MGContactFrameDestroy(&trackpadFrame);

        Finger mouse[] = {
            contact(10, MTTouchStateTouching, 0.35, 0.70, 1.5, 8.0, 8.0),
            contact(11, MTTouchStateTouching, 0.96, 0.66, 0.875, 8.0, 6.58),
        };
        MGContactFrame mouseFrame = MGMagicMouseContactFrameCreate(mouse, 2, NO);
        const int mouseFilteredIdentifiers[] = {10};
        requireIdentifiers(mouseFrame.thumbFiltered, mouseFilteredIdentifiers, 1,
                           @"Magic Mouse filtered view retained a measured resting-edge contact");
        requireIdentifiers(mouseFrame.fingertipScale,
                           mouseFilteredIdentifiers, 1,
                           @"Magic Mouse fingertip-scale view diverged from the filtered recognizer input");
        MGContactFrameDestroy(&mouseFrame);

        Finger leftMouse[] = {
            contact(12, MTTouchStateTouching, 0.90, 0.20, 1.5, 8.0, 8.0),
            contact(13, MTTouchStateTouching, 0.40, 0.70, 1.5, 8.0, 8.0),
        };
        mouseFrame = MGMagicMouseContactFrameCreate(leftMouse, 2, YES);
        require(fabsf(mouseFrame.raw.contacts[0].px - 0.10f) < 0.0001f,
                @"Magic Mouse raw view did not mirror left-handed geometry");
        const int leftMouseFilteredIdentifiers[] = {13};
        requireIdentifiers(mouseFrame.thumbFiltered,
                           leftMouseFilteredIdentifiers, 1,
                           @"Magic Mouse left-handed thumb was not filtered");
        MGContactFrameDestroy(&mouseFrame);

        Finger thumbStable[] = {
            contact(40, MTTouchStateTouching, 0.10, 0.20, 1.5, 8.0, 8.0),
            contact(41, MTTouchStateTouching, 0.40, 0.70, 1.5, 8.0, 8.0),
            contact(42, MTTouchStateTouching, 0.70, 0.75, 1.5, 8.0, 8.0),
        };
        mouseFrame = MGMagicMouseContactFrameCreate(thumbStable, 3, NO);
        require(mouseFrame.thumbFiltered.count == 2,
                @"synthetic thumb frame did not establish a thumb");
        MGContactFrameDestroy(&mouseFrame);

        Finger thumbFlicker[] = {
            contact(40, MTTouchStateTouching, 0.16, 0.30, 1.5, 8.0, 8.0),
            contact(41, MTTouchStateTouching, 0.40, 0.70, 1.5, 8.0, 8.0),
            contact(42, MTTouchStateTouching, 0.70, 0.75, 1.5, 8.0, 8.0),
        };
        mouseFrame = MGMagicMouseContactFrameCreate(thumbFlicker, 3, NO);
        require(mouseFrame.thumbFiltered.count == 3,
                @"synthetic frame did not reproduce one-frame thumb flicker");
        int lastThumbPresent = 1;
        int thumbPresent = mouseFrame.raw.count - mouseFrame.thumbFiltered.count;
        if (!thumbPresent && lastThumbPresent && mouseFrame.raw.count == 3)
            thumbPresent = lastThumbPresent;
        require(mouseFrame.raw.count - (thumbPresent ? 1 : 0) == 2,
                @"thumb hysteresis did not preserve the recognizer count");
        MGContactFrameDestroy(&mouseFrame);

        for (int argument = 1; argument < argc; argument++) {
            NSString *path = [NSString stringWithUTF8String:argv[argument]];
            MGTrackpadContactFrameBuilder fixtureBuilder;
            MGTrackpadContactFrameBuilderInitialize(&fixtureBuilder);
            int legacyThumbIdentifier = -1;
            for (NSDictionary *event in frameEventsAtPath(path)) {
                MGContactList fixtureContacts = contactsFromEvent(event);
                NSString *device = [event objectForKey:@"device"];
                MGContactFrame frame = [device hasPrefix:@"mouse-"]
                    ? MGMagicMouseContactFrameCreate(fixtureContacts.contacts,
                                                     fixtureContacts.count, NO)
                    : MGTrackpadContactFrameCreate(&fixtureBuilder,
                                                   fixtureContacts.contacts,
                                                   fixtureContacts.count, NO);
                MGContactList legacyRaw = [device hasPrefix:@"mouse-"]
                    ? fixtureContacts
                    : legacyTrackpadRawContacts(fixtureContacts);
                requireSameList(frame.raw, legacyRaw,
                                @"fixture raw derivation changed");
                MGContactList legacyFiltered;
                if ([device hasPrefix:@"mouse-"]) {
                    legacyFiltered = legacyMouseFilteredContacts(legacyRaw);
                } else {
                    if (fixtureContacts.count == 0)
                        legacyThumbIdentifier = -1;
                    legacyFiltered = legacyTrackpadThumbFilteredContacts(
                        legacyRaw, &legacyThumbIdentifier, NO);
                }
                MGContactList legacyFingertips = legacyFingertipScaleContacts(
                    legacyFiltered, [device hasPrefix:@"mouse-"]);
                requireSameList(frame.thumbFiltered, legacyFiltered,
                                @"fixture filtered derivation changed");
                requireSameList(frame.fingertipScale, legacyFingertips,
                                @"fixture fingertip-scale derivation changed");
                free((void *)legacyFiltered.contacts);
                if (legacyRaw.contacts != fixtureContacts.contacts)
                    free((void *)legacyRaw.contacts);
                free((void *)legacyFingertips.contacts);
                MGContactFrameDestroy(&frame);
                free((void *)fixtureContacts.contacts);
            }
        }

        printf("contact frame: all checks passed\n");
    }
    return 0;
}
