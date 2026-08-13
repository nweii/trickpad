// Schedules sequence actions without sleeping on the gesture callback thread,
// and invalidates scheduled remainders through one cancellation generation.

#import "SequenceDispatcher.h"

static const NSTimeInterval kSequenceInterKeystrokeDelay = 0.03;

@interface MGSequenceDispatcher ()
- (void)scheduleSequence:(NSArray *)sequence
                   index:(NSUInteger)index
     previousWasKeystroke:(BOOL)previousWasKeystroke
              generation:(NSUInteger)generation
             stepHandler:(MGSequenceStepHandler)handler;
@end

@implementation MGSequenceDispatcher

- (instancetype)initWithScheduler:(MGSequenceScheduler)scheduler {
    self = [super init];
    if (self)
        _scheduler = [scheduler copy];
    return self;
}

- (void)dealloc {
    [_scheduler release];
    [super dealloc];
}

- (void)dispatchSequence:(NSArray *)sequence stepHandler:(MGSequenceStepHandler)handler {
    if ([sequence count] == 0 || handler == nil)
        return;
    NSUInteger generation = 0;
    @synchronized (self) {
        generation = _generation;
    }
    [self scheduleSequence:sequence index:0 previousWasKeystroke:NO
                 generation:generation stepHandler:handler];
}

- (void)scheduleSequence:(NSArray *)sequence
                   index:(NSUInteger)index
     previousWasKeystroke:(BOOL)previousWasKeystroke
              generation:(NSUInteger)generation
             stepHandler:(MGSequenceStepHandler)handler {
    NSTimeInterval delay = 0;
    while (index < [sequence count]) {
        NSDictionary *candidate = [sequence objectAtIndex:index];
        NSNumber *wait = [candidate objectForKey:@"WaitMilliseconds"];
        if (wait == nil)
            break;
        delay += [wait doubleValue] / 1000.0;
        index++;
    }
    if (index >= [sequence count])
        return;

    NSDictionary *step = [sequence objectAtIndex:index];
    BOOL stepIsKeystroke = ![[step objectForKey:@"IsAction"] boolValue];
    if (previousWasKeystroke && stepIsKeystroke)
        delay += kSequenceInterKeystrokeDelay;
    NSUInteger nextIndex = index + 1;
    _scheduler(delay, ^{
        BOOL active = NO;
        @synchronized (self) {
            active = generation == _generation;
        }
        if (!active)
            return;
        handler(step);
        [self scheduleSequence:sequence index:nextIndex
           previousWasKeystroke:stepIsKeystroke generation:generation
                    stepHandler:handler];
    });
}

- (void)cancelAll {
    @synchronized (self) {
        _generation++;
    }
}

@end
