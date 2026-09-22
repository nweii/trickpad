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
            return YES;
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
            return YES;
        }];
        runFirstScheduled(scheduled);
        require(fabs([[[scheduled firstObject] objectForKey:@"delay"] doubleValue] - 0.03) < 0.0001,
                "consecutive keystrokes receive the default processing gap");

        [dispatcher cancelAll];
        runFirstScheduled(scheduled);
        require([emitted isEqual:@[@"prefix"]],
                "cancellation drops the undispatched sequence remainder");

        [scheduled removeAllObjects];
        [emitted removeAllObjects];
        NSDictionary *prefixB = @{ @"Name": @"prefix-b", @"IsAction": @NO };
        NSDictionary *keyB = @{ @"Name": @"key-b", @"IsAction": @NO };
        MGSequenceStepHandler collect = ^(NSDictionary *step) {
            [emitted addObject:[step objectForKey:@"Name"]];
            return YES;
        };
        [dispatcher dispatchSequence:@[prefix, key] stepHandler:collect];
        [dispatcher dispatchSequence:@[prefixB, keyB] stepHandler:collect];
        while ([scheduled count] > 0)
            runFirstScheduled(scheduled);
        require([emitted isEqual:@[@"prefix", @"key", @"prefix-b", @"key-b"]],
                "a queued sequence starts after the active sequence finishes");

        [scheduled removeAllObjects];
        [emitted removeAllObjects];
        [dispatcher dispatchSequence:@[prefix, key] stepHandler:collect];
        [dispatcher dispatchSequence:@[prefixB, keyB] stepHandler:collect];
        runFirstScheduled(scheduled);
        [dispatcher cancelAll];
        while ([scheduled count] > 0)
            runFirstScheduled(scheduled);
        [dispatcher dispatchSequence:@[url] stepHandler:collect];
        while ([scheduled count] > 0)
            runFirstScheduled(scheduled);
        require([emitted isEqual:@[@"prefix", @"url"]],
                "cancellation drops both the active remainder and queued sequences");

        // A step that reports failure stops its own sequence, and the next
        // queued sequence still runs.
        [scheduled removeAllObjects];
        [emitted removeAllObjects];
        MGSequenceStepHandler stopAtPrefix = ^(NSDictionary *step) {
            [emitted addObject:[step objectForKey:@"Name"]];
            return (BOOL)![[step objectForKey:@"Name"] isEqualToString:@"prefix"];
        };
        [dispatcher dispatchSequence:@[prefix, key, url] stepHandler:stopAtPrefix];
        [dispatcher dispatchSequence:@[prefixB, keyB] stepHandler:stopAtPrefix];
        while ([scheduled count] > 0)
            runFirstScheduled(scheduled);
        require([emitted isEqual:@[@"prefix", @"prefix-b", @"key-b"]],
                "a failed step stops the rest of its sequence only");

        // Limited sequences count the running one and every queued one;
        // unlimited sequences never count and are never refused.
        [scheduled removeAllObjects];
        [emitted removeAllObjects];
        require([dispatcher dispatchSequence:@[prefix] limitedTo:3 stepHandler:collect],
                "a limited sequence is admitted under its limit");
        require([dispatcher dispatchSequence:@[key] limitedTo:3 stepHandler:collect] &&
                [dispatcher dispatchSequence:@[url] limitedTo:3 stepHandler:collect],
                "limited sequences queue up to the limit");
        [dispatcher dispatchSequence:@[prefixB] stepHandler:collect];
        require(![dispatcher dispatchSequence:@[keyB] limitedTo:3 stepHandler:collect],
                "a limited sequence beyond the limit is refused");
        while ([scheduled count] > 0)
            runFirstScheduled(scheduled);
        require([emitted isEqual:@[@"prefix", @"key", @"url", @"prefix-b"]],
                "refusal leaves the admitted and unlimited sequences in order");
        require([dispatcher dispatchSequence:@[keyB] limitedTo:3 stepHandler:collect],
                "finished limited sequences free their places");
        [dispatcher cancelAll];
        require([dispatcher dispatchSequence:@[prefix] limitedTo:1 stepHandler:collect],
                "cancellation frees every limited place");

        if (failures == 0) {
            printf("sequence dispatcher: all checks passed\n");
            return 0;
        }
        fprintf(stderr, "sequence dispatcher: %d failure(s)\n", failures);
        return 1;
    }
}
