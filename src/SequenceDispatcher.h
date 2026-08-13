// Defines asynchronous ordered dispatch for one parsed sequence binding.

#import <Foundation/Foundation.h>
#import <dispatch/dispatch.h>

typedef void (^MGSequenceScheduler)(NSTimeInterval delay, dispatch_block_t block);
typedef void (^MGSequenceStepHandler)(NSDictionary *step);

@interface MGSequenceDispatcher : NSObject {
    NSUInteger _generation;
    MGSequenceScheduler _scheduler;
}

- (instancetype)initWithScheduler:(MGSequenceScheduler)scheduler;

// Schedules every action in order and returns before the first action runs.
- (void)dispatchSequence:(NSArray *)sequence stepHandler:(MGSequenceStepHandler)handler;

// Drops every action that has not started.
- (void)cancelAll;

@end
