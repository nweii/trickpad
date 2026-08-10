// Coordinates delayed single-gesture actions so a second matching gesture can
// cancel the pending action without coupling recognizers to dispatch timing.

#import <Foundation/Foundation.h>
#import <dispatch/dispatch.h>

typedef void (^MGDeferredGestureScheduler)(NSTimeInterval delay, dispatch_block_t block);

@interface MGDeferredGestureDispatcher : NSObject {
    NSMutableDictionary *_pendingTokens;
    NSUInteger _nextToken;
    MGDeferredGestureScheduler _scheduler;
}

- (instancetype)initWithScheduler:(MGDeferredGestureScheduler)scheduler;
- (void)handleGestureKey:(NSString *)key
                   delay:(NSTimeInterval)delay
                  action:(dispatch_block_t)action;
- (void)cancelGestureKey:(NSString *)key;

@end
