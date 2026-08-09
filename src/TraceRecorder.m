// Records bounded trace events off callback threads and writes deterministic NDJSON without sensitive values.

#import "TraceRecorder.h"

#import <mach/mach_time.h>
#import <os/lock.h>

#include <stdatomic.h>

static const NSUInteger kTraceMaximumPendingEvents = 4096;
static const unsigned long long kTraceMaximumBytes = 50ULL * 1024ULL * 1024ULL;
static atomic_bool traceActive = ATOMIC_VAR_INIT(false);

@interface MGTraceState : NSObject {
@public
    os_unfair_lock lock;
    BOOL active;
    BOOL capturing;
    BOOL awaitingLabel;
    BOOL sawContactsInSegment;
    BOOL sawMouseUpInSegment;
    BOOL closesOnFullLift;
    BOOL auditsGestureCatalog;
    BOOL liftScheduled;
    BOOL stopping;
    NSString *session;
    NSString *step;
    NSString *requested;
    NSString *observedGesture;
    NSUInteger expectedDispatchCount;
    NSUInteger observedDispatchCount;
    NSUInteger catalogCandidateCount;
    NSString *bundlePath;
    NSFileHandle *eventsHandle;
    dispatch_queue_t writer;
    unsigned long long nextSequence;
    unsigned long long writtenBytes;
    NSUInteger pendingEvents;
    NSUInteger droppedEvents;
    NSUInteger segment;
    NSUInteger liftGeneration;
    NSMutableArray *labels;
    NSMutableDictionary *devices;
}
@end

@implementation MGTraceState
@end

static MGTraceState *traceState(void) {
    static MGTraceState *state = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        state = [[MGTraceState alloc] init];
        state->lock = OS_UNFAIR_LOCK_INIT;
        state->writer = dispatch_queue_create("fyi.thirdwind.trickpad.trace", DISPATCH_QUEUE_SERIAL);
        state->labels = [[NSMutableArray alloc] init];
        state->devices = [[NSMutableDictionary alloc] init];
    });
    return state;
}

static uint64_t monotonicNanoseconds(void) {
    static mach_timebase_info_data_t info;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ mach_timebase_info(&info); });
    uint64_t value = mach_continuous_time();
    return value * info.numer / info.denom;
}

static NSSet *allowedEnvelopeKeys(void) {
    static NSSet *keys;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        keys = [[NSSet alloc] initWithArray:@[
            @"schema", @"session", @"step", @"segment", @"record_seq",
            @"t_ns", @"source", @"event", @"device", @"data"
        ]];
    });
    return keys;
}

static NSArray *forbiddenKeyFragments(void) {
    static NSArray *keys;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        keys = [@[
            @"application", @"bundle", @"command",
            @"keycode", @"modifier", @"url", @"script", @"clipboard",
            @"cursor", @"screen", @"device_id", @"serial"
        ] retain];
    });
    return keys;
}

static BOOL objectContainsForbiddenKey(id object) {
    if ([object isKindOfClass:[NSDictionary class]]) {
        for (NSString *key in object) {
            NSString *lowercase = [key lowercaseString];
            BOOL forbidden = NO;
            for (NSString *fragment in forbiddenKeyFragments()) {
                if ([lowercase rangeOfString:fragment].location != NSNotFound) {
                    forbidden = YES;
                    break;
                }
            }
            if (forbidden || objectContainsForbiddenKey([object objectForKey:key]))
                return YES;
        }
    } else if ([object isKindOfClass:[NSArray class]]) {
        for (id value in object)
            if (objectContainsForbiddenKey(value)) return YES;
    }
    return NO;
}

NSData *MGTraceDeterministicJSONLine(NSDictionary *event, NSString **problem) {
    if (problem != NULL) *problem = nil;
    if (![event isKindOfClass:[NSDictionary class]] || objectContainsForbiddenKey(event)) {
        if (problem != NULL) *problem = @"Trace event contains a forbidden field.";
        return nil;
    }
    for (NSString *key in event) {
        if (![allowedEnvelopeKeys() containsObject:key]) {
            if (problem != NULL) *problem = [NSString stringWithFormat:@"Unknown trace envelope field: %@", key];
            return nil;
        }
    }
    NSError *error = nil;
    NSData *json = [NSJSONSerialization dataWithJSONObject:event
                                                   options:NSJSONWritingSortedKeys
                                                     error:&error];
    if (json == nil) {
        if (problem != NULL) *problem = [error localizedDescription];
        return nil;
    }
    NSMutableData *line = [NSMutableData dataWithData:json];
    const char newline = '\n';
    [line appendBytes:&newline length:1];
    return line;
}

static NSString *ephemeralDeviceName(const void *device, NSString *prefix) {
    MGTraceState *state = traceState();
    if (device == NULL) return nil;
    NSString *key = [NSString stringWithFormat:@"%@:%p", prefix, device];
    os_unfair_lock_lock(&state->lock);
    NSString *name = [state->devices objectForKey:key];
    if (name == nil) {
        name = [NSString stringWithFormat:@"%@-%lu", prefix, (unsigned long)[state->devices count] + 1];
        [state->devices setObject:name forKey:key];
    }
    [name retain];
    os_unfair_lock_unlock(&state->lock);
    return [name autorelease];
}

static void enqueue(NSString *source, NSString *event, NSString *device,
                    NSDictionary *data) {
    if (!atomic_load_explicit(&traceActive, memory_order_relaxed))
        return;
    MGTraceState *state = traceState();
    os_unfair_lock_lock(&state->lock);
    BOOL guideEvent = [source isEqualToString:@"guide"];
    if (!state->active || state->stopping || (!state->capturing && !guideEvent)) {
        os_unfair_lock_unlock(&state->lock);
        return;
    }
    if (state->pendingEvents >= kTraceMaximumPendingEvents ||
        state->writtenBytes >= kTraceMaximumBytes) {
        state->droppedEvents++;
        os_unfair_lock_unlock(&state->lock);
        return;
    }
    unsigned long long sequence = ++state->nextSequence;
    NSUInteger segment = state->segment;
    NSString *session = [state->session copy];
    NSString *step = [state->step copy] ?: @"idle";
    state->pendingEvents++;

    NSDictionary *envelope = @{
        @"schema": @1,
        @"session": session,
        @"step": step,
        @"segment": @(segment),
        @"record_seq": @(sequence),
        @"t_ns": @(monotonicNanoseconds()),
        @"source": source,
        @"event": event,
        @"device": device ?: [NSNull null],
        @"data": data ?: @{},
    };
    // Queue insertion stays under the same lock as sequence assignment. The
    // writer does all serialization and file I/O after the callback returns.
    dispatch_async(state->writer, ^{
        NSString *problem = nil;
        NSData *line = MGTraceDeterministicJSONLine(envelope, &problem);
        if (line != nil) {
            os_unfair_lock_lock(&state->lock);
            BOOL withinLimit = state->writtenBytes + [line length] <= kTraceMaximumBytes;
            if (withinLimit) state->writtenBytes += [line length];
            else state->droppedEvents++;
            os_unfair_lock_unlock(&state->lock);
            if (withinLimit) [state->eventsHandle writeData:line];
        } else {
            os_unfair_lock_lock(&state->lock);
            state->droppedEvents++;
            os_unfair_lock_unlock(&state->lock);
        }
        os_unfair_lock_lock(&state->lock);
        state->pendingEvents--;
        os_unfair_lock_unlock(&state->lock);
    });
    os_unfair_lock_unlock(&state->lock);
    [session release];
    [step release];
}

BOOL MGTraceStart(NSString *path, NSString **problem) {
    return MGTraceStartCapture(path, @"magic-mouse-guided", nil, problem);
}

BOOL MGTraceStartCapture(NSString *path, NSString *capture, NSString *candidate,
                         NSString **problem) {
    MGTraceState *state = traceState();
    if (problem != NULL) *problem = nil;
    os_unfair_lock_lock(&state->lock);
    if (state->active) {
        os_unfair_lock_unlock(&state->lock);
        if (problem != NULL) *problem = @"A trace session is already active.";
        return NO;
    }
    os_unfair_lock_unlock(&state->lock);

    NSError *error = nil;
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm createDirectoryAtPath:path withIntermediateDirectories:YES
                        attributes:@{NSFilePosixPermissions: @0700} error:&error]) {
        if (problem != NULL) *problem = [error localizedDescription];
        return NO;
    }
    NSString *eventsPath = [path stringByAppendingPathComponent:@"events.ndjson"];
    if (![fm createFileAtPath:eventsPath contents:nil attributes:@{NSFilePosixPermissions: @0600}]) {
        if (problem != NULL) *problem = @"Could not create events.ndjson.";
        return NO;
    }
    NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:eventsPath];
    if (handle == nil) {
        if (problem != NULL) *problem = @"Could not open events.ndjson.";
        return NO;
    }
    NSString *newSession = [[NSUUID UUID] UUIDString];
    NSMutableDictionary *manifest = [NSMutableDictionary dictionaryWithDictionary:@{
        @"schema": @1,
        @"session": newSession,
        @"capture": capture ?: @"magic-mouse-guided",
        @"actions": @"suppressed",
        @"device_identity": @"session-ephemeral",
        @"privacy": @"redacted-by-construction",
    }];
    // The candidate name is the one field a person types. It stays in the
    // manifest and never reaches an event envelope.
    if ([candidate length] > 0) [manifest setObject:candidate forKey:@"candidate"];
    NSData *manifestData = [NSJSONSerialization dataWithJSONObject:manifest
                                                           options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys
                                                             error:&error];
    if (manifestData == nil || ![manifestData writeToFile:[path stringByAppendingPathComponent:@"manifest.json"]
                                                  options:NSDataWritingAtomic error:&error]) {
        if (problem != NULL) *problem = [error localizedDescription];
        return NO;
    }

    os_unfair_lock_lock(&state->lock);
    state->active = YES;
    state->capturing = NO;
    state->awaitingLabel = NO;
    state->sawContactsInSegment = NO;
    state->liftScheduled = NO;
    state->stopping = NO;
    [state->session release]; state->session = [newSession copy];
    [state->step release]; state->step = [@"setup" copy];
    [state->requested release]; state->requested = nil;
    [state->observedGesture release]; state->observedGesture = nil;
    [state->bundlePath release]; state->bundlePath = [path copy];
    [state->eventsHandle release]; state->eventsHandle = [handle retain];
    state->expectedDispatchCount = 0;
    state->nextSequence = 0;
    state->writtenBytes = 0;
    state->pendingEvents = 0;
    state->droppedEvents = 0;
    state->segment = 0;
    state->liftGeneration = 0;
    [state->labels removeAllObjects];
    [state->devices removeAllObjects];
    os_unfair_lock_unlock(&state->lock);
    atomic_store_explicit(&traceActive, true, memory_order_relaxed);
    enqueue(@"guide", @"session-start", nil, @{@"requested": @"setup"});
    return YES;
}

BOOL MGTraceIsActive(void) {
    return atomic_load_explicit(&traceActive, memory_order_relaxed);
}

BOOL MGTraceIsCapturing(void) {
    if (!MGTraceIsActive()) return NO;
    MGTraceState *state = traceState();
    os_unfair_lock_lock(&state->lock);
    BOOL capturing = state->capturing;
    os_unfair_lock_unlock(&state->lock);
    return capturing;
}

BOOL MGTraceSuppressesActions(void) { return MGTraceIsActive(); }

BOOL MGTraceAuditsGestureCatalog(void) {
    if (!MGTraceIsActive()) return NO;
    MGTraceState *state = traceState();
    os_unfair_lock_lock(&state->lock);
    BOOL audits = state->active && state->capturing && state->auditsGestureCatalog;
    os_unfair_lock_unlock(&state->lock);
    return audits;
}

BOOL MGTraceObservesUnconfiguredGesture(NSString *gesture) {
    if (!MGTraceIsActive() || gesture == nil) return NO;
    MGTraceState *state = traceState();
    os_unfair_lock_lock(&state->lock);
    BOOL observes = state->active && state->capturing &&
        ![state->observedGesture isEqualToString:@"*"] &&
        [state->observedGesture isEqualToString:gesture];
    os_unfair_lock_unlock(&state->lock);
    return observes;
}

NSString *MGTraceBundlePath(void) {
    MGTraceState *state = traceState();
    os_unfair_lock_lock(&state->lock); NSString *path = [state->bundlePath copy]; os_unfair_lock_unlock(&state->lock);
    return [path autorelease];
}

NSDictionary *MGTraceStatus(void) {
    MGTraceState *state = traceState();
    os_unfair_lock_lock(&state->lock);
    NSDictionary *status = [@{@"active": @(state->active), @"capturing": @(state->capturing),
                              @"awaiting_label": @(state->awaitingLabel),
                              @"saw_contacts": @(state->sawContactsInSegment),
                              @"saw_mouse_up": @(state->sawMouseUpInSegment),
                              @"expected_dispatch_count": @(state->expectedDispatchCount),
                              @"observed_dispatch_count": @(state->observedDispatchCount),
                              @"catalog_candidate_count": @(state->catalogCandidateCount),
                              @"step": state->step ?: @"idle",
                              @"segment": @(state->segment), @"pending": @(state->pendingEvents),
                              @"dropped": @(state->droppedEvents), @"bytes": @(state->writtenBytes)} retain];
    os_unfair_lock_unlock(&state->lock);
    return [status autorelease];
}

void MGTraceBeginStep(NSString *step, NSString *requested,
                      NSString *observedGesture, NSUInteger expectedDispatchCount,
                      NSString *instruction, BOOL closesOnFullLift,
                      BOOL auditsGestureCatalog) {
    MGTraceState *state = traceState();
    os_unfair_lock_lock(&state->lock);
    if (!state->active) { os_unfair_lock_unlock(&state->lock); return; }
    [state->step release]; state->step = [step copy];
    [state->requested release]; state->requested = [requested copy];
    [state->observedGesture release]; state->observedGesture = [observedGesture copy];
    state->expectedDispatchCount = expectedDispatchCount;
    state->observedDispatchCount = 0;
    state->catalogCandidateCount = 0;
    state->capturing = NO;
    state->awaitingLabel = NO;
    state->sawContactsInSegment = NO;
    state->sawMouseUpInSegment = NO;
    state->closesOnFullLift = closesOnFullLift;
    state->auditsGestureCatalog = auditsGestureCatalog;
    state->liftScheduled = NO;
    state->liftGeneration++;
    NSUInteger segment = ++state->segment;
    os_unfair_lock_unlock(&state->lock);
    enqueue(@"guide", @"step-start", nil,
            @{@"requested": requested ?: @"none",
              @"observed_gesture": observedGesture ?: @"unknown",
              @"expected_dispatch_count": @(expectedDispatchCount),
              @"catalog_audit": @(auditsGestureCatalog),
              @"instruction": instruction ?: @""});
    os_unfair_lock_lock(&state->lock);
    if (state->active && state->segment == segment) state->capturing = YES;
    os_unfair_lock_unlock(&state->lock);
}

void MGTraceMarkStep(NSString *label) {
    if (![@[@"clean", @"botched", @"unsure", @"skip"] containsObject:label]) return;
    MGTraceState *state = traceState();
    os_unfair_lock_lock(&state->lock);
    if (!state->active || !state->awaitingLabel) {
        os_unfair_lock_unlock(&state->lock);
        return;
    }
    NSDictionary *entry = @{ @"segment": @(state->segment), @"step": state->step ?: @"idle",
                             @"requested": state->requested ?: @"none",
                             @"observed_gesture": state->observedGesture ?: @"unknown",
                             @"expected_dispatch_count": @(state->expectedDispatchCount),
                             @"human": label };
    [state->labels addObject:entry];
    state->awaitingLabel = NO;
    os_unfair_lock_unlock(&state->lock);
    enqueue(@"guide", @"human-label", nil, @{@"label": label});
}

void MGTraceFinishOpenStep(NSString *label) {
    MGTraceState *state = traceState();
    os_unfair_lock_lock(&state->lock);
    if (!state->active || !state->capturing) {
        os_unfair_lock_unlock(&state->lock);
        return;
    }
    NSDictionary *entry = @{ @"segment": @(state->segment), @"step": state->step ?: @"idle",
                             @"requested": state->requested ?: @"none",
                             @"observed_gesture": state->observedGesture ?: @"unknown",
                             @"expected_dispatch_count": @(state->expectedDispatchCount),
                             @"human": label ?: @"unsure" };
    [state->labels addObject:entry];
    state->capturing = NO;
    state->awaitingLabel = NO;
    state->liftScheduled = NO;
    state->liftGeneration++;
    os_unfair_lock_unlock(&state->lock);
    enqueue(@"guide", @"capture-window-finished", nil, @{@"label": label ?: @"unsure"});
}

void MGTraceStop(void) {
    MGTraceState *state = traceState();
    if (!MGTraceIsActive()) return;
    enqueue(@"guide", @"session-stop", nil, @{});
    os_unfair_lock_lock(&state->lock); state->stopping = YES; os_unfair_lock_unlock(&state->lock);
    dispatch_sync(state->writer, ^{});
    os_unfair_lock_lock(&state->lock);
    NSArray *labelsCopy = [[state->labels copy] autorelease];
    NSString *path = [[state->bundlePath copy] autorelease];
    NSUInteger dropped = state->droppedEvents;
    [state->eventsHandle synchronizeFile];
    [state->eventsHandle closeFile];
    [state->eventsHandle release]; state->eventsHandle = nil;
    state->active = NO;
    state->capturing = NO;
    state->awaitingLabel = NO;
    state->stopping = NO;
    os_unfair_lock_unlock(&state->lock);
    atomic_store_explicit(&traceActive, false, memory_order_relaxed);
    NSDictionary *labelsDocument = @{@"schema": @1, @"labels": labelsCopy,
                                      @"dropped_events": @(dropped)};
    NSData *data = [NSJSONSerialization dataWithJSONObject:labelsDocument
                                                   options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys error:nil];
    [data writeToFile:[path stringByAppendingPathComponent:@"labels.json"] options:NSDataWritingAtomic error:nil];
}

static void recordFrame(NSString *devicePrefix, const void *device,
                        double hardwareTimestamp, int frame,
                        const MGTraceContact *contacts, int contactCount) {
    if (!MGTraceIsCapturing()) return;
    NSMutableArray *values = [NSMutableArray arrayWithCapacity:MAX(contactCount, 0)];
    for (int i = 0; i < contactCount; i++) {
        [values addObject:@{@"id": @(contacts[i].identifier), @"state": @(contacts[i].state),
                            @"x": @(contacts[i].x), @"y": @(contacts[i].y), @"size": @(contacts[i].size),
                            @"major": @(contacts[i].majorAxis), @"minor": @(contacts[i].minorAxis),
                            @"density": @(contacts[i].density)}];
    }
    enqueue(@"touch", @"frame", ephemeralDeviceName(device, devicePrefix),
            @{@"hardware_t": @(hardwareTimestamp), @"frame": @(frame), @"contacts": values});

    MGTraceState *state = traceState();
    os_unfair_lock_lock(&state->lock);
    if (!state->active || !state->capturing || !state->closesOnFullLift) {
        os_unfair_lock_unlock(&state->lock);
        return;
    }
    if (contactCount > 0) {
        state->sawContactsInSegment = YES;
        state->liftScheduled = NO;
        state->liftGeneration++;
        os_unfair_lock_unlock(&state->lock);
        return;
    }
    if (!state->sawContactsInSegment || state->liftScheduled) {
        os_unfair_lock_unlock(&state->lock);
        return;
    }
    state->liftScheduled = YES;
    NSUInteger generation = state->liftGeneration;
    NSUInteger segment = state->segment;
    os_unfair_lock_unlock(&state->lock);

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.75 * NSEC_PER_SEC)),
                   dispatch_get_global_queue(QOS_CLASS_USER_INTERACTIVE, 0), ^{
        os_unfair_lock_lock(&state->lock);
        BOOL closesSegment = state->active && state->capturing &&
            state->segment == segment && state->liftGeneration == generation;
        if (closesSegment) {
            state->capturing = NO;
            state->awaitingLabel = YES;
            state->liftScheduled = NO;
        }
        os_unfair_lock_unlock(&state->lock);
        if (closesSegment)
            enqueue(@"guide", @"capture-window-closed", nil, @{});
    });
}

void MGTraceRecordMouseFrame(const void *device, double hardwareTimestamp,
                             int frame, const MGTraceContact *contacts,
                             int contactCount) {
    recordFrame(@"mouse", device, hardwareTimestamp, frame, contacts, contactCount);
}

void MGTraceRecordTrackpadFrame(const void *device, double hardwareTimestamp,
                                int frame, const MGTraceContact *contacts,
                                int contactCount) {
    recordFrame(@"trackpad", device, hardwareTimestamp, frame, contacts, contactCount);
}

void MGTraceRecordFilterDecision(int identifier, NSString *reason, BOOL kept,
                                 double x, double y, double size,
                                 double majorAxis, double minorAxis) {
    if (!MGTraceIsActive()) return;
    enqueue(@"filter", kept ? @"kept" : @"excluded", nil,
            @{@"id": @(identifier), @"reason": reason ?: @"none", @"x": @(x), @"y": @(y),
              @"size": @(size), @"major": @(majorAxis), @"minor": @(minorAxis)});
}

void MGTraceRecordCGEvent(NSString *event, double pressure,
                          int64_t axis1, int64_t axis2, NSString *disposition) {
    if (!MGTraceIsActive()) return;
    MGTraceState *state = traceState();
    if ([event isEqualToString:@"mouse-up"]) {
        os_unfair_lock_lock(&state->lock);
        if (state->active && state->capturing)
            state->sawMouseUpInSegment = YES;
        os_unfair_lock_unlock(&state->lock);
    }
    enqueue(@"cg", event, nil, @{@"pressure": @(pressure), @"axis1": @(axis1),
                                  @"axis2": @(axis2), @"disposition": disposition ?: @"observed"});
}

void MGTraceRecordClickEligibility(NSString *stage, int rawContactCount,
                                   int eligibleContactCount) {
    if (!MGTraceIsActive()) return;
    enqueue(@"click", @"mouse-down-eligibility", nil,
            @{@"stage": stage ?: @"unknown", @"raw_contacts": @(rawContactCount),
              @"eligible_contacts": @(eligibleContactCount)});
}

void MGTraceRecordCandidate(NSString *gesture, NSString *phase, NSString *reason) {
    if (!MGTraceIsActive()) return;
    if ([phase isEqualToString:@"shadow-recognized"]) {
        MGTraceState *state = traceState();
        os_unfair_lock_lock(&state->lock);
        if (state->active && state->capturing && state->auditsGestureCatalog)
            state->catalogCandidateCount++;
        os_unfair_lock_unlock(&state->lock);
    }
    enqueue(@"recognizer", @"candidate", nil,
            @{@"gesture": gesture ?: @"unknown", @"phase": phase ?: @"observed",
              @"reason": reason ?: @"none"});
}

void MGTraceRecordOwnership(NSString *requested, NSString *previous,
                            NSString *result, BOOL accepted) {
    if (!MGTraceIsActive()) return;
    enqueue(@"ownership", @"transition", nil,
            @{@"requested": requested ?: @"none", @"previous": previous ?: @"none",
              @"result": result ?: @"none", @"accepted": @(accepted)});
}

void MGTraceRecordDispatch(NSString *gesture, NSString *scope,
                           NSString *actionKind, NSString *outcome) {
    if (!MGTraceIsActive()) return;
    MGTraceState *state = traceState();
    os_unfair_lock_lock(&state->lock);
    if (state->active && state->capturing &&
        (state->observedGesture == nil || [state->observedGesture isEqualToString:@"*"] ||
         [gesture isEqualToString:state->observedGesture]))
        state->observedDispatchCount++;
    os_unfair_lock_unlock(&state->lock);
    enqueue(@"dispatch", @"result", nil,
            @{@"gesture": gesture ?: @"unknown", @"scope": scope ?: @"none",
              @"action_kind": actionKind ?: @"unknown", @"outcome": outcome ?: @"observed",
              @"inferred": [outcome isEqualToString:@"suppressed-for-trace"] ? @"recognized" : @"observed"});
}
