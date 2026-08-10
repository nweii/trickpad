// Coordinates delayed single-gesture actions so a second matching gesture can
// cancel the pending action, and run one of its own, without coupling
// recognizers to dispatch timing.

#import <Foundation/Foundation.h>
#import <dispatch/dispatch.h>

typedef void (^MGDeferredGestureScheduler)(NSTimeInterval delay, dispatch_block_t block);

@interface MGDeferredGestureDispatcher : NSObject {
    NSMutableDictionary *_pendingTokens;
    NSUInteger _nextToken;
    MGDeferredGestureScheduler _scheduler;
}

- (instancetype)initWithScheduler:(MGDeferredGestureScheduler)scheduler;

// Opens a window of `delay` for `key`. The first call runs `action` once the
// window closes untouched. A second call inside the window closes it early,
// drops the pending action, and runs `repeatAction` at once. Either block may
// be nil: a nil action opens the window without delaying anything, and a nil
// repeat leaves a repeat cancelling the pending action and nothing more.
- (void)handleGestureKey:(NSString *)key
                   delay:(NSTimeInterval)delay
                  action:(dispatch_block_t)action
                  repeat:(dispatch_block_t)repeatAction;
- (void)cancelGestureKey:(NSString *)key;

@end
