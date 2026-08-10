// Checks that deferred gestures fire once after waiting, that a second
// matching gesture cancels the pending single action, and that a repeat block
// runs in its place when one is supplied.

#import <Foundation/Foundation.h>
#import <math.h>
#import "DeferredGestureDispatcher.h"

static int failures = 0;

static void fail(const char *label) {
    fprintf(stderr, "FAIL  %s\n", label);
    failures++;
}

int main(void) {
    @autoreleasepool {
        NSMutableArray *scheduled = [NSMutableArray array];
        MGDeferredGestureScheduler scheduler = ^(NSTimeInterval delay, dispatch_block_t block) {
            [scheduled addObject:@{ @"delay": @(delay), @"block": [[block copy] autorelease] }];
        };
        MGDeferredGestureDispatcher *dispatcher =
            [[[MGDeferredGestureDispatcher alloc] initWithScheduler:scheduler] autorelease];
        __block int actions = 0;

        [dispatcher handleGestureKey:@"mouse:Two-Finger Tap" delay:0.4 action:^{ actions++; } repeat:nil];
        if ([scheduled count] != 1 ||
            fabs([[[scheduled objectAtIndex:0] objectForKey:@"delay"] doubleValue] - 0.4) > 0.0001)
            fail("first tap waits for the supplied interval");
        ((dispatch_block_t)[[scheduled objectAtIndex:0] objectForKey:@"block"])();
        if (actions != 1)
            fail("unmatched tap dispatches after waiting");

        [scheduled removeAllObjects];
        actions = 0;
        [dispatcher handleGestureKey:@"mouse:Two-Finger Tap" delay:0.4 action:^{ actions++; } repeat:nil];
        [dispatcher handleGestureKey:@"mouse:Two-Finger Tap" delay:0.4 action:^{ actions++; } repeat:nil];
        ((dispatch_block_t)[[scheduled objectAtIndex:0] objectForKey:@"block"])();
        if (actions != 0 || [scheduled count] != 1)
            fail("second matching tap cancels the pending single action");

        [scheduled removeAllObjects];
        actions = 0;
        [dispatcher handleGestureKey:@"mouse:Two-Finger Tap" delay:0.4 action:^{ actions++; } repeat:nil];
        [dispatcher handleGestureKey:@"trackpad:Two-Finger Tap" delay:0.4 action:^{ actions++; } repeat:nil];
        for (NSDictionary *item in scheduled)
            ((dispatch_block_t)[item objectForKey:@"block"])();
        if (actions != 2)
            fail("different devices keep independent pending actions");

        [scheduled removeAllObjects];
        actions = 0;
        __block int repeats = 0;
        dispatch_block_t single = ^{ actions++; };
        dispatch_block_t both = ^{ repeats++; };
        [dispatcher handleGestureKey:@"mouse:Two-Finger Tap" delay:0.4 action:single repeat:both];
        [dispatcher handleGestureKey:@"mouse:Two-Finger Tap" delay:0.4 action:single repeat:both];
        ((dispatch_block_t)[[scheduled objectAtIndex:0] objectForKey:@"block"])();
        if (actions != 0 || repeats != 1)
            fail("a repeat inside the window replaces the pending action with its own");

        // Binding only the repeat opens the window with nothing delayed, so an
        // unrepeated gesture waits for no action of its own.
        [scheduled removeAllObjects];
        repeats = 0;
        [dispatcher handleGestureKey:@"mouse:Three-Finger Tap" delay:0.4 action:nil repeat:both];
        ((dispatch_block_t)[[scheduled objectAtIndex:0] objectForKey:@"block"])();
        if (repeats != 0)
            fail("an unrepeated gesture runs nothing when only the repeat is supplied");
        [dispatcher handleGestureKey:@"mouse:Three-Finger Tap" delay:0.4 action:nil repeat:both];
        [dispatcher handleGestureKey:@"mouse:Three-Finger Tap" delay:0.4 action:nil repeat:both];
        if (repeats != 1)
            fail("a repeat runs without a pending single action");

        if (failures == 0) {
            printf("deferred gesture dispatcher: all checks passed\n");
            return 0;
        }
        fprintf(stderr, "deferred gesture dispatcher: %d failure(s)\n", failures);
        return 1;
    }
}
