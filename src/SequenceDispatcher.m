// Schedules sequence actions without sleeping on the gesture callback thread,
// serializes repeated sequences, and cancels work through one generation.

#import "SequenceDispatcher.h"

static const NSTimeInterval kSequenceInterKeystrokeDelay = 0.03;

@interface MGSequenceDispatcher ()
- (BOOL)enqueueSequence:(NSArray *)sequence
                  limit:(NSUInteger)limit
            stepHandler:(MGSequenceStepHandler)handler;
- (void)startNextSequence;
- (void)scheduleSequence:(NSArray *)sequence
                   index:(NSUInteger)index
     previousWasKeystroke:(BOOL)previousWasKeystroke
              generation:(NSUInteger)generation
             stepHandler:(MGSequenceStepHandler)handler
               completion:(dispatch_block_t)completion;
- (void)finishSequenceWithGeneration:(NSUInteger)generation;
@end

@implementation MGSequenceDispatcher

- (instancetype)initWithScheduler:(MGSequenceScheduler)scheduler {
    self = [super init];
    if (self) {
        _scheduler = [scheduler copy];
        _pendingSequences = [[NSMutableArray alloc] init];
    }
    return self;
}

- (void)dealloc {
    [_scheduler release];
    [_pendingSequences release];
    [super dealloc];
}

- (void)dispatchSequence:(NSArray *)sequence stepHandler:(MGSequenceStepHandler)handler {
    [self enqueueSequence:sequence limit:0 stepHandler:handler];
}

- (BOOL)dispatchSequence:(NSArray *)sequence
              limitedTo:(NSUInteger)limit
             stepHandler:(MGSequenceStepHandler)handler {
    return [self enqueueSequence:sequence limit:limit stepHandler:handler];
}

// A limit of zero admits the sequence unconditionally and leaves it out of
// every limited count.
- (BOOL)enqueueSequence:(NSArray *)sequence
                  limit:(NSUInteger)limit
            stepHandler:(MGSequenceStepHandler)handler {
    if ([sequence count] == 0 || handler == nil)
        return NO;
    NSDictionary *pending = @{
        @"Sequence": sequence,
        @"Handler": [[handler copy] autorelease],
        @"Limited": @(limit > 0),
    };
    BOOL shouldStart = NO;
    @synchronized (self) {
        if (limit > 0) {
            NSUInteger limited = _sequenceRunning && _runningSequenceIsLimited ? 1 : 0;
            for (NSDictionary *queued in _pendingSequences)
                limited += [[queued objectForKey:@"Limited"] boolValue] ? 1 : 0;
            if (limited >= limit)
                return NO;
        }
        [_pendingSequences addObject:pending];
        if (!_sequenceRunning) {
            _sequenceRunning = YES;
            shouldStart = YES;
        }
    }
    if (shouldStart)
        [self startNextSequence];
    return YES;
}

- (void)startNextSequence {
    NSDictionary *pending = nil;
    NSUInteger generation = 0;
    @synchronized (self) {
        if (!_sequenceRunning)
            return;
        if ([_pendingSequences count] == 0) {
            _sequenceRunning = NO;
            return;
        }
        pending = [[_pendingSequences firstObject] retain];
        [_pendingSequences removeObjectAtIndex:0];
        _runningSequenceIsLimited = [[pending objectForKey:@"Limited"] boolValue];
        generation = _generation;
    }
    NSArray *sequence = [pending objectForKey:@"Sequence"];
    MGSequenceStepHandler handler = [pending objectForKey:@"Handler"];
    [self scheduleSequence:sequence index:0 previousWasKeystroke:NO
                 generation:generation stepHandler:handler completion:^{
        [self finishSequenceWithGeneration:generation];
    }];
    [pending release];
}

- (void)finishSequenceWithGeneration:(NSUInteger)generation {
    BOOL shouldStart = NO;
    @synchronized (self) {
        if (generation != _generation || !_sequenceRunning)
            return;
        _runningSequenceIsLimited = NO;
        if ([_pendingSequences count] == 0)
            _sequenceRunning = NO;
        else
            shouldStart = YES;
    }
    if (shouldStart)
        [self startNextSequence];
}

- (BOOL)generationIsActive:(NSUInteger)generation {
    @synchronized (self) {
        return generation == _generation && _sequenceRunning;
    }
}

- (void)scheduleCompletion:(dispatch_block_t)completion
                      delay:(NSTimeInterval)delay
                 generation:(NSUInteger)generation {
    if (![self generationIsActive:generation])
        return;
    if (delay == 0) {
        completion();
        return;
    }
    _scheduler(delay, ^{
        if ([self generationIsActive:generation])
            completion();
    });
}

- (void)scheduleSequence:(NSArray *)sequence
                   index:(NSUInteger)index
     previousWasKeystroke:(BOOL)previousWasKeystroke
              generation:(NSUInteger)generation
             stepHandler:(MGSequenceStepHandler)handler
               completion:(dispatch_block_t)completion {
    if (![self generationIsActive:generation])
        return;
    NSTimeInterval delay = 0;
    while (index < [sequence count]) {
        NSDictionary *candidate = [sequence objectAtIndex:index];
        NSNumber *wait = [candidate objectForKey:@"WaitMilliseconds"];
        if (wait == nil)
            break;
        delay += [wait doubleValue] / 1000.0;
        index++;
    }
    if (index >= [sequence count]) {
        [self scheduleCompletion:completion delay:delay generation:generation];
        return;
    }

    NSDictionary *step = [sequence objectAtIndex:index];
    BOOL stepIsKeystroke = ![[step objectForKey:@"IsAction"] boolValue];
    if (previousWasKeystroke && stepIsKeystroke)
        delay += kSequenceInterKeystrokeDelay;
    NSUInteger nextIndex = index + 1;
    _scheduler(delay, ^{
        if (![self generationIsActive:generation])
            return;
        if (!handler(step)) {
            completion();
            return;
        }
        [self scheduleSequence:sequence index:nextIndex
           previousWasKeystroke:stepIsKeystroke generation:generation
                    stepHandler:handler completion:completion];
    });
}

- (void)cancelAll {
    @synchronized (self) {
        _generation++;
        [_pendingSequences removeAllObjects];
        _sequenceRunning = NO;
        _runningSequenceIsLimited = NO;
    }
}

@end
