// Validates a redacted trace bundle and produces aggregate analysis without exposing raw configured values.

#import <Foundation/Foundation.h>

#include <math.h>

static void fail(NSString *message) {
    fprintf(stderr, "trace analyzer: %s\n", [message UTF8String]);
    exit(1);
}

static id readJSON(NSString *path) {
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (data == nil) return nil;
    return [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
}

static NSArray *readEvents(NSString *path) {
    NSString *text = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
    if (text == nil) return nil;
    NSMutableArray *events = [NSMutableArray array];
    unsigned long long previous = 0;
    for (NSString *line in [text componentsSeparatedByString:@"\n"]) {
        if ([line length] == 0) continue;
        NSDictionary *event = [NSJSONSerialization JSONObjectWithData:
            [line dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
        if (![event isKindOfClass:[NSDictionary class]]) return nil;
        unsigned long long sequence = [[event objectForKey:@"record_seq"] unsignedLongLongValue];
        if (sequence <= previous) return nil;
        previous = sequence;
        [events addObject:event];
    }
    return events;
}

static NSDictionary *distribution(NSArray *numbers) {
    if ([numbers count] == 0) return @{@"count": @0};
    NSArray *sorted = [numbers sortedArrayUsingComparator:^NSComparisonResult(NSNumber *a, NSNumber *b) {
        return [a compare:b];
    }];
    NSUInteger count = [sorted count];
    NSUInteger p90 = MIN(count - 1, (NSUInteger)ceil(0.90 * count) - 1);
    return @{@"count": @(count), @"min": sorted[0], @"median": sorted[(count - 1) / 2],
             @"p90": sorted[p90], @"max": sorted[count - 1]};
}

static BOOL gestureMatchesLegacyRequestedGesture(NSString *gesture, NSString *requested) {
    if ([requested hasPrefix:@"two-finger-tap"])
        return [gesture isEqualToString:@"Two-Finger Tap"];
    if ([requested hasPrefix:@"two-finger-click"])
        return [gesture isEqualToString:@"Two-Finger Click"];
    if ([requested hasPrefix:@"three-finger-click"])
        return [gesture isEqualToString:@"Three-Finger Click"];
    return [gesture isEqualToString:@"Two-Finger Click"] ||
        [gesture isEqualToString:@"Three-Finger Click"];
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc != 2) fail(@"usage: analyze-trace BUNDLE");
        NSString *root = [NSString stringWithUTF8String:argv[1]];
        NSDictionary *manifest = readJSON([root stringByAppendingPathComponent:@"manifest.json"]);
        NSDictionary *labelDocument = readJSON([root stringByAppendingPathComponent:@"labels.json"]);
        NSArray *events = readEvents([root stringByAppendingPathComponent:@"events.ndjson"]);
        if (![[manifest objectForKey:@"schema"] isEqual:@1] ||
            ![[labelDocument objectForKey:@"schema"] isEqual:@1] || events == nil)
            fail(@"malformed or unsupported trace bundle");
        NSArray *labels = [labelDocument objectForKey:@"labels"];
        if (![labels isKindOfClass:[NSArray class]]) fail(@"labels.json has no labels array");

        NSMutableDictionary *dispatchGesturesBySegment = [NSMutableDictionary dictionary];
        NSMutableDictionary *dispatchGestureCounts = [NSMutableDictionary dictionary];
        NSMutableDictionary *catalogCandidateCounts = [NSMutableDictionary dictionary];
        NSMutableDictionary *mouseDownEligibility = [NSMutableDictionary dictionary];
        NSMutableDictionary *filters = [NSMutableDictionary dictionary];
        NSMutableDictionary *outcomes = [NSMutableDictionary dictionary];
        NSMutableDictionary *firstDown = [NSMutableDictionary dictionary];
        NSMutableDictionary *lastUp = [NSMutableDictionary dictionary];
        NSMutableDictionary *firstTouch = [NSMutableDictionary dictionary];
        NSMutableDictionary *lastTouch = [NSMutableDictionary dictionary];
        NSMutableDictionary *contactFrames = [NSMutableDictionary dictionary];
        NSMutableDictionary *peakContacts = [NSMutableDictionary dictionary];
        NSMutableDictionary *contactPersistence = [NSMutableDictionary dictionary];
        NSMutableDictionary *contactFirstSeenBySegment = [NSMutableDictionary dictionary];
        NSMutableDictionary *firstPairSpanBySegment = [NSMutableDictionary dictionary];
        NSMutableSet *contactIdentifiers = [NSMutableSet set];
        NSMutableArray *sizes = [NSMutableArray array];
        NSMutableArray *majorAxes = [NSMutableArray array];
        NSMutableArray *minorAxes = [NSMutableArray array];
        NSMutableArray *xs = [NSMutableArray array];
        NSMutableArray *ys = [NSMutableArray array];
        NSUInteger acceptedOwnership = 0, rejectedOwnership = 0, cancellations = 0;

        for (NSDictionary *event in events) {
            NSNumber *segment = [event objectForKey:@"segment"];
            NSString *source = [event objectForKey:@"source"];
            NSString *name = [event objectForKey:@"event"];
            NSDictionary *data = [event objectForKey:@"data"];
            NSNumber *time = [event objectForKey:@"t_ns"];
            if ([source isEqualToString:@"dispatch"]) {
                NSMutableArray *gestures = dispatchGesturesBySegment[segment];
                if (gestures == nil) {
                    gestures = [NSMutableArray array];
                    dispatchGesturesBySegment[segment] = gestures;
                }
                NSString *gesture = [data objectForKey:@"gesture"] ?: @"unknown";
                [gestures addObject:gesture];
                dispatchGestureCounts[gesture] = @([dispatchGestureCounts[gesture] unsignedIntegerValue] + 1);
                NSString *outcome = [data objectForKey:@"outcome"] ?: @"unknown";
                outcomes[outcome] = @([outcomes[outcome] unsignedIntegerValue] + 1);
            } else if ([source isEqualToString:@"filter"]) {
                NSString *reason = [data objectForKey:@"reason"] ?: @"unknown";
                filters[reason] = @([filters[reason] unsignedIntegerValue] + 1);
            } else if ([source isEqualToString:@"ownership"]) {
                if ([[data objectForKey:@"accepted"] boolValue]) acceptedOwnership++;
                else rejectedOwnership++;
            } else if ([source isEqualToString:@"recognizer"]) {
                NSString *phase = [data objectForKey:@"phase"];
                if ([phase isEqualToString:@"canceled"]) {
                    cancellations++;
                } else if ([phase isEqualToString:@"shadow-recognized"]) {
                    NSString *gesture = [data objectForKey:@"gesture"] ?: @"unknown";
                    catalogCandidateCounts[gesture] = @([catalogCandidateCounts[gesture] unsignedIntegerValue] + 1);
                }
            } else if ([source isEqualToString:@"click"] &&
                       [name isEqualToString:@"mouse-down-eligibility"]) {
                NSString *stage = [data objectForKey:@"stage"] ?: @"unknown";
                mouseDownEligibility[stage] = @([mouseDownEligibility[stage] unsignedIntegerValue] + 1);
            } else if ([source isEqualToString:@"cg"] && [name isEqualToString:@"mouse-down"]) {
                if (firstDown[segment] == nil) firstDown[segment] = time;
            } else if ([source isEqualToString:@"cg"] && [name isEqualToString:@"mouse-up"]) {
                lastUp[segment] = time;
            } else if ([source isEqualToString:@"touch"] && [name isEqualToString:@"frame"]) {
                NSArray *contacts = [data objectForKey:@"contacts"];
                if ([contacts count] > 0) {
                    if (firstTouch[segment] == nil) firstTouch[segment] = time;
                    lastTouch[segment] = time;
                }
                contactFrames[segment] = @([contactFrames[segment] unsignedIntegerValue] + 1);
                if ([contacts count] > [peakContacts[segment] unsignedIntegerValue])
                    peakContacts[segment] = @([contacts count]);
                NSMutableDictionary *firstSeen = contactFirstSeenBySegment[segment];
                if (firstSeen == nil) {
                    firstSeen = [NSMutableDictionary dictionary];
                    contactFirstSeenBySegment[segment] = firstSeen;
                }
                for (NSDictionary *contact in contacts) {
                    NSString *contactKey = [NSString stringWithFormat:@"%@:%@", segment,
                                             [contact objectForKey:@"id"]];
                    NSString *contactID = [[contact objectForKey:@"id"] stringValue] ?: @"unknown";
                    if (firstSeen[contactID] == nil) firstSeen[contactID] = time;
                    [contactIdentifiers addObject:contactKey];
                    contactPersistence[contactKey] = @([contactPersistence[contactKey] unsignedIntegerValue] + 1);
                    if ([contact objectForKey:@"size"]) [sizes addObject:[contact objectForKey:@"size"]];
                    if ([contact objectForKey:@"major"]) [majorAxes addObject:[contact objectForKey:@"major"]];
                    if ([contact objectForKey:@"minor"]) [minorAxes addObject:[contact objectForKey:@"minor"]];
                    if ([contact objectForKey:@"x"]) [xs addObject:[contact objectForKey:@"x"]];
                    if ([contact objectForKey:@"y"]) [ys addObject:[contact objectForKey:@"y"]];
                }
                if ([contacts count] >= 2 && firstPairSpanBySegment[segment] == nil) {
                    double maximumDistance = 0;
                    for (NSUInteger i = 0; i < [contacts count]; i++) {
                        for (NSUInteger j = i + 1; j < [contacts count]; j++) {
                            double dx = [[contacts[i] objectForKey:@"x"] doubleValue] -
                                [[contacts[j] objectForKey:@"x"] doubleValue];
                            double dy = [[contacts[i] objectForKey:@"y"] doubleValue] -
                                [[contacts[j] objectForKey:@"y"] doubleValue];
                            maximumDistance = MAX(maximumDistance, sqrt(dx * dx + dy * dy));
                        }
                    }
                    firstPairSpanBySegment[segment] = @(maximumDistance);
                }
            }
        }

        NSUInteger tp = 0, tn = 0, fp = 0, fn = 0;
        NSUInteger exactCount = 0, underCount = 0, overCount = 0;
        NSMutableArray *falsePositive = [NSMutableArray array];
        NSMutableArray *falseNegative = [NSMutableArray array];
        NSMutableArray *downToTouch = [NSMutableArray array];
        NSMutableArray *touchToUp = [NSMutableArray array];
        NSMutableDictionary *humanCounts = [NSMutableDictionary dictionary];
        NSMutableArray *caseResults = [NSMutableArray array];
        for (NSDictionary *label in labels) {
            NSNumber *segment = [label objectForKey:@"segment"];
            NSUInteger expected = [[label objectForKey:@"expected_dispatch_count"] unsignedIntegerValue];
            NSString *requested = [label objectForKey:@"requested"] ?: @"none";
            NSString *observedGesture = [label objectForKey:@"observed_gesture"];
            NSDictionary *firstSeen = contactFirstSeenBySegment[segment] ?: @{};
            NSArray *onsetTimes = [firstSeen allValues];
            NSNumber *earliestOnset = [onsetTimes valueForKeyPath:@"@min.self"];
            NSNumber *latestOnset = [onsetTimes valueForKeyPath:@"@max.self"];
            NSNumber *firstTouchTime = firstTouch[segment];
            NSNumber *lastTouchTime = lastTouch[segment];
            NSMutableDictionary *contactMetrics = [@{
                @"contact_count": @([firstSeen count]),
                @"peak_contact_count": peakContacts[segment] ?: @0,
                @"frames": contactFrames[segment] ?: @0,
                @"first_pair_span": firstPairSpanBySegment[segment] ?: [NSNull null],
                @"contact_onset_spread_ms": earliestOnset != nil && latestOnset != nil
                    ? @(([latestOnset longLongValue] - [earliestOnset longLongValue]) / 1000000.0)
                    : [NSNull null],
                @"touch_duration_ms": firstTouchTime != nil && lastTouchTime != nil
                    ? @(([lastTouchTime longLongValue] - [firstTouchTime longLongValue]) / 1000000.0)
                    : [NSNull null],
            } mutableCopy];
            NSUInteger observed = 0;
            for (NSString *gesture in dispatchGesturesBySegment[segment])
                if ([observedGesture isEqualToString:@"*"] || (observedGesture != nil
                    ? [gesture isEqualToString:observedGesture]
                    : gestureMatchesLegacyRequestedGesture(gesture, requested))) observed++;
            NSString *human = [label objectForKey:@"human"] ?: @"unlabeled";
            humanCounts[human] = @([humanCounts[human] unsignedIntegerValue] + 1);
            BOOL excludedByHuman = [human isEqualToString:@"skip"] || [human isEqualToString:@"botched"];
            NSString *inference = excludedByHuman ? @"excluded-by-human-label" :
                observed == expected ? @"matches-request" :
                observed < expected ? @"under-dispatch" : @"over-dispatch";
            [caseResults addObject:@{@"segment": segment,
                @"requested": requested,
                @"human": human, @"expected_dispatch_count": @(expected),
                @"observed_dispatch_count": @(observed), @"inference": inference,
                @"contact_metrics": contactMetrics}];
            [contactMetrics release];
            if (excludedByHuman) continue;
            if (observed == expected) exactCount++;
            else if (observed < expected) underCount++;
            else overCount++;
            if (expected == 0 && observed == 0) tn++;
            else if (expected > 0 && observed == expected) tp++;
            else if (observed < expected) { fn++; [falseNegative addObject:segment]; }
            else { fp++; [falsePositive addObject:segment]; }
            if (firstDown[segment] && firstTouch[segment])
                [downToTouch addObject:@(([firstTouch[segment] longLongValue] - [firstDown[segment] longLongValue]) / 1000000.0)];
            if (lastTouch[segment] && lastUp[segment])
                [touchToUp addObject:@(([lastUp[segment] longLongValue] - [lastTouch[segment] longLongValue]) / 1000000.0)];
        }

        NSMutableDictionary *contactFramesForJSON = [NSMutableDictionary dictionary];
        for (NSNumber *segment in contactFrames)
            contactFramesForJSON[[segment stringValue]] = contactFrames[segment];
        NSDictionary *analysis = @{
            @"schema": @1,
            @"capture": [manifest objectForKey:@"capture"] ?: @"unknown",
            @"candidate": [manifest objectForKey:@"candidate"] ?: [NSNull null],
            @"case_counts": @{@"labeled": @([labels count]), @"events": @([events count]),
                               @"human": humanCounts},
            @"cases": caseResults,
            @"confusion_matrix": @{@"true_positive": @(tp), @"true_negative": @(tn),
                                    @"false_positive": @(fp), @"false_negative": @(fn)},
            @"dispatch_count_matrix": @{@"exact": @(exactCount), @"under": @(underCount),
                                          @"over": @(overCount)},
            @"timing_ms": @{@"mouse_down_to_first_touch": distribution(downToTouch),
                             @"last_touch_to_mouse_up": distribution(touchToUp)},
            @"contacts": @{@"segment_contact_frames": contactFramesForJSON,
                            @"unique_segment_contacts": @([contactIdentifiers count]),
                            @"persistence_frames": distribution([contactPersistence allValues]),
                            @"x": distribution(xs), @"y": distribution(ys),
                            @"size": distribution(sizes), @"major_axis": distribution(majorAxes),
                            @"minor_axis": distribution(minorAxes)},
            @"filters": filters,
            @"ownership": @{@"accepted": @(acceptedOwnership), @"rejected": @(rejectedOwnership),
                             @"cancellations": @(cancellations)},
            @"dispatch_outcomes": outcomes,
            @"dispatch_gestures": dispatchGestureCounts,
            @"catalog_candidates": catalogCandidateCounts,
            @"mouse_down_eligibility": mouseDownEligibility,
            @"likely_false_positive_segments": falsePositive,
            @"likely_false_negative_segments": falseNegative,
            @"interpretation": @"Requested intent, human label, recorded observation, and inferred classification remain separate. Likely errors are review candidates, not ground truth."
        };
        NSError *error = nil;
        NSData *json = [NSJSONSerialization dataWithJSONObject:analysis
                                                       options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys error:&error];
        if (json == nil || ![json writeToFile:[root stringByAppendingPathComponent:@"analysis.json"]
                                        options:NSDataWritingAtomic error:&error])
            fail([error localizedDescription] ?: @"could not write analysis.json");
        NSString *report = [NSString stringWithFormat:
            @"# Trickpad trace analysis\n\n"
             "Analyzed %lu labeled cases and %lu events.\n\n"
             "## Dispatch count results\n\n"
             "| Exact | Under | Over |\n|---:|---:|---:|\n| %lu | %lu | %lu |\n\n"
             "## Review candidates\n\nLikely false positives: %@\n\nLikely false negatives: %@\n\n"
             "## Configured gesture dispatches\n\n%@\n\n"
             "## Catalog audit candidates\n\n%@\n\n"
             "## Mouse-down eligibility\n\n%@\n\n"
             "## Interpretation\n\nRequested intent, human label, recorded observation, and analyzer inference are separate. Review candidate segments against the raw redacted events before changing recognition.\n",
            (unsigned long)[labels count], (unsigned long)[events count],
            (unsigned long)exactCount, (unsigned long)underCount, (unsigned long)overCount,
            falsePositive, falseNegative, dispatchGestureCounts, catalogCandidateCounts,
            mouseDownEligibility];
        if (![report writeToFile:[root stringByAppendingPathComponent:@"report.md"] atomically:YES
                         encoding:NSUTF8StringEncoding error:&error])
            fail([error localizedDescription] ?: @"could not write report.md");
        printf("trace analyzer: wrote analysis.json and report.md\n");
    }
    return 0;
}
