// Checks ordered asynchronous sequence dispatch, wait timing, the default
// keystroke gap, and cancellation of undispatched actions.

#import <Foundation/Foundation.h>
#import <math.h>
#import "SequenceDispatcher.h"

static int failures = 0;

static void require(BOOL condition, const char *message) {
    if (condition)
        return;
    fprintf(stderr, "FAIL  %s\n", message);
    failures++;
}

static void runFirstScheduled(NSMutableArray *scheduled) {
    NSDictionary *item = [[scheduled objectAtIndex:0] retain];
    [scheduled removeObjectAtIndex:0];
    ((dispatch_block_t)[item objectForKey:@"block"])();
    [item release];
}

int main(void) {
    @autoreleasepool {
        NSMutableArray *scheduled = [NSMutableArray array];
        MGSequenceScheduler scheduler = ^(NSTimeInterval delay, dispatch_block_t block) {
            [scheduled addObject:@{ @"delay": @(delay),
                                    @"block": [[block copy] autorelease] }];
        };
        MGSequenceDispatcher *dispatcher =
            [[[MGSequenceDispatcher alloc] initWithScheduler:scheduler] autorelease];
        NSDictionary *prefix = @{ @"Name": @"prefix", @"IsAction": @NO };
        NSDictionary *key = @{ @"Name": @"key", @"IsAction": @NO };
        NSDictionary *url = @{ @"Name": @"url", @"IsAction": @YES };
        NSMutableArray *emitted = [NSMutableArray array];

        [dispatcher dispatchSequence:@[prefix, @{ @"WaitMilliseconds": @120 }, key, url]
                         stepHandler:^(NSDictionary *step) {
            [emitted addObject:[step objectForKey:@"Name"]];
        }];
        require([emitted count] == 0 && [scheduled count] == 1,
                "dispatch returns before the first action runs");
        require(fabs([[[scheduled firstObject] objectForKey:@"delay"] doubleValue]) < 0.0001,
                "the first action is queued without a configured wait");
        runFirstScheduled(scheduled);
        require([emitted isEqual:@[@"prefix"]], "the first action dispatches first");
        require(fabs([[[scheduled firstObject] objectForKey:@"delay"] doubleValue] - 0.15) < 0.0001,
                "wait milliseconds add to the default inter-keystroke gap");
        runFirstScheduled(scheduled);
        runFirstScheduled(scheduled);
        require([emitted isEqual:@[@"prefix", @"key", @"url"]],
                "mixed actions dispatch in configured order");

        [emitted removeAllObjects];
        [dispatcher dispatchSequence:@[prefix, key] stepHandler:^(NSDictionary *step) {
            [emitted addObject:[step objectForKey:@"Name"]];
        }];
        runFirstScheduled(scheduled);
        require(fabs([[[scheduled firstObject] objectForKey:@"delay"] doubleValue] - 0.03) < 0.0001,
                "consecutive keystrokes receive the default processing gap");

        [dispatcher cancelAll];
        runFirstScheduled(scheduled);
        require([emitted isEqual:@[@"prefix"]],
                "cancellation drops the undispatched sequence remainder");

        if (failures == 0) {
            printf("sequence dispatcher: all checks passed\n");
            return 0;
        }
        fprintf(stderr, "sequence dispatcher: %d failure(s)\n", failures);
        return 1;
    }
}
