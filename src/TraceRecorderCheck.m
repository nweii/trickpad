// Checks deterministic serialization, privacy rejection, bounded capture, ordering, and bundle output.

#import <Foundation/Foundation.h>
#import "TraceRecorder.h"
#import <unistd.h>

static int failures = 0;

static void require(BOOL condition, NSString *message) {
    if (!condition) {
        fprintf(stderr, "FAIL  %s\n", [message UTF8String]);
        failures++;
    }
}

int main(void) {
    @autoreleasepool {
        NSDictionary *event = @{@"schema": @1, @"session": @"test", @"step": @"s",
            @"segment": @1, @"record_seq": @2, @"t_ns": @3, @"source": @"guide",
            @"event": @"test", @"device": [NSNull null], @"data": @{@"z": @1, @"a": @2}};
        NSString *problem = nil;
        NSData *first = MGTraceDeterministicJSONLine(event, &problem);
        NSData *second = MGTraceDeterministicJSONLine(event, &problem);
        require(first != nil && [first isEqualToData:second],
                @"identical events did not serialize deterministically");
        NSString *line = [[[NSString alloc] initWithData:first encoding:NSUTF8StringEncoding] autorelease];
        require([line hasSuffix:@"\n"] && [line rangeOfString:@"\"a\":2"].location <
                [line rangeOfString:@"\"z\":1"].location,
                @"serialized trace is not stable sorted NDJSON");

        for (NSString *privateKey in @[@"application_name", @"configured_command",
                                        @"keycode", @"url_value", @"script_path",
                                        @"clipboard", @"cursor_position", @"device_id"]) {
            NSMutableDictionary *leak = [event mutableCopy];
            [leak setObject:@{privateKey: @"private"} forKey:@"data"];
            require(MGTraceDeterministicJSONLine(leak, &problem) == nil && problem != nil,
                    [privateKey stringByAppendingString:@" reached serialization"]);
            [leak release];
        }

        NSString *root = [NSTemporaryDirectory() stringByAppendingPathComponent:
            [NSString stringWithFormat:@"MGTraceCheck-%@", [[NSUUID UUID] UUIDString]]];
        require(MGTraceStart(root, &problem), @"trace session did not start");
        MGTraceBeginStep(@"normal-r1", @"two-finger-click", @"Two-Finger Click", 1,
                         @"Click once", YES, NO);
        require(MGTraceObservesUnconfiguredGesture(@"Two-Finger Click"),
                @"guided trace did not observe its requested unconfigured gesture");
        require(![[MGTraceStatus() objectForKey:@"saw_mouse_up"] boolValue],
                @"new segment inherited a mouse-up marker");
        dispatch_group_t producers = dispatch_group_create();
        dispatch_semaphore_t startGate = dispatch_semaphore_create(0);
        const int producerCount = 32;
        for (int producer = 0; producer < producerCount; producer++) {
            dispatch_group_async(producers,
                dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
                    dispatch_semaphore_wait(startGate, DISPATCH_TIME_FOREVER);
                    for (int eventIndex = 0; eventIndex < 250; eventIndex++)
                        MGTraceRecordCGEvent(@"mouse-down", 1.0, producer,
                                             eventIndex, @"observed");
                });
        }
        for (int producer = 0; producer < producerCount; producer++)
            dispatch_semaphore_signal(startGate);
        dispatch_group_wait(producers, DISPATCH_TIME_FOREVER);
#if !OS_OBJECT_USE_OBJC
        dispatch_release(startGate);
        dispatch_release(producers);
#endif
        MGTraceContact contacts[] = {{1, 4, 0.3, 0.7, 1.2, 8.2, 6.1, 0.0}};
        for (int i = 0; i < 12000; i++)
            MGTraceRecordMouseFrame((void *)0x1, 1.0 + i, i, contacts, 1);
        MGTraceRecordDispatch(@"Two-Finger Click", @"global", @"built-in", @"suppressed-for-trace");
        MGTraceRecordDispatch(@"Three-Finger Click", @"global", @"built-in", @"suppressed-for-trace");
        MGTraceRecordCGEvent(@"mouse-up", 0.0, 0, 0, @"observed");
        require([[MGTraceStatus() objectForKey:@"saw_mouse_up"] boolValue],
                @"mouse-up was not exposed to guided timing cues");
        while ([[MGTraceStatus() objectForKey:@"pending"] unsignedIntegerValue] > 0)
            usleep(1000);
        MGTraceRecordMouseFrame((void *)0x1, 14000.0, 14000, NULL, 0);
        usleep(900000);
        require([[MGTraceStatus() objectForKey:@"awaiting_label"] boolValue],
                @"full lift did not close the capture window before labeling");
        require([[MGTraceStatus() objectForKey:@"observed_dispatch_count"] unsignedIntegerValue] == 1 &&
                [[MGTraceStatus() objectForKey:@"expected_dispatch_count"] unsignedIntegerValue] == 1,
                @"trace status did not separate observed and expected dispatch counts");
        MGTraceMarkStep(@"clean");
        MGTraceStop();

        NSDictionary *labels = [NSJSONSerialization JSONObjectWithData:
            [NSData dataWithContentsOfFile:[root stringByAppendingPathComponent:@"labels.json"]]
            options:0 error:nil];
        require(labels != nil && [[labels objectForKey:@"dropped_events"] unsignedIntegerValue] > 0,
                @"capture did not enforce its pending-event bound");
        NSString *events = [NSString stringWithContentsOfFile:
            [root stringByAppendingPathComponent:@"events.ndjson"]
            encoding:NSUTF8StringEncoding error:nil];
        require([events rangeOfString:@"private"].location == NSNotFound,
                @"rejected private value appeared in capture");
        unsigned long long previous = 0;
        for (NSString *row in [events componentsSeparatedByString:@"\n"]) {
            if ([row length] == 0) continue;
            NSDictionary *decoded = [NSJSONSerialization JSONObjectWithData:
                [row dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
            unsigned long long sequence = [[decoded objectForKey:@"record_seq"] unsignedLongLongValue];
            require(sequence > previous, @"record sequence did not preserve enqueue order");
            previous = sequence;
        }
        require(previous > 0, @"capture wrote no events");

        NSString *manualRoot = [NSTemporaryDirectory() stringByAppendingPathComponent:
            [NSString stringWithFormat:@"MGTraceManualCheck-%@", [[NSUUID UUID] UUIDString]]];
        require(MGTraceStart(manualRoot, &problem), @"manual trace session did not start");
        MGTraceBeginStep(@"ambient", @"ordinary-mouse-use", @"*", 0,
                         @"Use the mouse normally", NO, NO);
        require(!MGTraceObservesUnconfiguredGesture(@"Two-Finger Click"),
                @"ambient trace counted an unconfigured gesture");
        MGTraceRecordDispatch(@"Two-Finger Tap", @"global", @"keystroke",
                              @"suppressed-for-trace");
        MGTraceRecordDispatch(@"Middle-Fix Index-Far-Tap", @"global", @"keystroke",
                              @"suppressed-for-trace");
        require([[MGTraceStatus() objectForKey:@"observed_dispatch_count"] unsignedIntegerValue] == 2,
                @"ambient trace did not count every configured gesture dispatch");
        require(!MGTraceAuditsGestureCatalog(), @"ordinary trace enabled catalog auditing");
        MGTraceRecordMouseFrame((void *)0x2, 1.0, 1, contacts, 1);
        MGTraceRecordMouseFrame((void *)0x2, 2.0, 2, NULL, 0);
        usleep(900000);
        require([[MGTraceStatus() objectForKey:@"capturing"] boolValue] &&
                ![[MGTraceStatus() objectForKey:@"awaiting_label"] boolValue],
                @"manual trace closed after an ordinary full lift");
        MGTraceFinishOpenStep(@"ambient");
        MGTraceStop();
        require(!MGTraceIsActive(), @"trace recorder remained active after stopping");

        NSString *catalogRoot = [NSTemporaryDirectory() stringByAppendingPathComponent:
            [NSString stringWithFormat:@"MGTraceCatalogCheck-%@", [[NSUUID UUID] UUIDString]]];
        require(MGTraceStart(catalogRoot, &problem), @"catalog trace session did not start");
        MGTraceBeginStep(@"catalog", @"gesture-catalog-audit", @"*", 0,
                         @"Use the mouse normally", NO, YES);
        require(MGTraceAuditsGestureCatalog(), @"catalog trace did not enable shadow auditing");
        MGTraceRecordCandidate(@"Three-Finger Tap", @"shadow-recognized", @"catalog-audit");
        require([[MGTraceStatus() objectForKey:@"catalog_candidate_count"] unsignedIntegerValue] == 1,
                @"catalog trace did not count a shadow recognition");
        MGTraceFinishOpenStep(@"ambient");
        MGTraceStop();

        NSString *candidateRoot = [NSTemporaryDirectory() stringByAppendingPathComponent:
            [NSString stringWithFormat:@"MGTraceCandidateCheck-%@", [[NSUUID UUID] UUIDString]]];
        require(MGTraceStartCapture(candidateRoot, @"candidate-gesture-guided",
                                    @"corner-pull", &problem),
                @"candidate gesture session did not start");
        MGTraceBeginStep(@"candidate-r1", @"candidate-gesture", @"none", 0,
                         @"Perform the candidate motion", YES, NO);
        require(!MGTraceObservesUnconfiguredGesture(@"Two-Finger Click") &&
                !MGTraceAuditsGestureCatalog(),
                @"candidate session evaluated an existing recognizer");
        MGTraceRecordTrackpadFrame((void *)0x3, 1.0, 1, contacts, 1);
        MGTraceRecordTrackpadFrame((void *)0x3, 2.0, 2, NULL, 0);
        usleep(900000);
        require([[MGTraceStatus() objectForKey:@"awaiting_label"] boolValue],
                @"a trackpad full lift did not close the candidate capture window");
        MGTraceMarkStep(@"clean");
        MGTraceStop();
        NSDictionary *candidateManifest = [NSJSONSerialization JSONObjectWithData:
            [NSData dataWithContentsOfFile:[candidateRoot stringByAppendingPathComponent:@"manifest.json"]]
            options:0 error:nil];
        require([[candidateManifest objectForKey:@"candidate"] isEqualToString:@"corner-pull"] &&
                [[candidateManifest objectForKey:@"capture"] isEqualToString:@"candidate-gesture-guided"],
                @"candidate metadata did not reach the bundle manifest");
        NSString *candidateEvents = [NSString stringWithContentsOfFile:
            [candidateRoot stringByAppendingPathComponent:@"events.ndjson"]
            encoding:NSUTF8StringEncoding error:nil];
        require([candidateEvents rangeOfString:@"trackpad-1"].location != NSNotFound,
                @"candidate session did not record trackpad contact frames");
        require([candidateEvents rangeOfString:@"corner-pull"].location == NSNotFound,
                @"the typed candidate name reached a trace event envelope");

        if (failures == 0) {
            printf("trace recorder: all checks passed\n");
            return 0;
        }
        fprintf(stderr, "trace recorder: %d failure(s)\n", failures);
        return 1;
    }
}
