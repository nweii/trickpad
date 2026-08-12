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
        const int rawIdentifiers[] = {1, 2, 3, 4};
        const int trackpadFilteredIdentifiers[] = {1, 4};
        const int fingertipIdentifiers[] = {1};
        requireIdentifiers(trackpadFrame.raw, rawIdentifiers, 4,
                           @"trackpad raw view changed the hardware list");
        requireIdentifiers(trackpadFrame.thumbFiltered,
                           trackpadFilteredIdentifiers, 2,
                           @"trackpad filtered view retained hover or edge contacts");
        requireIdentifiers(trackpadFrame.fingertipScale, fingertipIdentifiers, 1,
                           @"trackpad fingertip-scale view retained hover or palm-scale contacts");
        MGContactFrameDestroy(&trackpadFrame);

        Finger mouse[] = {
            contact(10, MTTouchStateTouching, 0.35, 0.70, 1.5, 8.0, 8.0),
            contact(11, MTTouchStateTouching, 0.96, 0.66, 0.875, 8.0, 6.58),
        };
        MGContactFrame mouseFrame = MGMagicMouseContactFrameCreate(mouse, 2, NO);
        const int mouseFilteredIdentifiers[] = {10};
        const int mouseFingertipIdentifiers[] = {10, 11};
        requireIdentifiers(mouseFrame.thumbFiltered, mouseFilteredIdentifiers, 1,
                           @"Magic Mouse filtered view retained a measured resting-edge contact");
        requireIdentifiers(mouseFrame.fingertipScale,
                           mouseFingertipIdentifiers, 2,
                           @"Magic Mouse swipe scale applied tap-quality filtering");
        MGContactFrameDestroy(&mouseFrame);

        for (int argument = 1; argument < argc; argument++) {
            NSString *path = [NSString stringWithUTF8String:argv[argument]];
            for (NSDictionary *event in frameEventsAtPath(path)) {
                MGContactList fixtureContacts = contactsFromEvent(event);
                NSString *device = [event objectForKey:@"device"];
                MGContactFrame frame = [device hasPrefix:@"mouse-"]
                    ? MGMagicMouseContactFrameCreate(fixtureContacts.contacts,
                                                     fixtureContacts.count, NO)
                    : MGTrackpadContactFrameCreate(&trackpadBuilder,
                                                   fixtureContacts.contacts,
                                                   fixtureContacts.count, NO);
                require(frame.raw.count == fixtureContacts.count,
                        @"fixture raw count changed");
                for (int i = 0; i < fixtureContacts.count; i++)
                    require(frame.raw.contacts[i].identifier == fixtureContacts.contacts[i].identifier,
                            @"fixture raw order changed");
                MGContactList legacyFiltered = [device hasPrefix:@"mouse-"]
                    ? legacyMouseFilteredContacts(fixtureContacts)
                    : fixtureContacts;
                MGContactList legacyFingertips = legacyFingertipScaleContacts(
                    legacyFiltered, [device hasPrefix:@"mouse-"]);
                requireSameList(frame.thumbFiltered, legacyFiltered,
                                @"fixture filtered derivation changed");
                requireSameList(frame.fingertipScale, legacyFingertips,
                                @"fixture fingertip-scale derivation changed");
                if (legacyFiltered.contacts != fixtureContacts.contacts)
                    free((void *)legacyFiltered.contacts);
                free((void *)legacyFingertips.contacts);
                MGContactFrameDestroy(&frame);
                free((void *)fixtureContacts.contacts);
            }
        }

        printf("contact frame: all checks passed\n");
    }
    return 0;
}
