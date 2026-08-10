// Implements per-device deferred gesture dispatch using replaceable scheduling,
// keeping the cancellation state deterministic and independently testable.

#import "DeferredGestureDispatcher.h"

@implementation MGDeferredGestureDispatcher

- (instancetype)initWithScheduler:(MGDeferredGestureScheduler)scheduler {
    self = [super init];
    if (self) {
        _pendingTokens = [[NSMutableDictionary alloc] init];
        _scheduler = [scheduler copy];
    }
    return self;
}

- (void)dealloc {
    [_pendingTokens release];
    [_scheduler release];
    [super dealloc];
}

- (void)handleGestureKey:(NSString *)key
                   delay:(NSTimeInterval)delay
                  action:(dispatch_block_t)action
                  repeat:(dispatch_block_t)repeatAction {
    NSNumber *token = nil;
    @synchronized (self) {
        if ([_pendingTokens objectForKey:key] == nil) {
            token = [NSNumber numberWithUnsignedInteger:++_nextToken];
            [_pendingTokens setObject:token forKey:key];
        } else {
            [_pendingTokens removeObjectForKey:key];
        }
    }

    if (token == nil) {
        if (repeatAction != nil)
            repeatAction();
        return;
    }

    _scheduler(delay, ^{
        BOOL shouldRun = NO;
        @synchronized (self) {
            if ([[_pendingTokens objectForKey:key] isEqual:token]) {
                [_pendingTokens removeObjectForKey:key];
                shouldRun = YES;
            }
        }
        if (shouldRun && action != nil)
            action();
    });
}

- (void)cancelGestureKey:(NSString *)key {
    @synchronized (self) {
        [_pendingTokens removeObjectForKey:key];
    }
}

@end
